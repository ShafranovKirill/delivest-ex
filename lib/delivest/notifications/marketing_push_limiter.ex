defmodule Delivest.Notifications.MarketingPushLimiter do
  @moduledoc "Claims a client-wide marketing Push budget at the first delivery attempt."
  import Ecto.Query

  alias Delivest.Franchise.Settings
  alias Delivest.Notifications.MarketingPushReservation
  alias Delivest.Repo

  # The transaction also makes standalone calls safe; inside Features.with_enabled_many
  # it shares the existing short transaction and its source-generation locks.
  def claim(intent_id, client_id) do
    {:ok, result} = Repo.transaction(fn -> claim_locked(intent_id, client_id) end)
    result
  end

  defp claim_locked(intent_id, client_id) do
    Repo.query!(
      "SELECT pg_advisory_xact_lock(hashtextextended('marketing-push:client:' || $1, 0))",
      [client_id]
    )

    settings = Repo.one(from s in Settings, lock: "FOR SHARE") || %Settings{}
    now = DateTime.utc_now(:microsecond)
    window = settings.marketing_push_window_hours * 3_600

    case Repo.get(MarketingPushReservation, intent_id) do
      %MarketingPushReservation{client_id: ^client_id, reserved_at: reserved_at} ->
        if DateTime.diff(now, reserved_at, :microsecond) < window * 1_000_000,
          do: :reserved,
          else: :stale

      %MarketingPushReservation{} ->
        raise ArgumentError, "marketing Push intent belongs to another client"

      nil ->
        cutoff = DateTime.add(now, -window, :second)

        count =
          Repo.all(
            from(r in MarketingPushReservation,
              where: r.client_id == ^client_id and r.reserved_at > ^cutoff,
              select: r.intent_id,
              limit: ^settings.marketing_push_limit_count
            )
          )
          |> length()

        if count < settings.marketing_push_limit_count do
          Repo.insert!(%MarketingPushReservation{
            intent_id: intent_id,
            client_id: client_id,
            reserved_at: now
          })

          :reserved
        else
          :limited
        end
    end
  end
end
