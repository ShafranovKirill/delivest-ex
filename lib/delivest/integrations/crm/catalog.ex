defmodule Delivest.Integrations.Crm.Catalog do
  import Ecto.Query, warn: false

  require Logger

  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.{CatalogCheck, CatalogHints, CatalogSnapshot}
  alias Delivest.{Net, Repo}

  def check_all do
    sources()
    |> Enum.group_by(&catalog_source/1)
    |> Enum.each(fn {_source, sources} -> check_group(sources) end)
  end

  def get_snapshot(branch_id), do: Repo.get_by(CatalogSnapshot, branch_id: branch_id)

  defp sources do
    from(i in BranchInfo,
      join: b in assoc(i, :branch),
      where: is_nil(b.deleted_at),
      where: fragment("(?->>'enabled')::boolean", i.crm),
      preload: [branch: b]
    )
    |> Repo.all()
    |> Enum.flat_map(&source/1)
  end

  defp source(%BranchInfo{crm: crm, branch: branch}) do
    with name when not is_nil(name) <- crm.provider,
         {:ok, _name, module} <- Crm.provider_module(name),
         true <- Code.ensure_loaded?(module) and function_exported?(module, :fetch_catalog, 1),
         %{} = settings <- Map.get(crm, name) do
      [%{branch: branch, provider: name, module: module, settings: settings}]
    else
      _ -> []
    end
  end

  defp catalog_source(%{module: module, settings: settings}), do: module.catalog_source(settings)

  defp check_group([%{module: module, settings: settings} | _] = sources) do
    case module.fetch_catalog(settings) do
      {:ok, catalog} ->
        Enum.each(sources, &check_branch(&1, catalog))

      {:error, reason} ->
        Logger.warning("#{module.name()} catalog was not received: #{inspect(reason)}")
    end
  end

  defp check_branch(%{branch: branch, provider: provider, module: module}, catalog) do
    issues = branch.id |> Net.list_branch_products() |> CatalogCheck.issues(catalog)
    previous = get_snapshot(branch.id)

    issues
    |> new_issues(previous)
    |> CatalogHints.report(branch.name, module.name())

    save(previous, branch.id, provider, catalog, issues)
  end

  defp new_issues(issues, nil), do: issues

  defp new_issues(issues, %CatalogSnapshot{issues: previous}) do
    known = MapSet.new(previous, &CatalogCheck.key/1)
    Enum.reject(issues, &MapSet.member?(known, CatalogCheck.key(&1)))
  end

  defp save(previous, branch_id, provider, catalog, issues) do
    Repo.insert_or_update!(
      Ecto.Changeset.change(previous || %CatalogSnapshot{branch_id: branch_id}, %{
        provider: to_string(provider),
        products: Enum.map(catalog, &Map.new(&1, fn {key, value} -> {to_string(key), value} end)),
        issues: issues,
        checked_at: DateTime.utc_now(:second)
      })
    )
  end
end
