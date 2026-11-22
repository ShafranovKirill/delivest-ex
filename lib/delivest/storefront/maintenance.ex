defmodule Delivest.Storefront.Maintenance do
  @moduledoc "Effective availability of the public storefront, independent of order intake."

  import Ecto.Query

  alias Delivest.Franchise.Settings
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Repo

  @franchise_lock "storefront-maintenance:franchise"

  def status_of(franchise_enabled, branch_enabled) do
    cond do
      franchise_enabled == true -> %{enabled: true, reason: :franchise}
      branch_enabled == true -> %{enabled: true, reason: :branch}
      true -> %{enabled: false, reason: nil}
    end
  end

  def status(branch_id) do
    franchise_enabled = Repo.one(from s in Settings, select: s.maintenance_enabled) || false

    branch_enabled =
      Repo.one(
        from i in BranchInfo,
          where: i.branch_id == ^branch_id,
          select: i.maintenance_enabled
      ) || false

    status_of(franchise_enabled, branch_enabled)
  end

  # Called inside a checkout transaction after an idempotency replay has been ruled out.
  # The shared locks serialize a new order with either settings change.
  def ensure_available(repo, branch_id) do
    advisory_lock(repo, @franchise_lock, :shared)
    advisory_lock(repo, branch_lock(branch_id), :shared)

    franchise_enabled = repo.one(from s in Settings, select: s.maintenance_enabled) || false

    branch_enabled =
      repo.one(
        from i in BranchInfo,
          where: i.branch_id == ^branch_id,
          select: i.maintenance_enabled
      ) || false

    if status_of(franchise_enabled, branch_enabled).enabled,
      do: {:error, :storefront_maintenance},
      else: {:ok, :available}
  end

  def lock_franchise(repo), do: advisory_lock(repo, @franchise_lock, :exclusive)
  def lock_branch(repo, branch_id), do: advisory_lock(repo, branch_lock(branch_id), :exclusive)

  defp branch_lock(branch_id), do: "storefront-maintenance:branch:#{branch_id}"

  defp advisory_lock(repo, key, :shared),
    do:
      Ecto.Adapters.SQL.query!(
        repo,
        "SELECT pg_advisory_xact_lock_shared(hashtextextended($1, 0))",
        [key]
      )

  defp advisory_lock(repo, key, :exclusive),
    do:
      Ecto.Adapters.SQL.query!(repo, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        key
      ])
end
