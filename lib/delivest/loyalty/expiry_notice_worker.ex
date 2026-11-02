defmodule Delivest.Loyalty.ExpiryNoticeWorker do
  @moduledoc """
  Once a day, reminds clients that their stars will expire in a week.

  A reminder is sent once per client and expiry date, so running the job every
  day for the same batch does not produce duplicates.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Delivest.{Franchise, Identity, Push, Repo}
  alias Delivest.Loyalty.{Entry, ExpiryNotification}

  @days 7

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now(:second)
    deadline = DateTime.add(now, @days, :day)

    Entry
    |> where([e], e.kind in [:accrual, :adjust, :refund])
    |> where([e], e.remaining > 0)
    |> where([e], e.expires_at > ^now and e.expires_at <= ^deadline)
    |> select([e], %{
      client_id: e.client_id,
      branch_id: e.branch_id,
      expires_at: e.expires_at,
      remaining: e.remaining
    })
    |> Repo.all()
    |> Enum.group_by(& &1.client_id)
    |> Enum.each(&remind/1)

    :ok
  end

  defp remind({client_id, entries}) do
    first = Enum.min_by(entries, & &1.expires_at)
    expires_on = DateTime.to_date(first.expires_at)
    stars = Enum.sum(Enum.map(entries, & &1.remaining))

    if record(client_id, expires_on) do
      Push.deliver_to_client(client_id, &message(&1, first.branch_id, stars, expires_on))
    end
  end

  defp record(client_id, expires_on) do
    {count, _} =
      Repo.insert_all(
        ExpiryNotification,
        [
          %{
            id: Ecto.UUID.generate(),
            client_id: client_id,
            expires_on: expires_on,
            inserted_at: DateTime.utc_now(:second)
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:client_id, :expires_on]
      )

    count == 1
  end

  defp message(locale, branch_id, stars, expires_on) do
    settings = Franchise.get_settings()
    date = Date.to_string(expires_on)

    %{
      title: settings.name,
      body: body(locale, stars, date),
      icon: Franchise.icon_url(settings, "icon-192.png"),
      tag: "loyalty-expiry-#{expires_on}",
      url: url(branch_id)
    }
  end

  defp body("ru", stars, date),
    do: "Сгорят звёзды: #{stars}. Успейте обменять до #{date}."

  defp body(_locale, stars, date), do: "Stars expiring soon: #{stars}. Use them before #{date}."

  defp url(branch_id) do
    case Identity.get_branch(branch_id) do
      {:ok, branch} -> "/#{branch.slug}/stars"
      _error -> "/"
    end
  end
end
