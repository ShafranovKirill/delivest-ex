defmodule Delivest.Oms.Kitchen do
  import Ecto.Query

  require Logger

  alias Delivest.{Identity, Push, Repo}
  alias Delivest.Identity.{Branch, Staff}
  alias Delivest.Identity.Branch.{BranchInfo, KitchenSettings}
  alias Delivest.Gateway
  alias Delivest.Oms.{Order, OrderDeadline, OrderFlow, Orders, OrderTransition}
  alias Delivest.Oms.Kitchen.{ReadyWorker, SendWorker}

  @undo_seconds 10
  @upcoming_minutes 60
  @pending_states ~w(scheduled available executing retryable)

  def undo_seconds, do: @undo_seconds

  def account?(%Staff{} = staff),
    do: Identity.can?(staff, "orders.cook") and not Identity.can?(staff, "orders.update")

  def account?(_staff), do: false

  def subscribe(branch_id), do: Phoenix.PubSub.subscribe(Delivest.PubSub, topic(branch_id))

  def unsubscribe(branch_id), do: Phoenix.PubSub.unsubscribe(Delivest.PubSub, topic(branch_id))

  def subscribe_availability(branch_id),
    do: Phoenix.PubSub.subscribe(Delivest.PubSub, availability_topic(branch_id))

  def unsubscribe_availability(branch_id),
    do: Phoenix.PubSub.unsubscribe(Delivest.PubSub, availability_topic(branch_id))

  def notify_availability(branch_id),
    do:
      Phoenix.PubSub.broadcast(
        Delivest.PubSub,
        availability_topic(branch_id),
        {:kitchen_availability, branch_id}
      )

  def working(%Branch{} = branch) do
    case unavailable_reason(branch) do
      nil -> branch.info.kitchen
      _reason -> nil
    end
  end

  def working(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %Branch{} = branch} -> working(branch)
      _error -> nil
    end
  end

  def working?(%Branch{} = branch), do: working(branch) != nil
  def working?(branch_id), do: working(branch_id) != nil

  @doc """
  Why the branch kitchen cannot be used in the app, or `nil` when it can.

  `:disabled` — the kitchen is off in the branch settings.
  `:crm` — the kitchen belongs to the CRM and is not available in the app.
  """
  def unavailable_reason(
        %Branch{info: %BranchInfo{kitchen: %KitchenSettings{enabled: true}}} = branch
      ) do
    if Gateway.own?(branch, :kitchen), do: nil, else: :crm
  end

  def unavailable_reason(%Branch{}), do: :disabled

  def unavailable_reason(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %Branch{} = branch} -> unavailable_reason(branch)
      _error -> :disabled
    end
  end

  @doc """
  The single access rule for the kitchen screen and its commands.

  The staff member needs branch access and `orders.cook`, and the branch kitchen
  must be enabled and owned by this app.
  """
  def available?(%Staff{} = staff, %Branch{} = branch) do
    Identity.has_branch_access?(staff, branch.id) and
      Identity.can?(staff, "orders.cook") and
      working?(branch)
  end

  def available?(%Staff{} = staff, branch_id) when is_binary(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %Branch{} = branch} -> available?(staff, branch)
      _error -> false
    end
  end

  def available?(_staff, _branch), do: false

  def sends_at(%Order{cook_by: nil}, _kitchen), do: nil

  def sends_at(%Order{cook_by: cook_by}, %KitchenSettings{lead_minutes: lead}),
    do: DateTime.add(cook_by, -lead, :minute)

  def due?(%Order{} = order, %KitchenSettings{} = kitchen, now) do
    case sends_at(order, kitchen) do
      nil -> true
      at -> DateTime.compare(at, now) != :gt
    end
  end

  def order_accepted(%Order{status: :accepted, crm: nil} = order) do
    with %KitchenSettings{} = kitchen <- working(order.branch_id) do
      case sends_at(order, kitchen) do
        nil ->
          send_now(order)

        at ->
          if DateTime.compare(at, DateTime.utc_now()) == :gt do
            schedule_send(order, at)
          else
            send_now(order)
          end
      end
    else
      _ -> {:ok, order}
    end
  end

  def order_accepted(order), do: {:ok, order}

  @doc """
  Sends an accepted order when its time has come, otherwise asks Oban to wait.

  Called by `SendWorker`. A retry with an early time becomes a snooze instead
  of a second job, so the uniqueness on `order_id` stays intact.
  """
  def send_due(order_id) do
    with %Order{status: :accepted, crm: nil, deleted_at: nil} = order <-
           Repo.get(Order, order_id),
         %KitchenSettings{} = kitchen <- working(order.branch_id) do
      case sends_at(order, kitchen) do
        nil ->
          send_to_kitchen(order)

        at ->
          now = DateTime.utc_now()

          if DateTime.compare(at, now) == :gt,
            do: {:snooze, max(DateTime.diff(at, now, :second), 1)},
            else: send_to_kitchen(order)
      end
    else
      _ -> :ok
    end
  end

  @doc """
  Plans the kitchen send again after the kitchen settings or the CRM changed.

  A branch that lost its own kitchen drops every pending send; an enabled one
  replans accepted orders, sending the ones whose time has already come.
  """
  def reschedule_branch(branch_id) do
    case working(branch_id) do
      %KitchenSettings{} = _kitchen ->
        accepted(branch_id) |> Enum.each(&order_accepted/1)

      _ ->
        cancel_sends(fn query ->
          where(query, [j], fragment("?->>'branch_id' = ?", j.args, ^branch_id))
        end)
    end

    :ok
  end

  @doc "Drops planned sends when an order is no longer waiting for the kitchen."
  def cancel_send(order_id) do
    cancel_sends(fn query ->
      where(query, [j], fragment("?->>'order_id' = ?", j.args, ^order_id))
    end)

    :ok
  end

  def dispatch_due(now \\ DateTime.utc_now()) do
    Order
    |> join(:inner, [o], i in BranchInfo, on: i.branch_id == o.branch_id)
    |> where([o], o.status == :accepted and is_nil(o.crm) and is_nil(o.deleted_at))
    |> where([_o, i], fragment("(?->>'enabled')::boolean", i.kitchen))
    |> where(
      [o, i],
      is_nil(o.cook_by) or
        fragment(
          "? - make_interval(mins => (?->>'lead_minutes')::integer) <= ?",
          o.cook_by,
          i.kitchen,
          ^now
        )
    )
    |> Repo.all()
    |> Enum.filter(&working?(&1.branch_id))
    |> Enum.map(&send_to_kitchen/1)
  end

  def list_cooking(branch_id) do
    orders =
      Order
      |> where([o], o.branch_id == ^branch_id and o.status == :preparing)
      |> where([o], is_nil(o.crm) and is_nil(o.deleted_at))
      |> preload(items: :modifiers)
      |> Repo.all()

    started = started_at(Enum.map(orders, & &1.id))
    delivery_minutes = OrderDeadline.delivery_minutes(branch_id)

    orders
    |> Enum.map(fn order ->
      %{
        order: order,
        deadline: OrderDeadline.at(order, delivery_minutes),
        started_at: Map.get(started, order.id, order.updated_at)
      }
    end)
    |> Enum.sort_by(& &1.deadline, DateTime)
  end

  def list_upcoming(branch_id, %KitchenSettings{lead_minutes: lead} = kitchen, now) do
    horizon = DateTime.add(now, @upcoming_minutes, :minute)
    latest = DateTime.add(horizon, lead, :minute)

    Order
    |> where([o], o.branch_id == ^branch_id and o.status == :accepted)
    |> where([o], is_nil(o.crm) and is_nil(o.deleted_at))
    |> where([o], not is_nil(o.cook_by) and o.cook_by <= ^latest)
    |> order_by([o], asc: o.cook_by)
    |> Repo.all()
    |> Enum.map(&%{order: &1, sends_at: sends_at(&1, kitchen)})
  end

  def list_late(branch_id, now \\ DateTime.utc_now()) do
    Order
    |> where([o], o.branch_id == ^branch_id and o.status == :preparing)
    |> where([o], is_nil(o.crm) and is_nil(o.deleted_at))
    |> where([o], o.cook_by < ^now)
    |> order_by([o], asc: o.cook_by)
    |> Repo.all()
  end

  def pending_ready(branch_id) do
    Oban.Job
    |> where([j], j.worker == ^Oban.Worker.to_string(ReadyWorker))
    |> where([j], j.state in @pending_states)
    |> where([j], fragment("?->>'branch_id' = ?", j.args, ^branch_id))
    |> select([j], {fragment("?->>'order_id'", j.args), j.scheduled_at})
    |> Repo.all()
    |> Map.new()
  end

  def mark_ready(%Staff{} = staff, branch_id, order_id) do
    with :ok <- Identity.authorize(staff, "orders.cook", branch_id),
         true <- available?(staff, branch_id) || {:error, :kitchen_unavailable},
         {:ok, order} <- fetch(branch_id, order_id),
         true <- OrderFlow.can?(order, :ready, {:staff, staff}) || {:error, :forbidden},
         {:ok, _job} <-
           %{order_id: order.id, branch_id: branch_id, staff_id: staff.id}
           |> ReadyWorker.new(schedule_in: @undo_seconds)
           |> Oban.insert() do
      changed(branch_id)
      {:ok, order}
    end
  end

  def undo_ready(%Staff{} = staff, branch_id, order_id) do
    with :ok <- Identity.authorize(staff, "orders.cook", branch_id),
         true <- available?(staff, branch_id) || {:error, :kitchen_unavailable} do
      {:ok, count} =
        Oban.Job
        |> where([j], j.worker == ^Oban.Worker.to_string(ReadyWorker))
        |> where([j], j.state in ["scheduled", "available"])
        |> where([j], fragment("?->>'order_id' = ?", j.args, ^order_id))
        |> where([j], fragment("?->>'branch_id' = ?", j.args, ^branch_id))
        |> Oban.cancel_all_jobs()

      changed(branch_id)
      if count > 0, do: :ok, else: {:error, :too_late}
    end
  end

  def finish_ready(order_id, staff_id) do
    with %Order{} = order <- Repo.get(Order, order_id),
         {:ok, staff} <- Identity.get_staff(staff_id, preload: [:role, :branches]),
         true <- available?(staff, order.branch_id) || {:error, :kitchen_unavailable} do
      result = Orders.advance_order(order, :ready, {:staff, staff})
      changed(order.branch_id)

      with {:ok, %Order{status: :ready} = ready} <- result do
        broadcast(order.branch_id, {:kitchen_order_ready, ready})
        Push.notify_staff(:order_ready, ready.id)
      end

      result
    else
      {:error, :kitchen_unavailable} -> {:error, :kitchen_unavailable}
      _ -> {:error, :order_not_found}
    end
  end

  def changed(branch_id), do: broadcast(branch_id, {:kitchen_changed, branch_id})

  defp fetch(branch_id, order_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(order_id),
         %Order{status: :preparing, deleted_at: nil} = order <-
           Repo.get_by(Order, id: uuid, branch_id: branch_id) do
      {:ok, order}
    else
      _ -> {:error, :order_not_found}
    end
  end

  defp send_to_kitchen(order), do: Orders.advance_order(order, :preparing, :system)

  defp send_now(order) do
    case send_to_kitchen(order) do
      {:ok, sent} ->
        {:ok, sent}

      {:error, reason} ->
        Logger.warning("order #{order.number}: not sent to the kitchen (#{inspect(reason)})")
        {:ok, order}
    end
  end

  defp schedule_send(order, at) do
    cancel_send(order.id)

    %{order_id: order.id, branch_id: order.branch_id}
    |> SendWorker.new(scheduled_at: at)
    |> Oban.insert()

    {:ok, order}
  end

  defp accepted(branch_id) do
    Order
    |> where([o], o.branch_id == ^branch_id and o.status == :accepted)
    |> where([o], is_nil(o.crm) and is_nil(o.deleted_at))
    |> Repo.all()
  end

  defp cancel_sends(filter) do
    Oban.Job
    |> where([j], j.worker == ^Oban.Worker.to_string(SendWorker))
    |> where([j], j.state in ["available", "scheduled", "retryable"])
    |> filter.()
    |> Oban.cancel_all_jobs()
  end

  defp started_at([]), do: %{}

  defp started_at(order_ids) do
    OrderTransition
    |> where([t], t.order_id in ^order_ids and t.to == :preparing and is_nil(t.reverted_at))
    |> group_by([t], t.order_id)
    |> select([t], {t.order_id, max(t.inserted_at)})
    |> Repo.all()
    |> Map.new()
  end

  defp broadcast(branch_id, message),
    do: Phoenix.PubSub.broadcast(Delivest.PubSub, topic(branch_id), message)

  defp topic(branch_id), do: "kitchen:#{branch_id}"
  defp availability_topic(branch_id), do: "kitchen_availability:#{branch_id}"
end
