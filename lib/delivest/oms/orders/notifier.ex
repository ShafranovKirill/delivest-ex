defmodule Delivest.Oms.Orders.Notifier do
  alias Delivest.Repo

  @source Delivest.Oms.Orders
  @topic inspect(@source)

  def subscribe, do: Phoenix.PubSub.subscribe(Delivest.PubSub, @topic)

  def publish({:ok, order}, event) do
    order = Repo.preload(order, [:items, :client], force: true)
    Phoenix.PubSub.broadcast(Delivest.PubSub, @topic, {@source, event, order})
    {:ok, order}
  end

  def publish(error, _event), do: error
end
