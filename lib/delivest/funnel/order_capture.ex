defmodule Delivest.Funnel.OrderCapture do
  @moduledoc "Captures the unverified funnel session in the fresh order transaction."
  import Ecto.Query

  alias Delivest.Funnel.OrderReceipt
  alias Delivest.Repo

  def capture(order, owner_key, as_of_at) when is_binary(owner_key) do
    cutoff = DateTime.add(as_of_at, -30 * 60, :second)

    session =
      Repo.query!(
        """
        SELECT s.id::text, s.started_at, latest.received_at
        FROM funnel_sessions s
        JOIN LATERAL (
          SELECT e.received_at
          FROM funnel_events e
          WHERE e.session_id=s.id AND e.received_at >= $3 AND e.received_at <= $4
          ORDER BY e.received_at DESC, e.id DESC
          LIMIT 1
        ) latest ON TRUE
        WHERE s.branch_id=$1::text::uuid AND s.owner_key=$2
          AND s.started_at <= $4 AND s.last_at >= $3
        ORDER BY latest.received_at DESC, s.id DESC
        LIMIT 1
        """,
        [order.branch_id, owner_key, DateTime.to_naive(cutoff), DateTime.to_naive(as_of_at)]
      ).rows
      |> case do
        [[id, started_at, last_at]] -> %{id: id, started_at: started_at, last_at: last_at}
        _ -> nil
      end

    if session do
      source =
        Repo.one(
          from e in "funnel_events",
            where: e.session_id == type(^session.id, :binary_id) and e.received_at <= ^as_of_at,
            order_by: [asc: e.received_at, asc: e.id],
            select: %{
              source_type: e.source_type,
              utm_source: e.utm_source,
              utm_medium: e.utm_medium,
              utm_campaign: e.utm_campaign
            },
            limit: 1
        )

      Repo.insert_all(
        OrderReceipt,
        [
          %{
            order_id: order.id,
            session_id: session.id,
            owner_kind:
              if(String.starts_with?(owner_key, "client:"), do: "client", else: "guest"),
            session_started_at: DateTime.from_naive!(session.started_at, "Etc/UTC"),
            session_last_at: DateTime.from_naive!(session.last_at, "Etc/UTC"),
            source_type: (source && source.source_type) || "unknown",
            utm_source: source && source.utm_source,
            utm_medium: source && source.utm_medium,
            utm_campaign: source && source.utm_campaign,
            as_of_at: as_of_at,
            inserted_at: as_of_at
          }
        ],
        on_conflict: :nothing
      )
    end

    :ok
  end

  def capture(_, _, _), do: :ok
end
