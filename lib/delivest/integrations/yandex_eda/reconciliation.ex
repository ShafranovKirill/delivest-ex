defmodule Delivest.Integrations.YandexEda.Reconciliation do
  import Ecto.Query

  alias Delivest.{LocalTime, Repo}
  alias Delivest.Integrations.YandexEda.{Clock, PushApi}
  alias Delivest.Oms.Order

  @provider "yandex_eda"
  @page 1000

  def run(settings, branch_id, %Date{} = date) do
    zone = LocalTime.timezone(branch_id)
    from = LocalTime.start_of_day_utc(date, zone)
    to = DateTime.add(LocalTime.end_of_day_utc(date, zone), 1, :second)

    with {:ok, remote} <- history(settings, branch_id, from, to, 0, []) do
      ours = ours(branch_id, from, to, Enum.map(remote, & &1["eats_id"]))
      rows = Enum.map(remote, &remote_row(&1, Map.get(ours, &1["eats_id"])))
      known = MapSet.new(remote, & &1["eats_id"])

      extra =
        for {eats_id, order} <- ours,
            not MapSet.member?(known, eats_id),
            do: %{eats_id: eats_id, order: order, remote: nil, problem: :not_in_yandex}

      {:ok, %{total: length(remote), problems: Enum.reject(rows ++ extra, &is_nil(&1.problem))}}
    end
  end

  defp history(settings, branch_id, from, to, offset, acc) do
    filter = %{
      origin_ids: [%{origin_id: branch_id}],
      from: Clock.format(from),
      to: Clock.format(to),
      pagination: %{limit: @page, offset: offset}
    }

    with {:ok, orders} <- PushApi.orders_history(settings, filter) do
      if length(orders) == @page,
        do: history(settings, branch_id, from, to, offset + @page, acc ++ orders),
        else: {:ok, acc ++ orders}
    end
  end

  defp ours(branch_id, from, to, eats_ids) do
    from(o in Order,
      where: o.branch_id == ^branch_id and o.source == @provider and is_nil(o.deleted_at),
      where:
        fragment("?->>'external_id' = ANY(?)", o.channel, ^eats_ids) or
          (o.inserted_at >= ^from and o.inserted_at < ^to)
    )
    |> Repo.all()
    |> Map.new(&{&1.channel.external_id, &1})
  end

  defp remote_row(remote, order) do
    %{
      eats_id: remote["eats_id"],
      order: order,
      remote: remote,
      problem: problem(remote["status"], order)
    }
  end

  defp problem(_status, nil), do: :missing

  defp problem("CANCELLED", %Order{status: status}) when status != :cancelled,
    do: :cancelled_in_yandex

  defp problem("DELIVERED", %Order{status: :cancelled}), do: :cancelled_here
  defp problem(_status, _order), do: nil
end
