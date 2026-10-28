defmodule Delivest.Push do
  import Ecto.Query

  alias Delivest.Oms.Order
  alias Delivest.Push.{Subscription, Vapid, Worker}
  alias Delivest.Repo

  defdelegate public_key, to: Vapid

  def subscribe(%Order{} = order, attrs) do
    %Subscription{order_id: order.id, notified_status: to_string(order.status)}
    |> Subscription.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:p256dh, :auth, :locale, :updated_at]},
      conflict_target: [:order_id, :endpoint]
    )
  end

  def order_changed(%Order{id: order_id}) do
    if Repo.exists?(from(s in Subscription, where: s.order_id == ^order_id)),
      do: %{order_id: order_id} |> Worker.new() |> Oban.insert()

    :ok
  end
end
