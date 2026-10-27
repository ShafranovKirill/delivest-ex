defmodule Delivest.Integrations.Frontpad.AddressFields do
  import Delivest.Integrations.Frontpad.Fields

  def build(nil), do: %{street: nil, home: nil, pod: nil, et: nil, apart: nil}

  def build(address) do
    %{
      street: text(address.street, 50),
      home: text(address.house, 50),
      pod: digits(address.entrance, 2),
      et: digits(address.floor, 2),
      apart: text(address.apartment, 50)
    }
  end
end
