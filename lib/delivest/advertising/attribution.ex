defmodule Delivest.Advertising.Attribution do
  @moduledoc "Trusted last touch and immutable first observed source selectors."
  import Ecto.Query

  alias Delivest.Repo
  alias Delivest.Advertising.{Click, FirstSource, GuestClaim}

  @window_seconds 7 * 86_400

  def last_touch(client_id, guest_id, as_of \\ DateTime.utc_now()) do
    lower = DateTime.add(as_of, -@window_seconds, :second)

    direct =
      if client_id do
        latest(from(c in Click, where: c.client_id == ^client_id), lower, as_of)
      end

    mapped =
      if client_id do
        latest(
          from(c in Click,
            join: claim in GuestClaim,
            on: claim.guest_id == c.guest_id,
            where: claim.client_id == ^client_id and is_nil(c.client_id)
          ),
          lower,
          as_of
        )
      end

    unclaimed =
      if guest_id && is_nil(Repo.get(GuestClaim, guest_id)) do
        latest(
          from(c in Click, where: c.guest_id == ^guest_id and is_nil(c.client_id)),
          lower,
          as_of
        )
      end

    [direct, mapped, unclaimed]
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&{DateTime.to_unix(&1.clicked_at, :microsecond), &1.id}, fn -> nil end)
  end

  defp latest(query, lower, as_of) do
    query
    |> where([c], c.clicked_at >= ^lower and c.clicked_at <= ^as_of)
    |> order_by([c], desc: c.clicked_at, desc: c.id)
    |> limit(1)
    |> Repo.one()
  end

  def first_source(client_id), do: Repo.get(FirstSource, client_id)

  def claim(client_id, guest_id, as_of \\ DateTime.utc_now())

  def claim(client_id, guest_id, as_of) when is_binary(client_id) and is_binary(guest_id) do
    with {:ok, client_id} <- Ecto.UUID.cast(client_id),
         {:ok, guest_id} <- Ecto.UUID.cast(guest_id) do
      if Repo.in_transaction?(),
        do: {:ok, claim_locked(client_id, guest_id, as_of)},
        else: Repo.transaction(fn -> claim_locked(client_id, guest_id, as_of) end)
    else
      _ -> {:error, :invalid_identity}
    end
  end

  def claim(_, _, _), do: {:error, :invalid_identity}

  defp claim_locked(client_id, guest_id, as_of) do
    for key <- Enum.sort(["advertising:client:" <> client_id, "advertising:guest:" <> guest_id]) do
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])
    end

    claimed =
      case Repo.get(GuestClaim, guest_id) do
        nil -> bind_new_guest(client_id, guest_id, as_of)
        _existing -> 0
      end

    %{claimed: claimed, first_source: Repo.get(FirstSource, client_id)}
  end

  defp bind_new_guest(client_id, guest_id, as_of) do
    lower = DateTime.add(as_of, -90 * 86_400, :second)

    earliest =
      Repo.one(
        from c in Click,
          where:
            c.guest_id == ^guest_id and is_nil(c.client_id) and c.clicked_at >= ^lower and
              c.clicked_at <= ^as_of,
          order_by: [asc: c.clicked_at, asc: c.id],
          limit: 1
      )

    if earliest do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      Repo.insert!(%GuestClaim{guest_id: guest_id, client_id: client_id, claimed_at: now})

      Repo.insert_all(
        FirstSource,
        [
          %{
            client_id: client_id,
            link_id: earliest.link_id,
            landing_branch_id: earliest.branch_id,
            clicked_at: earliest.clicked_at,
            inserted_at: now
          }
        ],
        on_conflict: :nothing
      )

      1
    else
      0
    end
  end
end
