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

  def get_uncached, do: load()

  def change(%Settings{} = settings, attrs \\ %{}), do: Settings.changeset(settings, attrs)

  def save(attrs) do
    case save_with_previous(attrs) do
      {:ok, {_previous, settings}} -> {:ok, settings}
      error -> error
    end
  end

  def save_with_previous(attrs) do
    result =
      Repo.transaction(fn ->
        if Map.has_key?(attrs, :maintenance_enabled) or Map.has_key?(attrs, "maintenance_enabled") do
          Delivest.Storefront.Maintenance.lock_franchise(Repo)
        end

        previous = load()

        case previous |> Settings.changeset(attrs) |> Repo.insert_or_update() do
          {:ok, settings} -> {previous, settings}
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    Cachex.del(@cache, @key)
    result
  end

  def save_images(attrs) do
    load()
    |> Settings.images_changeset(attrs)
    |> Repo.insert_or_update()
    |> tap(fn _result -> Cachex.del(@cache, @key) end)
  end

  def current(field), do: Map.fetch!(load(), field)

  defp load do
    Repo.one(Settings) || %Settings{fiscal_enabled: legacy_fiscal_active?()}
  end

  defp legacy_fiscal_active? do
    case Ecto.Adapters.SQL.query(
           Repo,
           "SELECT EXISTS (SELECT 1 FROM branch_info WHERE fiscal->>'mode' = 'own' AND COALESCE((fiscal->>'enabled')::boolean, TRUE))",
           []
         ) do
      {:ok, %{rows: [[active?]]}} -> active?
      _ -> false
    end
  end
end
