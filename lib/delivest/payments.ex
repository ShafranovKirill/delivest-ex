defmodule Delivest.Payments do
  import Ecto.Query

  alias Delivest.Couriers.Delivery
  alias Delivest.Identity
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.{BranchInfo, PaymentSettings}
  alias Delivest.Identity.Staff
  alias Delivest.Integrations.Yookassa
  alias Delivest.Oms.{Order, OrderEvents, OrderFlow}
  alias Delivest.Payments.{Payment, Refund}
  alias Delivest.Repo

  @offline %{cash: :cash, card_offline: :card}
  @open [:pending, :authorized]

  @type balance :: :unpaid | :partially_paid | :paid | :overpaid | :refunded

  def settings(%Branch{info: %BranchInfo{payments: %PaymentSettings{} = payments}}), do: payments

  def settings(%Branch{id: id}) do
    case Identity.get_branch(id, preload: :info) do
      {:ok, %Branch{info: %BranchInfo{payments: %PaymentSettings{} = payments}}} -> payments
      _ -> %PaymentSettings{}
    end
  end

  def enabled_methods(%Branch{} = branch),
    do: branch |> settings() |> PaymentSettings.enabled(Yookassa.ready?())

  def list(order_id) do
    Repo.all(
      from(p in Payment,
        where: p.order_id == ^order_id,
        order_by: [asc: p.inserted_at],
        preload: :refunds
      )
    )
  end

  @spec balance(Order.t()) :: balance()
  def balance(%Order{} = order), do: balance(order.total_amount, list(order.id))

  @spec balance(integer(), [Payment.t()]) :: balance()
  def balance(total, payments) do
    paid = paid(payments)
    net = paid - refunded(payments)

    cond do
      paid == 0 and total > 0 -> :unpaid
      net == 0 and paid > 0 -> :refunded
      net < total -> :partially_paid
      net == total -> :paid
      true -> :overpaid
    end
  end

  def due(%Order{} = order) do
    payments = list(order.id)
    order.total_amount - paid(payments) + refunded(payments)
  end

  def open(repo, %Order{} = order, opts \\ []) do
    cond do
      order.awaiting_payment ->
        insert(repo, order, :system, %{
          method: :online,
          amount: order.total_amount,
          status: :pending,
          provider: "yookassa"
        })

      opts[:paid_online] && order.channel ->
        insert(repo, order, :channel, %{
          method: :aggregator,
          amount: order.total_amount,
          status: :paid,
          provider: order.source,
          fiscalized_by: :aggregator,
          paid_at: DateTime.utc_now(:second)
        })

      method = @offline[order.payment_method] ->
        expect(repo, order, method, opts[:cash_given])

      true ->
        {:ok, nil}
    end
  end

  def sync(repo, %Order{} = order) do
    payments = repo.all(from(p in Payment, where: p.order_id == ^order.id, preload: :refunds))

    with {:ok, _adjusted} <- adjust_online(repo, order, payments) do
      sync_offline(repo, order, payments)
    end
  end

  defp adjust_online(repo, order, payments) do
    payments
    |> Enum.filter(&(&1.method == :online and &1.provider == "yookassa"))
    |> each(&adjust_online_payment(repo, order, &1))
  end

  defp adjust_online_payment(repo, order, %Payment{status: :authorized} = payment) do
    target = min(order.total_amount, get_in(payment.details, ["hold_amount"]) || payment.amount)

    if target > 0 and target != payment.amount,
      do: payment |> Payment.resize_changeset(target) |> repo.update(),
      else: {:ok, payment}
  end

  defp adjust_online_payment(_repo, order, %Payment{status: :paid} = payment) do
    excess = payment.amount - taken(payment.id) - order.total_amount

    if excess > 0 and not order.awaiting_payment do
      with {:ok, _refund} <- refund(payment, excess, %{reason: "order changed"}),
           do: {:ok, payment}
    else
      {:ok, payment}
    end
  end

  defp adjust_online_payment(_repo, _order, payment), do: {:ok, payment}

  defp sync_offline(repo, order, payments) do
    pending = Enum.find(payments, &(&1.status == :pending and &1.method in [:cash, :card]))
    due = order.total_amount - paid(payments) + refunded(payments)
    method = @offline[order.payment_method]

    cond do
      pending && (due <= 0 or is_nil(method)) ->
        move(repo, order, pending, :cancelled, :system)

      pending ->
        cash_given =
          if method == :cash and (pending.cash_given || 0) >= due, do: pending.cash_given

        pending
        |> Payment.amount_changeset(%{amount: due, method: method, cash_given: cash_given})
        |> repo.update()

      method && due > 0 && order.status not in [:completed, :cancelled] ->
        expect(repo, order, method, nil)

      true ->
        {:ok, nil}
    end
  end

  def collect(repo, %Order{} = order, by), do: settle(repo, order, by)

  def advance(repo, %Order{} = order, %Payment{} = payment, to, by, attrs \\ %{}),
    do: move(repo, order, payment, to, by, attrs)

  def on_status(_repo, _order, [], _by), do: {:ok, nil}

  def on_status(repo, %Order{} = order, steps, by) do
    case List.last(steps) do
      {_from, :completed} -> settle(repo, order, by)
      {_from, :cancelled} -> cancel_open(repo, order, by)
      _step -> {:ok, nil}
    end
  end

  def reopenable?(%Payment{} = payment) do
    payment.status == :paid and payment.method in [:cash, :card] and is_nil(payment.settlement_id) and
      payment.fiscalized_by in [nil, :none] and
      Enum.all?(payment.refunds, &(&1.status == :failed))
  end

  def reopen(repo, %Order{} = order, by) do
    repo.all(from(p in Payment, where: p.order_id == ^order.id, preload: :refunds))
    |> Enum.filter(&reopenable?/1)
    |> each(&move(repo, order, &1, :pending, by, %{paid_at: nil, collected_by_id: nil}))
  end

  def refund(payment, amount, attrs \\ %{}, by \\ :system)

  def refund(%Payment{status: :paid} = payment, amount, attrs, by) do
    Repo.transaction(fn ->
      payment = Repo.one!(from(p in Payment, where: p.id == ^payment.id, lock: "FOR UPDATE"))
      left = payment.amount - taken(payment.id)
      instant? = payment.method in [:cash, :card]

      with :ok <- check_amount(amount, left),
           {:ok, refund} <- insert_refund(payment, amount, attrs, by, instant?),
           :ok <- enqueue_remote(payment, refund),
           order = Repo.get!(Order, payment.order_id),
           {:ok, _event} <- event(Repo, order, payment, "refund", by) do
        refund
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def refund(%Payment{}, _amount, _attrs, _by), do: {:error, :not_paid}

  defp settle(repo, order, by) do
    payments = repo.all(from(p in Payment, where: p.order_id == ^order.id, preload: :refunds))
    open = Enum.filter(payments, &(&1.status in @open))
    attrs = Map.put(collector(repo, order, by), :paid_at, DateTime.utc_now(:second))
    move_attrs = Map.take(attrs, [:paid_at, :collected_by_id])

    offline = Enum.filter(open, &(&1.method in [:cash, :card]))

    with {:ok, _moved} <- each(offline, &move(repo, order, &1, :paid, by, move_attrs)) do
      due =
        order.total_amount - paid(payments) - Enum.sum(Enum.map(open, & &1.amount)) +
          refunded(payments)

      case @offline[order.payment_method] do
        method when is_atom(method) and not is_nil(method) and due > 0 ->
          insert(repo, order, by, Map.merge(attrs, %{method: method, amount: due, status: :paid}))

        _none ->
          {:ok, nil}
      end
    end
  end

  defp collector(repo, order, by) do
    case staff_id(by) do
      nil -> courier(repo, order.id)
      id -> %{collected_by_id: id}
    end
  end

  defp courier(repo, order_id) do
    query =
      from(d in Delivery,
        where: d.order_id == ^order_id and d.status in [:picked_up, :delivered],
        order_by: [desc: d.inserted_at],
        limit: 1,
        select: {d.provider, d.courier_id}
      )

    case repo.one(query) do
      {:staff, courier_id} -> %{collected_by_id: courier_id}
      {:yandex, _courier_id} -> %{collected_by_id: nil, provider: "yandex_delivery"}
      _none -> %{collected_by_id: nil}
    end
  end

  defp cancel_open(repo, order, by) do
    repo.all(from(p in Payment, where: p.order_id == ^order.id and p.status in ^@open))
    |> each(&move(repo, order, &1, :cancelled, by))
  end

  defp expect(repo, order, method, cash_given) do
    insert(repo, order, :system, %{
      method: method,
      amount: order.total_amount,
      status: :pending,
      cash_given: if(method == :cash and (cash_given || 0) >= order.total_amount, do: cash_given)
    })
  end

  defp insert(_repo, %Order{total_amount: total}, _by, _attrs) when total <= 0, do: {:ok, nil}

  defp insert(repo, order, by, attrs) do
    params = Map.merge(attrs, %{order_id: order.id, branch_id: order.branch_id})

    with {:ok, payment} <- %Payment{} |> Payment.changeset(params) |> repo.insert(),
         {:ok, _event} <- event(repo, order, payment, "created", by) do
      {:ok, payment}
    end
  end

  defp move(repo, order, payment, to, by, attrs \\ %{}) do
    with {:ok, payment} <- payment |> Payment.move_changeset(to, attrs) |> repo.update(),
         {:ok, _event} <- event(repo, order, payment, to, by) do
      {:ok, payment}
    end
  end

  defp insert_refund(payment, amount, attrs, by, instant?) do
    %Refund{}
    |> Refund.changeset(
      Map.merge(attrs, %{
        payment_id: payment.id,
        order_id: payment.order_id,
        amount: amount,
        status: if(instant?, do: :succeeded, else: :pending),
        refunded_at: if(instant?, do: DateTime.utc_now(:second)),
        refunded_by_id: staff_id(by)
      })
    )
    |> Repo.insert()
  end

  defp enqueue_remote(%Payment{method: :online, provider: "yookassa"}, %Refund{} = refund) do
    case %{refund_id: refund.id}
         |> Delivest.Payments.Online.RefundWorker.new()
         |> Oban.insert() do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp enqueue_remote(_payment, _refund), do: :ok

  defp check_amount(amount, left) when is_integer(amount) and amount > 0 and amount <= left,
    do: :ok

  defp check_amount(_amount, _left), do: {:error, :refund_too_large}

  defp taken(payment_id) do
    Repo.one(
      from(r in Refund,
        where: r.payment_id == ^payment_id and r.status in [:pending, :succeeded],
        select: coalesce(sum(r.amount), 0)
      )
    )
  end

  defp event(repo, order, payment, change, by) do
    OrderEvents.payment_changed(repo, order, payment, change, OrderEvents.actor(by, order))
  end

  defp each(list, fun) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        error -> {:halt, error}
      end
    end)
  end

  defp paid(payments),
    do: payments |> Enum.filter(&(&1.status == :paid)) |> Enum.map(& &1.amount) |> Enum.sum()

  defp refunded(payments) do
    payments
    |> Enum.flat_map(&loaded_refunds/1)
    |> Enum.filter(&(&1.status == :succeeded))
    |> Enum.map(& &1.amount)
    |> Enum.sum()
  end

  defp loaded_refunds(%Payment{refunds: refunds}) when is_list(refunds), do: refunds
  defp loaded_refunds(_payment), do: []

  defp staff_id(%Staff{id: id}), do: id
  defp staff_id(by), do: by |> OrderFlow.staff() |> then(&(&1 && &1.id))
end
