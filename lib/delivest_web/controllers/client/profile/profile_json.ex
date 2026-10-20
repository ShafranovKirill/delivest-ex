defmodule DelivestWeb.Client.Profile.ProfileJSON do
  def show(%{client: client}), do: %{data: client(client)}

  def client(client), do: %{id: client.id, phone: client.phone, name: client.name}
end
