defmodule Delivest.Integrations.YandexAds.ScheduleWorker do
  @moduledoc "Optional account-wide import; no per-branch duplicate reports. Also runs bounded retention."
  use Oban.Worker, queue: :yandex_ads, max_attempts: 1
  import Ecto.Query
  alias Delivest.Repo
  alias Delivest.Integrations.YandexAds
  alias Delivest.Integrations.YandexAds.{Identity, OrderReceipt, CostWorker, Conversion, Cost}

  @impl Oban.Worker
  def perform(_) do
    settings = YandexAds.get_settings()

    if YandexAds.costs_active?(settings) do
      today = YandexAds.now() |> DateTime.shift_zone!(settings.timezone) |> DateTime.to_date()
      # Reconcile a rolling week including corrected and deleted provider rows.
      %{
        generation: settings.generation,
        from: Date.to_iso8601(Date.add(today, -7)),
        to: Date.to_iso8601(today),
        feature_generations: YandexAds.costs_token(settings)
      }
      |> CostWorker.new()
      |> Oban.insert()
    end

    prune()
    :ok
  end

  def prune do
    cutoff = DateTime.add(YandexAds.now(), -90 * 86_400)
    ids = Repo.all(from(i in Identity, where: i.updated_at < ^cutoff, select: i.id, limit: 500))
    Repo.delete_all(from(i in Identity, where: i.id in ^ids))

    ids =
      Repo.all(
        from(r in OrderReceipt, where: r.inserted_at < ^cutoff, select: r.order_id, limit: 500)
      )

    Repo.delete_all(from(r in OrderReceipt, where: r.order_id in ^ids))

    ids =
      Repo.all(
        from(c in Conversion,
          where:
            c.inserted_at < ^cutoff and
              fragment(
                "jsonb_exists(?, 'client_id') OR jsonb_exists(?, 'yclid')",
                c.payload,
                c.payload
              ),
          select: c.id,
          limit: 500
        )
      )

    Repo.update_all(from(c in Conversion, where: c.id in ^ids),
      set: [payload: %{}, reason: "raw_identifier_retention_expired", updated_at: YandexAds.now()]
    )

    Repo.update_all(
      from(c in Conversion, where: c.id in ^ids and c.status in ["pending", "sending"]),
      set: [status: "skipped"]
    )

    aggregate_cutoff = YandexAds.now() |> DateTime.to_date() |> Date.shift(month: -36)
    ids = Repo.all(from(c in Cost, where: c.day < ^aggregate_cutoff, select: c.id, limit: 500))
    Repo.delete_all(from(c in Cost, where: c.id in ^ids))
    :ok
  end
end
