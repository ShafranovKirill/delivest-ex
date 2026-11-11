defmodule Delivest.Advertising.Clicks do
  @moduledoc "Capture server-observed link hits and prune expiring raw click rows."
  import Ecto.Query

  alias Delivest.{Features, Repo}
  alias Delivest.Advertising.{Click, FirstSource, GuestClaim, Link}

  @retention_seconds 90 * 86_400
  @prune_batch 500

  def prune_batch, do: @prune_batch

  def capture(%Link{enabled: true, archived_at: nil} = link, actor) when is_map(actor) do
    with {:ok, actor} <- validated_actor(actor),
         {:ok, generation} <- Features.snapshot("analytics_links", {:branch, link.branch_id}) do
      case Features.with_enabled("analytics_links", {:branch, link.branch_id}, generation, fn ->
             capture_locked(link, actor)
           end) do
        {:ok, {:captured, guest_id}} -> {:ok, guest_id}
        _ -> :skipped
      end
    else
      _ -> :skipped
    end
  end

  def capture(_, _), do: :skipped

  defp validated_actor(%{client_id: client_id, guest_id: guest_id}) do
    cond do
      client_id && match?({:ok, _}, Ecto.UUID.cast(client_id)) ->
        {:ok, %{client_id: client_id, guest_id: nil}}

      is_nil(client_id) && match?({:ok, _}, Ecto.UUID.cast(guest_id)) ->
        {:ok, %{client_id: nil, guest_id: guest_id}}

      true ->
        {:error, :invalid_actor}
    end
  end

  defp validated_actor(_), do: {:error, :invalid_actor}

  defp capture_locked(link, actor) do
    # The gate lock fences archival and disable against publication.
    case Repo.one(
           from l in Link,
             where: l.id == ^link.id and l.enabled == true and is_nil(l.archived_at),
             lock: "FOR SHARE"
         ) do
      nil ->
        :skipped

      _ ->
        if actor.guest_id do
          Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
            "advertising:guest:" <> actor.guest_id
          ])
        end

        guest_id = rotate_claimed_guest(actor.guest_id)
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        Repo.insert_all(Click, [
          %{
            id: Ecto.UUID.generate(),
            link_id: link.id,
            branch_id: link.branch_id,
            guest_id: guest_id,
            client_id: actor.client_id,
            clicked_at: now
          }
        ])

        if actor.client_id do
          Repo.insert_all(
            FirstSource,
            [
              %{
                client_id: actor.client_id,
                link_id: link.id,
                landing_branch_id: link.branch_id,
                clicked_at: now,
                inserted_at: now
              }
            ],
            on_conflict: :nothing
          )
        end

        {:captured, guest_id}
    end
  end

  defp rotate_claimed_guest(nil), do: nil

  defp rotate_claimed_guest(guest_id) do
    if Repo.get(GuestClaim, guest_id), do: Ecto.UUID.generate(), else: guest_id
  end

  def prune(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@retention_seconds, :second)

    Repo.query!(
      "DELETE FROM advertising_clicks WHERE id IN (SELECT id FROM advertising_clicks WHERE clicked_at < $1 ORDER BY clicked_at, id LIMIT $2 FOR UPDATE SKIP LOCKED)",
      [cutoff, @prune_batch]
    ).num_rows
  end

  def prune_claims(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@retention_seconds, :second)

    Repo.query!(
      "DELETE FROM advertising_guest_claims WHERE guest_id IN (SELECT g.guest_id FROM advertising_guest_claims g WHERE g.claimed_at < $1 AND NOT EXISTS (SELECT 1 FROM advertising_clicks c WHERE c.guest_id = g.guest_id) ORDER BY g.claimed_at, g.guest_id LIMIT $2 FOR UPDATE SKIP LOCKED)",
      [cutoff, @prune_batch]
    ).num_rows
  end
end
