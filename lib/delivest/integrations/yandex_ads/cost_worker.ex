defmodule Delivest.Integrations.YandexAds.CostWorker do
  use Oban.Worker,
    queue: :yandex_ads,
    max_attempts: 5,
    unique: [
      period: 3600,
      keys: [:generation, :from, :to, :feature_generations, :settings_version]
    ]

  import Ecto.Query
  alias Delivest.Repo
  alias Delivest.Integrations.YandexAds
  alias Delivest.Integrations.YandexAds.{Api, Cost, Settings}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"generation" => generation, "from" => raw_from, "to" => raw_to} = args
      }) do
    settings = YandexAds.get_settings()
    token = args["feature_generations"]

    with true <- settings.generation == generation and YandexAds.costs_active?(settings),
         true <- args["settings_version"] == YandexAds.cost_settings_version(settings),
         true <-
           is_map(token) and map_size(token) > 0 and token == YandexAds.costs_token(settings),
         {:ok, from} <- Date.from_iso8601(raw_from),
         {:ok, to} <- Date.from_iso8601(raw_to),
         true <- YandexAds.valid_period?(from, to),
         {:ok, campaigns} <- Api.reporting_campaigns(settings) do
      case Api.report(%{settings | cost_feature_generations: token}, from, to) do
        {:ok, rows} ->
          ids = Enum.map(campaigns, &to_string(&1["Id"])) |> MapSet.new()

          if Enum.all?(rows, &MapSet.member?(ids, &1.campaign_id)),
            do: publish(settings, from, to, rows, token),
            else: {:cancel, :unknown_report_campaign}

        {:retry, seconds} ->
          {:snooze, seconds}

        {:error, {:http_error, status, _}} when status in [401, 403] ->
          {:cancel, :access_revoked}

        _ ->
          {:error, :report_unavailable}
      end
    else
      {:error, :unsupported_currency_or_timezone} -> {:cancel, :unsupported_currency_or_timezone}
      {:error, _} -> {:error, :account_verification_unavailable}
      _ -> {:cancel, :disabled_or_invalid_period}
    end
  end

  def publish(settings, from, to, rows, token \\ nil) do
    token = token || YandexAds.costs_token(settings)

    case Repo.transaction(fn ->
           YandexAds.lock_settings()

           current = YandexAds.get_settings()

           if not YandexAds.same_cost_settings?(current, settings) or
                token != YandexAds.costs_token(current) or map_size(token) == 0 or
                not YandexAds.costs_active?(current),
              do: Repo.rollback(:disabled)

           case Delivest.Features.publish_if_enabled(YandexAds.publication_requests(token), fn ->
                  account = YandexAds.account_key(settings)

                  Repo.delete_all(
                    from(c in Cost,
                      where:
                        c.account == ^account and c.day >= ^from and
                          c.day <= ^to
                    )
                  )

                  entries =
                    Enum.map(
                      rows,
                      &Map.merge(&1, %{
                        id: Ecto.UUID.generate(),
                        generation: settings.generation,
                        account: account,
                        currency: settings.currency,
                        include_vat: settings.include_vat,
                        updated_at: YandexAds.now()
                      })
                    )

                  if entries != [], do: Repo.insert_all(Cost, entries)

                  Repo.update_all(
                    from(s in Settings,
                      where: s.id == 1 and s.generation == ^settings.generation
                    ),
                    set: [costs_refreshed_at: YandexAds.now(), costs_from: from, costs_to: to]
                  )

                  :ok
                end) do
             {:ok, :ok} -> :ok
             _ -> Repo.rollback(:disabled)
           end
         end) do
      {:ok, :ok} -> :ok
      {:error, :disabled} -> {:cancel, :disabled}
    end
  end
end
