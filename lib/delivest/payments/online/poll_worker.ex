defmodule Delivest.Payments.Online.PollWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  require Logger

  alias Delivest.Integrations.Yookassa
  alias Delivest.Payments.{Online, Payment}
  alias Delivest.Repo

  @quiet_seconds 120
  @limit 100

  @impl Oban.Worker
  def perform(_job) do
    if Yookassa.configured?(), do: poll(DateTime.utc_now())
    :ok
  end

  def poll(now) do
    cutoff = DateTime.add(now, -@quiet_seconds, :second)

    from(p in Payment,
      where: p.provider == "yookassa" and p.status == :pending and not is_nil(p.external_id),
      where: p.updated_at < ^cutoff,
      order_by: p.updated_at,
      limit: @limit,
      select: p.external_id
    )
    |> Repo.all()
    |> Enum.map(fn id -> {id, Online.sync(id)} end)
    |> tap(&log/1)
  end

  defp log(results) do
    for {id, {:error, reason}} <- results,
        do: Logger.warning("yookassa payment #{id} was not polled: #{inspect(reason)}")
  end
end
