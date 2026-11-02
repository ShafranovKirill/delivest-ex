defmodule Delivest.Push do
  import Ecto.Query

  require Logger

  alias Delivest.Identity.{Client, Staff}
  alias Delivest.Oms.Order

  alias Delivest.Push.{
    ClientSubscription,
    NoteWorker,
    Sender,
    StaffSubscription,
    StaffWorker,
    Subscription,
    Vapid,
    Worker
  }

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

  def notify_note(%Order{id: order_id}, note) when is_atom(note) do
    %{order_id: order_id, note: note} |> NoteWorker.new() |> Oban.insert()
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

  def subscribe_client(%Client{} = client, attrs) do
    %ClientSubscription{client_id: client.id}
    |> ClientSubscription.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:client_id, :p256dh, :auth, :locale, :updated_at]},
      conflict_target: [:client_id, :endpoint]
    )
  end

  def unsubscribe_client(%Client{} = client, endpoint) when is_binary(endpoint) do
    Repo.delete_all(
      from(s in ClientSubscription,
        where: s.client_id == ^client.id and s.endpoint == ^endpoint
      )
    )

    :ok
  end

  def unsubscribe_client(_client, _endpoint), do: :ok

  def client_subscriptions(client_id) when is_binary(client_id) do
    Repo.all(from(s in ClientSubscription, where: s.client_id == ^client_id))
  end

  @doc """
  Sends one message to every device of the client. `message` receives the
  subscription locale and returns the push payload.
  """
  def deliver_to_client(client_id, message) when is_function(message, 1) do
    client_id
    |> client_subscriptions()
    |> Enum.each(fn subscription ->
      case Sender.deliver(subscription, message.(subscription.locale || "ru")) do
        :ok ->
          :ok

        :expired ->
          Repo.delete_all(from(s in ClientSubscription, where: s.id == ^subscription.id))

        {:error, reason} ->
          Logger.warning(
            "client push to #{URI.parse(subscription.endpoint).host} failed: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  def deliver_to_client(_client_id, _message), do: :ok
end
