defmodule Delivest.Integrations.YandexAds.ConversionWorker do
  @moduledoc "Claim, send once, then poll. Unknown writes are never blindly replayed."
  use Oban.Worker,
    queue: :yandex_ads,
    max_attempts: 8,
    unique: [
      period: :infinity,
      keys: [:conversion_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  import Ecto.Query
  alias Delivest.Repo
  alias Delivest.Integrations.YandexAds
  alias Delivest.Integrations.YandexAds.{Api, Conversion}
  alias Delivest.Oms.Order

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"conversion_id" => id}}) do
    case claim(id) do
      {:ok, {:send, row}} -> send_conversion(row)
      {:ok, {:poll, row}} -> poll(row)
      _ -> :ok
    end
  end

  defp claim(id) do
    Repo.transaction(fn ->
      row = Repo.one(from(c in Conversion, where: c.id == ^id, lock: "FOR UPDATE"))
      settings = YandexAds.get_settings()

      cond do
        is_nil(row) ->
          :done

        row.status not in ["pending", "sending", "submitted"] ->
          :done

        not eligible?(row, settings) ->
          persist(row, status: "stale", reason: "disabled_or_connection_changed")
          :done

        row.status == "submitted" ->
          {:poll, row}

        row.status == "sending" ->
          persist(row, status: "unknown", reason: "interrupted_send_requires_reconciliation")
          :done

        row.status != "pending" ->
          :done

        Repo.get(Order, row.order_id).status != :completed ->
          persist(row, status: "reverted", reason: "order_not_completed")
          :done

        true ->
          {:send, persist(row, status: "sending", attempted_at: YandexAds.now())}
      end
    end)
  end

  defp send_conversion(row) do
    settings = YandexAds.get_settings()

    if eligible?(row, settings) and current_completed?(row) do
      case prepare(row) do
        {:ok, payload} ->
          if eligible?(row, YandexAds.get_settings()) and current_completed?(row) do
            handle_result(row, deliver(settings, row.channel, payload))
          else
            persist(row, status: "stale", reason: "disabled_before_send")
            :ok
          end

        {:skip, reason} ->
          persist(row, status: "skipped", reason: reason)
          :ok
      end
    else
      persist(row, status: "stale", reason: "disabled_or_order_changed")
      :ok
    end
  end

  def prepare(%Conversion{channel: "offline"} = row) do
    payload = row.payload
    age = DateTime.diff(YandexAds.now(), DateTime.from_iso8601(payload["captured_at"]) |> elem(1))

    identifiers =
      [{"ClientId", payload["client_id"]}, {"Yclid", payload["yclid"]}]
      |> Enum.filter(fn {_key, value} -> is_binary(value) and value != "" end)

    cond do
      age >= 20 * 86_400 -> {:skip, "identifier_window_expired"}
      identifiers != [] -> {:ok, csv(row, identifiers)}
      true -> {:skip, "missing_identifier"}
    end
  end

  def prepare(%Conversion{channel: "ecommerce"} = row) do
    payload = row.payload
    {:ok, captured_at, _} = DateTime.from_iso8601(payload["captured_at"])
    branch = Repo.get(Delivest.Identity.Branch, row.branch_id)

    landing =
      if branch,
        do: DelivestWeb.AdvertisingDestination.for_branch(branch.slug),
        else: {:error, :unknown_branch}

    cond do
      not is_binary(payload["client_id"]) ->
        {:skip, "missing_client_id"}

      DateTime.diff(YandexAds.now(), captured_at) >= 12 * 3600 ->
        {:skip, "measurement_window_expired"}

      not match?({:ok, _}, landing) ->
        {:skip, "invalid_public_origin"}

      true ->
        params = %{
          cid: payload["client_id"],
          t: "event",
          pa: "purchase",
          ti: row.order_id,
          tr: money(row.amount),
          cu: "RUB",
          et: Integer.to_string(DateTime.to_unix(row.occurred_at)),
          dl: elem(landing, 1)
        }

        params =
          Enum.with_index(payload["items"] || [], 1)
          |> Enum.reduce(params, fn {item, index}, values ->
            Map.merge(values, %{
              "pr#{index}id" => item["id"],
              "pr#{index}nm" => item["name"],
              "pr#{index}pr" => money(item["price"]),
              "pr#{index}qt" => item["quantity"]
            })
          end)

        if byte_size(URI.encode_query(params)) < 900_000,
          do: {:ok, params},
          else: {:skip, "measurement_payload_too_large"}
    end
  end

  def csv(row, identifier, value), do: csv(row, [{identifier, value}])

  def csv(row, identifiers) do
    header = Enum.map(identifiers, &elem(&1, 0)) ++ ~w(Target DateTime Price Currency)

    values =
      Enum.map(identifiers, &elem(&1, 1)) ++
        [row.payload["goal"], DateTime.to_unix(row.occurred_at), money(row.amount), "RUB"]

    Enum.join(header, ",") <> "\n" <> Enum.join(values, ",") <> "\n"
  end

  def money(amount) when is_integer(amount) and amount >= 0,
    do:
      "#{div(amount, 100)}.#{amount |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  defp deliver(settings, "offline", csv), do: Api.upload(settings, csv)
  defp deliver(settings, "ecommerce", params), do: Api.purchase(settings, params)

  defp handle_result(row, {:ok, %{status: status, body: body}}) when status in 200..299 do
    if row.channel == "offline" do
      case body do
        %{"uploading" => %{"id" => id}} when is_integer(id) or is_binary(id) ->
          update_unless_reverted(row,
            status: "submitted",
            upload_id: to_string(id),
            provider_status: "accepted_not_matched"
          )

          {:snooze, 60}

        _ ->
          update_unless_reverted(row, status: "unknown", reason: "upload_id_missing")
          :ok
      end
    else
      update_unless_reverted(row,
        status: "submitted",
        provider_status: "request_accepted_event_not_confirmed"
      )

      :ok
    end
  end

  defp handle_result(row, {:error, {:http_error, 429, _}}) do
    update_unless_reverted(row, status: "pending", reason: "rate_limited")
    {:snooze, 60}
  end

  defp handle_result(row, {:error, {:http_error, status, _}}) when status in 400..499 do
    update_unless_reverted(row, status: "failed", reason: "provider_rejected_#{status}")
    :ok
  end

  defp handle_result(row, _) do
    update_unless_reverted(row,
      status: "unknown",
      reason: "write_outcome_unknown_requires_reconciliation"
    )

    :ok
  end

  defp poll(%Conversion{channel: "ecommerce"}), do: :ok

  defp poll(row) do
    settings = YandexAds.get_settings()

    if eligible?(row, settings) do
      case Api.upload_status(settings, row.upload_id) do
        {:ok, %{body: %{"uploading" => upload}}} ->
          status = upload["status"]

          cond do
            status in ["PROCESSED", "MATCHED"] and upload["line_quantity"] == 0 ->
              update_unless_reverted(row,
                status: "failed",
                provider_status: status,
                reason: "provider_validated_zero_rows"
              )

              :ok

            status in ["PROCESSED", "MATCHED"] ->
              update_unless_reverted(row,
                status: "processed",
                provider_status: status,
                reason: "processing_confirmed_matching_not_proven"
              )

              :ok

            status == "LINKAGE_FAILURE" ->
              update_unless_reverted(row,
                status: "failed",
                provider_status: status,
                reason: "linkage_failure"
              )

              :ok

            true ->
              update_unless_reverted(row, provider_status: status)
              {:snooze, 120}
          end

        {:error, {:http_error, status, _}} when status in [401, 403, 404] ->
          update_unless_reverted(row, reason: "poll_unavailable_#{status}")
          :ok

        _ ->
          {:snooze, 120}
      end
    else
      update_unless_reverted(row, status: "stale", reason: "disabled_before_poll")
      :ok
    end
  end

  defp eligible?(row, settings),
    do:
      row.generation == settings.generation and row.counter_id == settings.counter_id and
        YandexAds.valid_feature_token?(
          if(row.channel == "offline", do: :conversions, else: :ecommerce),
          row.branch_id,
          row.payload["feature_generation"]
        ) and
        YandexAds.enabled?(
          settings,
          if(row.channel == "offline", do: :conversions, else: :ecommerce),
          row.branch_id
        )

  defp current_completed?(row),
    do: match?(%Order{status: :completed, deleted_at: nil}, Repo.get(Order, row.order_id))

  defp persist(row, attrs), do: row |> Ecto.Changeset.change(attrs) |> Repo.update!()

  defp update_unless_reverted(row, attrs) do
    Repo.update_all(
      from(c in Conversion, where: c.id == ^row.id and c.status in ["sending", "submitted"]),
      set: Keyword.put(attrs, :updated_at, YandexAds.now())
    )
  end
end
