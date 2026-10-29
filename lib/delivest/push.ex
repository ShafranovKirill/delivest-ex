defmodule Delivest.Push do
  import Ecto.Query

  alias Delivest.Identity.Staff
  alias Delivest.Oms.Order
  alias Delivest.Push.{StaffSubscription, StaffWorker, Subscription, Vapid, Worker}
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

  def subscribe_staff(%Staff{} = staff, attrs) do
    %StaffSubscription{staff_id: staff.id}
    |> StaffSubscription.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:staff_id, :p256dh, :auth, :updated_at]},
      conflict_target: :endpoint
    )
  end

  def unsubscribe_staff(%Staff{} = staff, endpoint) do
    Repo.delete_all(
      from(s in StaffSubscription, where: s.staff_id == ^staff.id and s.endpoint == ^endpoint)
    )

    :ok
  end

  def notify_staff(event, id) when is_atom(event) and is_binary(id) do
    %{event: event, id: id} |> StaffWorker.new() |> Oban.insert()
    :ok
  end
end
