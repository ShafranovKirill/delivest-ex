defmodule Delivest.Popular.RefreshWorker do
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  import Ecto.Query

  alias Delivest.{LocalTime, Popular, Repo}
  alias Delivest.Popular.Settings

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    Repo.all(from s in Settings, where: s.mode == :auto and (s.show_in_menu or s.show_in_cart))
    |> Enum.reduce_while(:ok, fn settings, _ ->
      result =
        if due?(settings, now),
          do: Popular.recalculate_branch(settings.branch_id, false),
          else: {:ok, settings}

      case result do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def due?(settings, now) do
    zone = LocalTime.timezone(settings.branch_id)
    date = now |> DateTime.shift_zone!(zone) |> DateTime.to_date()
    threshold = LocalTime.naive_to_utc(NaiveDateTime.new!(date, ~T[03:00:00]), zone)

    settings.mode == :auto and (settings.show_in_menu or settings.show_in_cart) and
      (is_nil(settings.calculated_at) or
         (DateTime.compare(now, threshold) != :lt and
            DateTime.compare(settings.calculated_at, threshold) == :lt))
  end
end
