defmodule Delivest.Funnel do
  @moduledoc "Bounded, opt-in raw funnel capture. Source labels are unverified client claims."

  alias Delivest.{Features, Repo}

  @events ~w(visit menu_view product_view cart_add checkout_start fulfillment_selected)
  @source_types ~w(direct campaign unknown)
  @fields ~w(event_id branch_id event source_type utm_source utm_medium utm_campaign)
  @idle_seconds 30 * 60
  @retention_seconds 90 * 86_400
  @prune_batch 500

  def prune_batch, do: @prune_batch

  def capture(attrs, owner_key) when is_map(attrs) and is_binary(owner_key) do
    with {:ok, event} <- validate(attrs),
         {:ok, token} <- Features.snapshot("analytics_funnel", {:branch, event.branch_id}),
         {:ok, session_id} <-
           Features.with_enabled("analytics_funnel", {:branch, event.branch_id}, token, fn ->
             record(event, owner_key)
           end) do
      {:ok, %{event_id: event.event_id, session_id: session_id}}
    else
      {:error, :invalid_payload} -> {:error, :invalid_payload}
      _ -> {:error, :disabled}
    end
  end

  def capture(_, _), do: {:error, :invalid_payload}

  defp validate(attrs) do
    with true <- Enum.all?(Map.keys(attrs), &(&1 in @fields)),
         {:ok, event_id} <- uuid(attrs["event_id"]),
         {:ok, branch_id} <- uuid(attrs["branch_id"]),
         event when event in @events <- attrs["event"],
         source_type when source_type in @source_types <- Map.get(attrs, "source_type", "unknown"),
         {:ok, source} <- slug(attrs["utm_source"]),
         {:ok, medium} <- slug(attrs["utm_medium"]),
         {:ok, campaign} <- slug(attrs["utm_campaign"]),
         true <- source_type == "campaign" or Enum.all?([source, medium, campaign], &is_nil/1) do
      {:ok,
       %{
         event_id: event_id,
         branch_id: branch_id,
         event: event,
         source_type: source_type,
         utm_source: source,
         utm_medium: medium,
         utm_campaign: campaign
       }}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  defp uuid(value) when is_binary(value), do: Ecto.UUID.cast(value)
  defp uuid(_), do: :error

  defp slug(nil), do: {:ok, nil}

  defp slug(value) when is_binary(value) and byte_size(value) <= 64 do
    digits = String.replace(value, ~r/[-_]/, "")

    if Regex.match?(~r/^[a-z0-9]+(?:[-_][a-z0-9]+)*$/, value) and
         not Regex.match?(~r/^\d{7,}$/, digits),
       do: {:ok, value},
       else: :error
  end

  defp slug(_), do: :error

  defp record(event, owner_key) do
    # The gate rows are locked by with_enabled. This lock serializes this owner's
    # session updates without creating any optional row before the dedupe lookup.
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      event.branch_id <> ":" <> owner_key
    ])

    active =
      Repo.query!(
        "SELECT 1 FROM branches WHERE id = $1::text::uuid AND is_active = true AND deleted_at IS NULL",
        [event.branch_id]
      ).num_rows == 1

    if not active, do: Repo.rollback(:disabled)

    duplicate =
      Repo.query!(
        "SELECT session_id::text FROM funnel_events WHERE branch_id = $1::text::uuid AND owner_key = $2 AND event_id = $3::text::uuid",
        [event.branch_id, owner_key, event.event_id]
      ).rows

    case duplicate do
      [[session_id]] -> session_id
      [] -> insert_event(event, owner_key)
    end
  end

  defp insert_event(event, owner_key) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    rows =
      Repo.query!(
        "SELECT id::text, last_at FROM funnel_sessions WHERE branch_id = $1::text::uuid AND owner_key = $2 ORDER BY last_at DESC LIMIT 1 FOR UPDATE",
        [event.branch_id, owner_key]
      ).rows

    session_id =
      case rows do
        [[id, last_at]] ->
          if NaiveDateTime.diff(DateTime.to_naive(now), to_naive(last_at), :microsecond) <
               @idle_seconds * 1_000_000 do
            Repo.query!("UPDATE funnel_sessions SET last_at = $1 WHERE id = $2::text::uuid", [
              now,
              id
            ])

            id
          else
            new_session(event.branch_id, owner_key, now)
          end

        _ ->
          new_session(event.branch_id, owner_key, now)
      end

    Repo.query!(
      "INSERT INTO funnel_events (event_id, branch_id, owner_key, session_id, event, source_type, utm_source, utm_medium, utm_campaign, received_at) VALUES ($1::text::uuid, $2::text::uuid, $3, $4::text::uuid, $5, $6, $7, $8, $9, $10)",
      [
        event.event_id,
        event.branch_id,
        owner_key,
        session_id,
        event.event,
        event.source_type,
        event.utm_source,
        event.utm_medium,
        event.utm_campaign,
        now
      ]
    )

    session_id
  end

  defp to_naive(%DateTime{} = value), do: DateTime.to_naive(value)
  defp to_naive(%NaiveDateTime{} = value), do: value

  defp new_session(branch_id, owner_key, now) do
    id = Ecto.UUID.generate()

    Repo.query!(
      "INSERT INTO funnel_sessions (id, branch_id, owner_key, started_at, last_at) VALUES ($1::text::uuid, $2::text::uuid, $3, $4, $4)",
      [id, branch_id, owner_key, now]
    )

    id
  end

  @doc "Delete at most 500 old events and 500 old sessions per daily maintenance run."
  def prune(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@retention_seconds, :second)

    events =
      Repo.query!(
        "DELETE FROM funnel_events WHERE id IN (SELECT id FROM funnel_events WHERE received_at < $1 ORDER BY received_at, id LIMIT $2 FOR UPDATE SKIP LOCKED)",
        [cutoff, @prune_batch]
      ).num_rows

    sessions =
      Repo.query!(
        "DELETE FROM funnel_sessions WHERE id IN (SELECT id FROM funnel_sessions WHERE last_at < $1 AND NOT EXISTS (SELECT 1 FROM funnel_events WHERE funnel_events.session_id = funnel_sessions.id) ORDER BY last_at, id LIMIT $2 FOR UPDATE SKIP LOCKED)",
        [cutoff, @prune_batch]
      ).num_rows

    %{events: events, sessions: sessions}
  end
end
