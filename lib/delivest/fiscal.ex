defmodule Delivest.Fiscal do
  import Ecto.Query

  require Logger

  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Fiscal.{BranchSettings, Builder, PollWorker, Receipt, RegisterWorker, Registry}
  alias Delivest.Identity.Branch
  alias Delivest.Net.Product
  alias Delivest.Oms.Order
  alias Delivest.Payments.Payment

  @poll_seconds 300

  def settings(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %Branch{info: %{fiscal: %BranchSettings{} = settings}}} -> settings
      _ -> %BranchSettings{}
    end
  end

  def change_settings(%BranchSettings{} = settings, attrs \\ %{}),
    do: BranchSettings.changeset(settings, attrs)

  def update_settings(staff, branch_id, attrs) do
    with {:ok, branch} <- Identity.get_branch(branch_id, preload: :info),
         {:ok, branch} <- Identity.update_integrations(staff, branch, %{"fiscal" => attrs}) do
      {:ok, branch.info.fiscal}
    else
      {:error, :info, changeset} -> {:error, Ecto.Changeset.get_change(changeset, :fiscal)}
      {:error, _step, changeset} -> {:error, changeset}
      error -> error
    end
  end

  def health_check(branch_id) do
    settings = settings(branch_id)

    with {:ok, module} <- Registry.fetch(settings.provider),
         %{} = provider_settings <- Map.get(settings, module.key()) || {:error, :missing_settings} do
      module.health_check(provider_settings)
    end
  end

  def list(order_id),
    do:
      Repo.all(from(r in Receipt, where: r.order_id == ^order_id, order_by: [asc: r.inserted_at]))

  def get(id), do: Repo.get(Receipt, id)

  def issue(%Order{} = order, payments, opts \\ []) do
    settings = settings(order.branch_id)

    with true <- BranchSettings.own?(settings) || {:error, :not_own},
         {:ok, module} <- Registry.fetch(settings.provider),
         %{} <- Map.get(settings, module.key()) || {:error, :missing_settings},
         [_ | _] <- payments || {:error, :no_payments} do
      order = Repo.preload(order, [items: :modifiers], force: true)
      payment_id = payment_id(payments, opts)
      payments = Enum.map(payments, &Builder.payment/1)

      built =
        Builder.build(order, settings,
          payments: payments,
          kind: Keyword.get(opts, :kind, :sell),
          products: products(order),
          cashier: opts[:cashier]
        )

      %Receipt{}
      |> Receipt.changeset(%{
        order_id: order.id,
        branch_id: order.branch_id,
        payment_id: payment_id,
        refund_of_id: opts[:refund_of_id],
        issued_by_id: opts[:staff_id],
        kind: built.kind,
        stage: built.stage,
        provider: to_string(module.key()),
        amount: built.total
      })
      |> insert_with_body(module, built, Map.get(settings, module.key()))
    end
  end

  def retry(%Receipt{status: :fail} = receipt, staff) do
    order = Repo.get!(Order, receipt.order_id)

    %Receipt{}
    |> Receipt.changeset(%{
      order_id: receipt.order_id,
      branch_id: receipt.branch_id,
      payment_id: receipt.payment_id,
      refund_of_id: receipt.refund_of_id,
      issued_by_id: staff.id,
      kind: receipt.kind,
      stage: receipt.stage,
      provider: receipt.provider,
      amount: receipt.amount
    })
    |> Ecto.Changeset.put_change(:request, receipt.request)
    |> insert_and_enqueue()
    |> tap(&audit(&1, staff, "fiscal.retried", order))
  end

  def retry(_receipt, _staff), do: {:error, :not_failed}

  def refund(%Receipt{kind: :sell, status: :done} = receipt, staff) do
    order = Repo.get!(Order, receipt.order_id)

    if Repo.exists?(
         from(r in Receipt, where: r.refund_of_id == ^receipt.id and r.status != :fail)
       ) do
      {:error, :already_refunded}
    else
      payments = receipt_payments(receipt)

      order
      |> issue(payments,
        kind: :sell_refund,
        refund_of_id: receipt.id,
        staff_id: staff.id,
        payment_id: receipt.payment_id
      )
      |> tap(&audit(&1, staff, "fiscal.refunded", order))
    end
  end

  def refund(_receipt, _staff), do: {:error, :not_refundable}

  def register(%Receipt{} = receipt) do
    with {:ok, module, settings} <- provider(receipt) do
      case module.register(receipt, receipt.request, settings) do
        {:ok, result} -> apply_result(receipt, result)
        {:error, _reason} = error -> error
      end
    end
  end

  def poll(%Receipt{} = receipt) do
    with {:ok, module, settings} <- provider(receipt),
         {:ok, result} <- module.fetch(receipt, settings) do
      apply_result(receipt, result, poll: false)
    end
  end

  def handle_callback(provider, token, params) do
    with {:ok, module} <- Registry.fetch(provider),
         {:ok, uuid, result} <- module.parse_callback(params),
         %Receipt{} = receipt <- Repo.get_by(Receipt, uuid: uuid) || {:error, :not_found},
         {:ok, _module, settings} <- provider(receipt),
         true <- valid_token?(module.callback_token(settings), token) || {:error, :not_found} do
      apply_result(receipt, result)
    end
  end

  def classify_error(%Receipt{provider: provider}, reason) do
    case Registry.fetch(provider) do
      {:ok, module} -> module.classify_error(reason)
      _ -> :permanent
    end
  end

  def failed(%Receipt{} = receipt, error, attempt) do
    receipt
    |> Receipt.result_changeset(%{status: :fail, error: error, attempts: attempt})
    |> Repo.update()
  end

  def attempted(%Receipt{} = receipt, error, attempt) do
    receipt
    |> Receipt.result_changeset(%{error: error, attempts: attempt})
    |> Repo.update()
  end

  def apply_result(receipt, result, opts \\ [])

  def apply_result(%Receipt{status: status} = receipt, _result, _opts)
      when status in [:done, :fail],
      do: {:ok, receipt}

  def apply_result(%Receipt{} = receipt, result, opts) do
    with {:ok, updated} <- receipt |> Receipt.result_changeset(result) |> Repo.update() do
      if updated.status != :wait or Keyword.get(opts, :poll, true), do: after_result(updated)
      {:ok, updated}
    end
  end

  def pending_alerts(branch_id, now \\ DateTime.utc_now()) do
    stale = DateTime.add(now, -600, :second)

    Repo.all(
      from(r in Receipt,
        as: :receipt,
        where: r.branch_id == ^branch_id,
        where: r.status == :fail or (r.status in [:pending, :wait] and r.inserted_at < ^stale),
        where:
          not exists(
            from(n in Receipt,
              where:
                n.order_id == parent_as(:receipt).order_id and n.kind == parent_as(:receipt).kind,
              where:
                n.status in [:pending, :wait, :done] and
                  n.inserted_at > parent_as(:receipt).inserted_at
            )
          ),
        order_by: [desc: r.inserted_at]
      )
    )
  end

  defp after_result(%Receipt{status: :wait} = receipt) do
    %{"receipt_id" => receipt.id}
    |> PollWorker.new(schedule_in: @poll_seconds)
    |> Oban.insert()
  end

  defp after_result(%Receipt{status: :done, kind: :sell, payment_id: payment_id})
       when is_binary(payment_id) do
    Repo.update_all(from(p in Payment, where: p.id == ^payment_id), set: [fiscalized_by: :us])
  end

  defp after_result(%Receipt{status: :fail} = receipt),
    do: Logger.warning("fiscal receipt #{receipt.id} failed: #{receipt.error}")

  defp after_result(_receipt), do: :ok

  defp insert_with_body(changeset, module, built, settings) do
    receipt = Ecto.Changeset.apply_changes(changeset)
    receipt = %{receipt | id: Ecto.UUID.generate()}

    changeset
    |> Ecto.Changeset.put_change(:id, receipt.id)
    |> Ecto.Changeset.put_change(:request, json(module.body(receipt, built, settings)))
    |> insert_and_enqueue()
  end

  defp insert_and_enqueue(changeset) do
    Repo.transaction(fn ->
      with {:ok, receipt} <- Repo.insert(changeset),
           {:ok, _job} <- %{"receipt_id" => receipt.id} |> RegisterWorker.new() |> Oban.insert() do
        receipt
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp json(body), do: body |> Jason.encode!() |> Jason.decode!()

  defp provider(%Receipt{} = receipt) do
    settings = settings(receipt.branch_id)

    with {:ok, module} <- Registry.fetch(receipt.provider),
         %{} = provider_settings <- Map.get(settings, module.key()) || {:error, :missing_settings} do
      {:ok, module, provider_settings}
    end
  end

  defp valid_token?(expected, token) when is_binary(expected) and is_binary(token),
    do: Plug.Crypto.secure_compare(expected, token)

  defp valid_token?(_expected, _token), do: false

  defp products(order) do
    ids = order.items |> Enum.map(& &1.product_id) |> Enum.reject(&is_nil/1)

    from(p in Product, where: p.id in ^ids, select: {p.id, %{vat: p.vat, excise: p.excise}})
    |> Repo.all()
    |> Map.new()
  end

  defp payment_id(payments, opts) do
    case {opts[:payment_id], payments} do
      {nil, [%{id: id}]} -> id
      {id, _payments} -> id
    end
  end

  defp receipt_payments(%Receipt{request: %{"receipt" => %{"payments" => payments}}}) do
    types = %{0 => :cash, 1 => :card, 2 => :certificate}

    Enum.map(payments, fn %{"type" => type, "sum" => sum} ->
      %{method: Map.get(types, type, :card), amount: round(sum * 100)}
    end)
  end

  defp audit({:ok, receipt}, staff, action, order),
    do: Audit.record(staff, action, order, metadata: %{receipt_id: receipt.id})

  defp audit(_result, _staff, _action, _order), do: :ok
end
