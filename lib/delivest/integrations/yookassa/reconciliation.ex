defmodule Delivest.Integrations.Yookassa.Reconciliation do
  @behaviour Delivest.Integrations.Poller

  import Ecto.Query

  require Logger

  alias Delivest.Integrations.{Health, Journal, Yookassa}
  alias Delivest.Integrations.Yookassa.Api
  alias Delivest.Payments.{Online, Payment}
  alias Delivest.Repo

  @window_hours 48
  @page 100
  @max_pages 50
  @remote %{
    pending: ["pending"],
    authorized: ["waiting_for_capture"],
    paid: ["succeeded"],
    cancelled: ["canceled"],
    failed: ["canceled"]
  }

  @impl true
  def key, do: :yookassa_reconcile

  @impl true
  def interval, do: 86_400

  @impl true
  def targets, do: if(Yookassa.configured?(), do: ["all"], else: [])

  @impl true
  def poll(_target) do
    now = DateTime.utc_now()

    case fetch(Yookassa.get_settings(), DateTime.add(now, -@window_hours, :hour), now) do
      {:ok, remote} ->
        report(run(remote, now))
        emit(:complete)
        :done

      {:error, {:incomplete, reason}} = error ->
        Logger.error("yookassa reconciliation incomplete: #{inspect(reason)}")
        Health.warn(:yookassa, nil, "reconcile_incomplete:#{reason}")
        emit(:incomplete)
        error

      error ->
        emit(:error)
        error
    end
  end

  def run(remote, now \\ DateTime.utc_now()) do
    since = DateTime.add(now, -@window_hours, :hour)
    by_id = Map.new(remote, &{&1["id"], &1})

    local =
      Repo.all(
        from(p in Payment,
          where:
            p.provider == "yookassa" and not is_nil(p.external_id) and p.inserted_at >= ^since
        )
      )

    stale_pending = DateTime.add(now, -1, :hour)

    issues =
      Enum.flat_map(local, fn payment ->
        case Map.fetch(by_id, payment.external_id) do
          :error -> [{:missing, payment.external_id}]
          {:ok, body} -> compare(payment, body, stale_pending)
        end
      end)

    known = MapSet.new(local, & &1.external_id)

    unknown =
      for {id, body} <- by_id,
          not MapSet.member?(known, id),
          get_in(body, ["metadata", "payment_id"]) != nil,
          do: {:unknown, id}

    issues ++ unknown
  end

  defp compare(payment, body, stale_pending) do
    cond do
      body["status"] not in Map.get(@remote, payment.status, []) ->
        heal(payment, body, stale_pending)

      amount_differs?(payment, body) ->
        [{:amount, payment.external_id}]

      true ->
        []
    end
  end

  defp heal(payment, body, stale_pending) do
    if payment.status == :pending and DateTime.compare(payment.updated_at, stale_pending) == :gt do
      []
    else
      case Online.apply_remote(body) do
        {:ok, :unchanged} -> [{:status, payment.external_id}]
        {:ok, _changed} -> []
        {:error, _reason} -> [{:status, payment.external_id}]
      end
    end
  end

  defp amount_differs?(%Payment{status: status} = payment, body) when status in [:paid] do
    Api.parse_amount(body["amount"]) != {:ok, payment.amount}
  end

  defp amount_differs?(payment, body) do
    expected = get_in(payment.details, ["hold_amount"]) || payment.amount
    Api.parse_amount(body["amount"]) != {:ok, expected}
  end

  defp fetch(settings, from, to) do
    Journal.scope([], fn -> page(settings, from, to, nil, [], 0, MapSet.new()) end)
  end

  defp page(_settings, _from, _to, _cursor, _acc, @max_pages, _seen),
    do: {:error, {:incomplete, :page_limit}}

  defp page(settings, from, to, cursor, acc, count, seen) do
    params =
      [
        {"created_at.gte", DateTime.to_iso8601(from)},
        {"created_at.lt", DateTime.to_iso8601(to)},
        {"limit", @page}
      ] ++ if(cursor, do: [{"cursor", cursor}], else: [])

    with {:ok, %{"items" => items} = body} when is_list(items) <-
           Api.list_payments(settings, params) do
      if Enum.all?(items, &(is_map(&1) and is_binary(&1["id"]))) do
        acc = [items | acc]

        case body["next_cursor"] do
          nil ->
            {:ok, acc |> Enum.reverse() |> List.flatten()}

          next when is_binary(next) and next != "" ->
            if MapSet.member?(seen, next) or next == cursor do
              {:error, {:incomplete, :repeated_cursor}}
            else
              page(settings, from, to, next, acc, count + 1, MapSet.put(seen, next))
            end

          _cursor ->
            {:error, {:incomplete, :invalid_cursor}}
        end
      else
        {:error, {:incomplete, :invalid_page}}
      end
    else
      {:ok, _body} -> {:error, {:incomplete, :invalid_page}}
      error -> error
    end
  end

  defp report([]), do: Health.clear_warning(:yookassa, nil)

  defp report(issues) do
    Logger.error(
      "yookassa reconciliation found #{length(issues)} differences: #{inspect(issues)}"
    )

    Health.warn(:yookassa, nil, "reconcile_issues:#{length(issues)}")
  end

  defp emit(result) do
    :telemetry.execute([:delivest, :yookassa, :reconciliation], %{count: 1}, %{result: result})
  end
end
