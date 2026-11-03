defmodule Delivest.Health do
  @moduledoc """
  Liveness and readiness facts for the running node.

  Liveness only says the application answers. Readiness additionally checks the
  database and that every migration shipped with this build has been applied, so
  a node that failed to initialise is not reported as a successful deployment.
  """

  alias Delivest.Repo

  @app "delivest"

  def version, do: Application.get_env(:delivest, :version, "dev")

  def live do
    %{status: "ok", app: @app, version: version()}
  end

  def ready do
    with :ok <- database(),
         :ok <- migrations() do
      %{
        status: "ok",
        app: @app,
        version: version(),
        checks: %{database: "ok", migrations: "ok"}
      }
    else
      {:error, check} ->
        {:error,
         %{
           status: "unavailable",
           app: @app,
           version: version(),
           checks: %{check => "error"}
         }}
    end
  end

  @doc """
  Migration versions present in the build but missing from the database.
  """
  def pending_migrations(expected, applied) do
    applied = MapSet.new(applied)
    Enum.reject(expected, &MapSet.member?(applied, &1))
  end

  defp database do
    case Repo.query("SELECT 1") do
      {:ok, _result} -> :ok
      {:error, _reason} -> {:error, :database}
    end
  end

  defp migrations do
    if pending_migrations(expected_migrations(), Ecto.Migrator.migrated_versions(Repo)) == [],
      do: :ok,
      else: {:error, :migrations}
  rescue
    _error -> {:error, :migrations}
  end

  defp expected_migrations do
    :delivest
    |> Application.app_dir("priv/repo/migrations")
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.flat_map(&version/1)
    |> Enum.sort()
  end

  defp version(path) do
    case path |> Path.basename() |> String.split("_", parts: 2) |> hd() |> Integer.parse() do
      {number, _rest} -> [number]
      :error -> []
    end
  end
end
