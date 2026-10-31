defmodule Delivest.Couriers.Contact do
  alias Delivest.Couriers.Delivery
  alias Delivest.Identity.Staff

  @shown [:assigned, :picked_up]

  def build(%Delivery{status: status} = delivery) when status in @shown, do: contact(delivery)
  def build(_delivery), do: nil

  defp contact(%Delivery{provider: :staff, courier: %Staff{} = courier}),
    do: %{name: courier.name, phone: courier.phone, tracking_url: nil}

  defp contact(%Delivery{
         provider: :yandex,
         details: %{"performer" => %{"name" => name}} = details
       }),
       do: %{name: name, phone: details["phone"], tracking_url: details["tracking_url"]}

  defp contact(_delivery), do: nil
end
