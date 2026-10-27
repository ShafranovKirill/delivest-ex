defmodule Delivest.Integrations.Dadata.Api do
  alias Delivest.HTTP.Client
  alias Delivest.Integrations.Dadata.{Address, Settings}

  @base_url "https://suggestions.dadata.ru/suggestions/api/4_1/rs"
  @count 7

  @spec suggest(Settings.t(), String.t(), String.t() | nil) ::
          {:ok, [Address.t()]} | {:error, term()}
  def suggest(%Settings{} = settings, query, city) do
    settings
    |> post("/suggest/address", Map.merge(%{query: query, count: @count}, city_filter(city)))
    |> addresses()
  end

  @spec geolocate(Settings.t(), float(), float()) :: {:ok, [Address.t()]} | {:error, term()}
  def geolocate(%Settings{} = settings, latitude, longitude) do
    settings
    |> post("/geolocate/address", %{lat: latitude, lon: longitude, count: 1, radius_meters: 100})
    |> addresses()
  end

  defp post(settings, path, body) do
    Client.post(path, body,
      base_url: @base_url,
      headers: [{"authorization", "Token " <> settings.api_key}]
    )
  end

  defp city_filter(nil), do: %{}

  defp city_filter(city),
    do: %{locations: [%{city: city}], restrict_value: true, from_bound: %{value: "street"}}

  defp addresses({:ok, %{"suggestions" => suggestions}}) when is_list(suggestions),
    do: {:ok, Enum.map(suggestions, &Address.from_suggestion/1)}

  defp addresses({:ok, body}), do: {:error, {:dadata, body}}
  defp addresses(error), do: error
end
