defmodule Delivest.Franchise.SettingsStore do
  alias Delivest.Repo
  alias Delivest.Franchise.Settings

  @cache :franchise_cache
  @key :settings

  def get do
    case Cachex.fetch(@cache, @key, fn _key -> {:commit, load()} end) do
      {:ok, settings} -> settings
      {:commit, settings} -> settings
      _error -> load()
    end
  end

  def change(%Settings{} = settings, attrs \\ %{}), do: Settings.changeset(settings, attrs)

  def save(attrs) do
    load()
    |> Settings.changeset(attrs)
    |> Repo.insert_or_update()
    |> tap(fn _result -> Cachex.del(@cache, @key) end)
  end

  def save_images(attrs) do
    load()
    |> Settings.images_changeset(attrs)
    |> Repo.insert_or_update()
    |> tap(fn _result -> Cachex.del(@cache, @key) end)
  end

  def current(field), do: Map.fetch!(load(), field)

  defp load, do: Repo.one(Settings) || %Settings{}
end
