defmodule DelivestWeb.Staff.BranchLive.Location do
  alias Delivest.Integrations.Dadata

  @spec suggest(String.t()) :: [Dadata.Address.t()]
  def suggest(query) do
    with query when byte_size(query) > 0 <- String.trim(query),
         {:ok, addresses} <- Dadata.suggest(query, nil) do
      addresses
    else
      _ -> []
    end
  end

  @spec at(float(), float()) :: map()
  def at(latitude, longitude) do
    case Dadata.geolocate(latitude, longitude) do
      {:ok, [address | _]} -> changes(address, latitude, longitude)
      _ -> %{latitude: latitude, longitude: longitude}
    end
  end

  @spec changes(Dadata.Address.t(), float() | nil, float() | nil) :: map()
  def changes(address, latitude \\ nil, longitude \\ nil) do
    %{
      address: address.value,
      city: address.city,
      latitude: latitude || address.latitude,
      longitude: longitude || address.longitude
    }
  end
end
