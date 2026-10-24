defmodule DelivestWeb.Staff.OrderLive.KnownClient do
  alias Delivest.{Identity, Oms}

  defstruct [:client, addresses: [], orders_count: 0]

  def find(phone) when is_binary(phone) do
    with true <- Regex.match?(Identity.phone_regex(), phone),
         %{} = client <- Identity.get_active_client_by_phone(phone) do
      %__MODULE__{
        client: client,
        addresses: Identity.list_client_addresses(client.id),
        orders_count: Oms.count_client_orders(client.id)
      }
    else
      _ -> nil
    end
  end

  def find(_phone), do: nil

  def valid_phone?(phone) when is_binary(phone), do: Regex.match?(Identity.phone_regex(), phone)
  def valid_phone?(_phone), do: false

  def address(%__MODULE__{addresses: addresses}, id), do: Enum.find(addresses, &(&1.id == id))
  def address(nil, _id), do: nil

  def address_params(address) do
    Map.new(Identity.Client.Address.fields(), &{Atom.to_string(&1), Map.get(address, &1)})
  end
end
