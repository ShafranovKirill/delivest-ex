defmodule Delivest.SiteSnapshot do
  @moduledoc """
  Transfers the public configuration of one branch or of the whole franchise
  between identical builds.

  This module keeps authorization, orchestration and audit. Archive parsing,
  snapshot reading, import planning, database writes and media transfer live in
  focused modules under `Delivest.SiteSnapshot`.
  """

  alias Delivest.{Audit, Identity, Repo}
  alias Delivest.Identity.Branch
  alias Delivest.SiteSnapshot.{Apply, Archive, Export, Fields, ImportPlan, MediaTransfer}

  @max_archive 100 * 1024 * 1024

  def build_id, do: Archive.build_id()
  def max_archive, do: @max_archive
  def sections, do: Fields.sections()

  def export(staff, branch_id, destination \\ :memory) do
    with :ok <- authorize(staff, branch_id, :read),
         {:ok, data} <- Export.branch_data(branch_id),
         {:ok, blobs} <- MediaTransfer.export_branch_blobs(data),
         {:ok, archive} <- Archive.encode(data, blobs, destination, :branch) do
      Audit.record(staff, "site_snapshot.exported", Repo.get!(Branch, branch_id))
      {:ok, archive}
    end
  end

  def import(staff, branch_id, archive) when is_binary(archive) do
    with :ok <- authorize(staff, branch_id, :write),
         {:ok, manifest, data, blobs} <- Archive.decode(archive, :branch),
         :ok <- authorize_global_catalog(staff, data) do
      result =
        Repo.transaction(
          fn ->
            lock!()

            try do
              plan = ImportPlan.build_branch(manifest, branch_id, data)
              upload_and_apply(plan, blobs)
            catch
              :throw, {:snapshot_abort, reason} -> Repo.rollback(reason)
            end
          end,
          timeout: :infinity
        )

      case result do
        {:ok, plan} ->
          Apply.post_commit(plan)

          counts =
            Map.merge(plan.counts, %{
              products: length(data["products"]),
              categories: length(data["categories"]),
              media: length(data["media"])
            })

          Audit.record(staff, "site_snapshot.imported", Repo.get!(Branch, branch_id),
            metadata: counts
          )

          {:ok, counts}

        {:error, reason} ->
          audit_import_failure(staff, branch_id, reason)
          {:error, reason}
      end
    else
      {:error, :forbidden} = error ->
        error

      {:error, reason} = error ->
        audit_import_failure(staff, branch_id, reason)
        error
    end
  end

  def import(_staff, _branch_id, _archive), do: {:error, :invalid_archive}

  def export_franchise(staff, sections, destination \\ :memory) do
    with {:ok, sections} <- normalize_sections(sections),
         :ok <- authorize_franchise(staff, :read),
         {:ok, data} <- Export.franchise_data(sections),
         {:ok, blobs} <- MediaTransfer.export_franchise_blobs(data),
         {:ok, archive} <- Archive.encode(data, blobs, destination, :franchise) do
      Audit.record(staff, "site_snapshot.exported", :franchise,
        metadata: %{scope: "franchise", sections: data["sections"]}
      )

      {:ok, archive}
    end
  end

  def import_franchise(staff, archive) when is_binary(archive) do
    with :ok <- authorize_franchise(staff, :write),
         {:ok, manifest, data, blobs} <- Archive.decode(archive, :franchise) do
      result =
        Repo.transaction(
          fn ->
            lock!()

            try do
              plan =
                ImportPlan.build_franchise(
                  manifest,
                  data,
                  Archive.sections_from_data(data, :franchise)
                )

              upload_and_apply(plan, blobs)
            catch
              :throw, {:snapshot_abort, reason} -> Repo.rollback(reason)
            end
          end,
          timeout: :infinity
        )

      case result do
        {:ok, plan} ->
          Apply.post_commit(plan)

          counts = Map.put(plan.counts, :scope, "franchise")

          Audit.record(staff, "site_snapshot.imported", :franchise, metadata: counts)

          {:ok, plan.counts}

        {:error, reason} ->
          audit_franchise_import_failure(staff, reason)
          {:error, reason}
      end
    else
      {:error, :forbidden} = error ->
        error

      {:error, reason} = error ->
        audit_franchise_import_failure(staff, reason)
        error
    end
  end

  def import_franchise(_staff, _archive), do: {:error, :invalid_archive}

  defp upload_and_apply(plan, blobs) do
    case MediaTransfer.upload_blobs(blobs) do
      {:ok, uploaded, keys} ->
        try do
          ImportPlan.preflight!(plan)
          Apply.apply(plan, uploaded)
          plan
        rescue
          error ->
            MediaTransfer.cleanup(keys)
            reraise error, __STACKTRACE__
        catch
          :throw, {:snapshot_abort, reason} ->
            MediaTransfer.cleanup(keys)
            Repo.rollback(reason)
        end

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp lock! do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["site_snapshot_global"])
  end

  defp audit_import_failure(staff, branch_id, reason) do
    case Repo.get(Branch, branch_id) do
      %Branch{} = branch ->
        Audit.record(staff, "site_snapshot.import_failed", branch,
          metadata: %{reason: audit_reason(reason)}
        )

      nil ->
        :ok
    end
  end

  defp audit_franchise_import_failure(staff, reason) do
    Audit.record(staff, "site_snapshot.import_failed", :franchise,
      metadata: %{reason: audit_reason(reason), scope: "franchise"}
    )
  end

  defp audit_reason(%Ecto.Changeset{errors: errors}),
    do: inspect({:invalid_fields, Keyword.keys(errors)})

  defp audit_reason(reason), do: inspect(reason)

  defp authorize(staff, branch_id, mode) do
    permissions =
      case mode do
        :read ->
          ~w(branches.read categories.read products.read delivery.read franchise.update)

        :write ->
          ~w(branches.read branches.update categories.read categories.create categories.update products.read products.create products.update delivery.read delivery.update franchise.update)
      end

    with %Branch{deleted_at: nil} <- Repo.get(Branch, branch_id),
         true <- Enum.all?(permissions, &(Identity.authorize(staff, &1, branch_id) == :ok)) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  defp authorize_global_catalog(staff, data) do
    if Enum.any?(~w(groups tags modifiers), &(Map.get(data, &1, []) != [])) and
         not Identity.can?(staff, "catalog.global.manage") do
      {:error, :forbidden}
    else
      :ok
    end
  end

  defp authorize_franchise(staff, _mode) do
    if Identity.can?(staff, "admin"), do: :ok, else: {:error, :forbidden}
  end

  defp normalize_sections(sections) when is_list(sections) do
    normalized =
      sections
      |> Enum.map(&section_name/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if normalized != [] and Enum.all?(sections, &(not is_nil(section_name(&1)))),
      do: {:ok, Enum.filter(Fields.sections(), &(&1 in normalized))},
      else: {:error, :invalid_sections}
  end

  defp normalize_sections(_), do: {:error, :invalid_sections}

  defp section_name(section) when is_atom(section),
    do: Enum.find(Fields.sections(), &(&1 == section))

  defp section_name(section) when is_binary(section),
    do: Enum.find(Fields.sections(), &(Atom.to_string(&1) == section))

  defp section_name(_), do: nil
end
