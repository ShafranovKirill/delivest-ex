defmodule Delivest.Oms.OrderFlow do
  alias Delivest.Identity
  alias Delivest.Identity.Staff
  alias Delivest.Oms.Order

  @type source :: :staff | :courier | :crm | :channel | :delivery | :system | :client
  @type by :: {:staff | :courier, Staff.t()} | :crm | :channel | :delivery | :system | :client
  @type step :: {Order.status(), Order.status()}

  @path [:created, :accepted, :preparing, :ready, :delivering, :completed]
  @final [:completed, :cancelled]
  @leaping [:crm, :channel, :delivery, :system, :client]
  @rank @path |> Enum.with_index() |> Map.new() |> Map.put(:cancelled, length(@path))

  @staff_permissions %{
    accepted: ["orders.update", "pos.use"],
    preparing: ["orders.cook", "orders.update"],
    ready: ["orders.cook", "orders.update"],
    delivering: ["orders.update"],
    completed: ["orders.update", "pos.use"],
    cancelled: ["orders.update"]
  }
  @courier_steps [:delivering, :completed]
  @revert_permission "orders.revert"

  def final, do: @final

  def active?(%Order{status: status}), do: status not in @final

  def path(%Order{} = order),
    do: if(Order.courier_leg?(order), do: @path, else: List.delete(@path, :delivering))

  def ahead?(nil, _to), do: true
  def ahead?(_from, :cancelled), do: true
  def ahead?(from, to), do: Map.fetch!(@rank, to) > Map.fetch!(@rank, from)

  def next(%Order{status: status} = order) do
    order |> path() |> Enum.drop_while(&(&1 != status)) |> Enum.at(1)
  end

  def source({kind, %Staff{}}) when kind in [:staff, :courier], do: kind
  def source(kind) when kind in @leaping, do: kind

  def staff({_kind, %Staff{} = staff}), do: staff
  def staff(_by), do: nil

  def leaping?(by), do: source(by) in @leaping

  @spec steps(Order.t(), Order.status(), by()) ::
          {:ok, [step()]} | {:ignored, atom()} | {:error, atom()}
  def steps(%Order{} = order, to, by) do
    to = settle_target(order, to, by)

    cond do
      to == order.status -> {:ok, []}
      order.status in @final -> refuse(by, :finished)
      order.awaiting_payment and to != :cancelled -> refuse(by, :awaiting_payment)
      to == :cancelled -> permit(order, [{order.status, :cancelled}], by)
      true -> forward(order, to, by)
    end
  end

  def can?(%Order{} = order, to, by), do: match?({:ok, [_ | _]}, steps(order, to, by))

  def can_revert?(%Staff{} = staff, %Order{branch_id: branch_id}),
    do: Identity.authorize(staff, @revert_permission, branch_id) == :ok

  def can_revert?(_staff, _order), do: false

  defp settle_target(%Order{} = order, :delivering, by) do
    if leaping?(by) and not Order.courier_leg?(order), do: :ready, else: :delivering
  end

  defp settle_target(_order, to, _by), do: to

  defp forward(order, to, by) do
    path = path(order)
    from_index = Enum.find_index(path, &(&1 == order.status))
    to_index = Enum.find_index(path, &(&1 == to))

    cond do
      is_nil(to_index) -> refuse(by, :unreachable)
      is_nil(from_index) and leaping?(by) -> {:ok, [{order.status, to}]}
      is_nil(from_index) -> {:error, :unreachable}
      to_index <= from_index -> refuse(by, :backward)
      true -> permit(order, path |> Enum.slice(from_index..to_index) |> pairs(), by)
    end
  end

  defp pairs(statuses),
    do: statuses |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&List.to_tuple/1)

  defp permit(_order, steps, by) when by in @leaping, do: {:ok, steps}

  defp permit(_order, [_, _ | _], _by), do: {:error, :skipped_step}

  defp permit(%Order{} = order, [{_from, to}] = steps, {:staff, staff}) do
    cond do
      Order.crm_managed?(order) -> {:error, :order_locked}
      authorized?(staff, Map.fetch!(@staff_permissions, to), order.branch_id) -> {:ok, steps}
      true -> {:error, :forbidden}
    end
  end

  defp permit(%Order{} = order, [{_from, to}] = steps, {:courier, _staff}) do
    if to in @courier_steps and order.fulfillment_type == :delivery,
      do: {:ok, steps},
      else: {:error, :forbidden}
  end

  defp refuse(by, reason) do
    if leaping?(by), do: {:ignored, reason}, else: {:error, reason}
  end

  defp authorized?(staff, permissions, branch_id),
    do: Enum.any?(permissions, &(Identity.authorize(staff, &1, branch_id) == :ok))
end
