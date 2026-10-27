defmodule Delivest.Integrations.YandexEda.OrderConfirmation do
  import Ecto.Query

  alias Delivest.{Identity, Repo}
  alias Delivest.Integrations.YandexEda.AcceptDeadlineWorker
  alias Delivest.Oms.{Order, Orders}

  @provider "yandex_eda"

  def watch(%Order{} = order) do
    with %DateTime{} = deadline <- accept_by(order) do
      %{"order_id" => order.id}
      |> AcceptDeadlineWorker.new(scheduled_at: deadline)
      |> Oban.insert()
    end

    :ok
  end

  def overdue(branch_id, now \\ DateTime.utc_now()) do
    from(o in Order,
      where: o.branch_id == ^branch_id and o.source == @provider,
      where: o.status == :created and is_nil(o.deleted_at),
      where: fragment("(?->'details'->>'accept_by')::timestamptz < ?", o.channel, ^now),
      where: fragment("coalesce(?->'details'->>'alert_dismissed', 'false') <> 'true'", o.channel),
      order_by: [asc: o.inserted_at]
    )
    |> Repo.all()
  end

  def keep(staff, branch_id, order_id) do
    with {:ok, order} <- fetch(staff, branch_id, order_id) do
      Orders.update_order_channel(order, %{
        details: Map.put(order.channel.details, "alert_dismissed", true)
      })
    end
  end

  def accept(staff, branch_id, order_id) do
    with {:ok, order} <- fetch(staff, branch_id, order_id) do
      Orders.update_order_details(order, details(order, "accepted"), staff)
    end
  end

  def cancel(staff, branch_id, order_id) do
    with {:ok, order} <- fetch(staff, branch_id, order_id) do
      attrs = order |> details("cancelled") |> Map.put("cancel_reason", "not_confirmed")
      Orders.update_order_details(order, attrs, staff)
    end
  end

  def accept_by(%Order{channel: %{details: %{"accept_by" => value}}}) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  def accept_by(_order), do: nil

  defp details(order, status),
    do: %{"status" => status, "payment_method" => to_string(order.payment_method)}

  defp fetch(staff, branch_id, order_id) do
    with true <- Identity.can?(staff, "orders.update") || {:error, :forbidden},
         {:ok, uuid} <- Ecto.UUID.cast(order_id),
         %Order{status: :created} = order <-
           Repo.get_by(Order, id: uuid, branch_id: branch_id, source: @provider) do
      {:ok, order}
    else
      {:error, :forbidden} -> {:error, :forbidden}
      _ -> {:error, :order_not_found}
    end
  end
end
