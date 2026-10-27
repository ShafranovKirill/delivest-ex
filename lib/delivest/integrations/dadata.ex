defmodule Delivest.Integrations.Dadata do
  alias Delivest.{Identity, Repo}
  alias Delivest.Integrations.Dadata.{Api, Settings}

  @cache :geo_cache
  @cache_ttl :timer.hours(24 * 7)

  def suggest(query, city) do
    query = normalize(query)
    cached({:suggest, city && normalize(city), query}, &Api.suggest(&1, query, city))
  end

  def geolocate(latitude, longitude) do
    latitude = Float.round(latitude, 4)
    longitude = Float.round(longitude, 4)
    cached({:geolocate, latitude, longitude}, &Api.geolocate(&1, latitude, longitude))
  end

  def get_settings, do: Repo.one(Settings) || %Settings{}

  def change_settings(%Settings{} = settings, attrs \\ %{}),
    do: Settings.changeset(settings, attrs)

  def update_settings(staff, attrs) do
    if Identity.can?(staff, "admin"),
      do: get_settings() |> Settings.changeset(attrs) |> Repo.insert_or_update(),
      else: {:error, :forbidden}
  end

  def active?, do: Settings.active?(get_settings())

  defp normalize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[\s,.]+/u, " ")
    |> String.trim()
  end

  defp cached(key, request) do
    case Cachex.get(@cache, key) do
      {:ok, addresses} when is_list(addresses) -> {:ok, addresses}
      _ -> fetch(key, request)
    end
  end

  defp fetch(key, request) do
    with {:ok, settings} <- fetch_settings(),
         {:ok, addresses} <- request.(settings) do
      Cachex.put(@cache, key, addresses, expire: @cache_ttl)
      {:ok, addresses}
    end
  end

  defp fetch_settings do
    settings = get_settings()

    if Settings.active?(settings),
      do: {:ok, settings},
      else: {:error, :dadata_not_configured}
  end
end
