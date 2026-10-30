defmodule Delivest.Integrations.Dadata do
  require Logger

  alias Delivest.{Identity, Repo}
  alias Delivest.Integrations.Dadata.{Api, Settings}

  @cache :geo_cache
  @cache_ttl :timer.hours(24 * 7)
  @pause :timer.minutes(5)

  def suggest(query, city) do
    query = normalize(query)
    cached({:suggest, city && normalize(city), query}, &Api.suggest(&1, query, city))
  end

  def geolocate(latitude, longitude) do
    latitude = Float.round(latitude, 4)
    longitude = Float.round(longitude, 4)
    cached({:geolocate, latitude, longitude}, &Api.geolocate(&1, latitude, longitude))
  end

  def health_check(%Settings{} = settings) do
    with {:ok, _addresses} <- Api.suggest(settings, "москва", nil), do: :ok
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
    @cache
    |> Cachex.fetch(key, fn -> load(request) end)
    |> case do
      {:ok, addresses} -> {:ok, addresses}
      {:commit, addresses} -> {:ok, addresses}
      {:ignore, result} -> result
      {:error, _reason} -> {:ok, []}
    end
  end

  defp load(request) do
    with {:ok, settings} <- fetch_settings(),
         :ok <- ensure_available(),
         {:ok, addresses} <- request.(settings) do
      {:commit, addresses, expire: @cache_ttl}
    else
      :unavailable -> {:ignore, {:ok, []}}
      {:error, reason} = error -> {:ignore, failed(error, reason)}
    end
  end

  defp failed(error, reason) do
    if unavailable?(reason) do
      Logger.warning("Dadata is unavailable, suggestions are paused: #{inspect(reason)}")
      Cachex.put(@cache, :unavailable, true, expire: @pause)
      {:ok, []}
    else
      error
    end
  end

  defp ensure_available do
    case Cachex.get(@cache, :unavailable) do
      {:ok, true} -> :unavailable
      _ -> :ok
    end
  end

  defp unavailable?({:http_error, status, _body}), do: status in [403, 429] or status >= 500
  defp unavailable?({:connection_error, _message, _reason}), do: true
  defp unavailable?(_reason), do: false

  defp fetch_settings do
    settings = get_settings()

    if Settings.active?(settings),
      do: {:ok, settings},
      else: {:error, :dadata_not_configured}
  end
end
