defmodule DelivestWeb.Client.Address.AddressJSON do
  alias Delivest.Identity.Client.Address

  def index(%{addresses: addresses}), do: %{data: Enum.map(addresses, &address/1)}

  def show(%{address: address}), do: %{data: address(address)}

  defp address(address), do: address |> Map.take([:id | Address.fields()])
end
