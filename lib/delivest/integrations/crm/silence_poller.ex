defmodule Delivest.Integrations.Crm.SilencePoller do
  @behaviour Delivest.Integrations.Poller

  use Gettext, backend: DelivestWeb.Gettext

  import Ecto.Query

  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.Lookup
  alias Delivest.Oms.{Order, OrderDeadline, Orders}
  alias Delivest.Repo

  @provider "frontpad"
  @open_statuses [:accepted, :preparing, :ready, :delivering]
  @grace_minutes 30

  @impl true
  def key, do: :crm_silence

  @impl true
  def interval, do: 600

  @impl true
  def targets do
    Enum.filter(Lookup.crm_branch_ids(), &(Crm.default_provider(&1) == String.to_atom(@provider)))
  end

  @impl true
  def poll(branch_id), do: poll(branch_id, DateTime.utc_now())

  def poll(branch_id, now) do
    delivery_minutes = OrderDeadline.delivery_minutes(branch_id)

    branch_id
    |> silent_orders(delivery_minutes, now)
    |> Enum.each(&raise_alert/1)

    :done
  end

  def silent?(%Order{crm: crm} = order, delivery_minutes, now) do
    threshold = DateTime.add(OrderDeadline.at(order, delivery_minutes), @grace_minutes, :minute)
    last_change = crm.remote_status_at || crm.sent_at || order.inserted_at

    DateTime.compare(now, threshold) == :gt and
      DateTime.compare(last_change, DateTime.add(now, -@grace_minutes, :minute)) == :lt
  end

  defp silent_orders(branch_id, delivery_minutes, now) do
    from(o in Order,
      where: o.branch_id == ^branch_id and is_nil(o.deleted_at),
      where: o.status in ^@open_statuses,
      where: fragment("?->>'provider' = ?", o.crm, ^@provider),
      where: fragment("?->>'status' = 'sent'", o.crm),
      where: fragment("coalesce(?->>'alert', '') = ''", o.crm)
    )
    |> Repo.all()
    |> Enum.filter(&silent?(&1, delivery_minutes, now))
  end

  defp raise_alert(order) do
    Orders.update_order_crm(order, %{
      alert:
        gettext(
          "Frontpad has not changed the status of order %{number} for a long time. Check the order in Frontpad",
          number: order.number
        )
    })
  end
end
