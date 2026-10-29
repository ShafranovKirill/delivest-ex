defmodule Delivest.Integrations.Crm.Catalog do
  alias Delivest.Identity
  alias Delivest.Identity.Branch
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.{BranchSettings, CatalogCheck, CatalogSnapshot}
  alias Delivest.Integrations.Journal
  alias Delivest.{Net, Repo}
  alias Delivest.Net.ProductCrmIds

  @refresh_interval_s 3600

  def get_snapshot(branch_id, provider) do
    Repo.get_by(CatalogSnapshot, branch_id: branch_id, provider: to_string(provider))
  end

  def refresh_available_at(nil), do: nil

  def refresh_available_at(%CatalogSnapshot{checked_at: checked_at}),
    do: DateTime.add(checked_at, @refresh_interval_s)

  def refresh(branch_id, provider) do
    snapshot = Repo.get_by(CatalogSnapshot, branch_id: branch_id)

    with :ok <- ensure_refresh_available(snapshot, to_string(provider)),
         {:ok, module, settings} <- source(branch_id, provider),
         {:ok, catalog} <-
           Journal.scope([branch_id: branch_id], fn -> module.fetch_catalog(settings) end) do
      {:ok, save(snapshot, branch_id, provider, catalog)}
    end
  end

  def issues(_branch_id, nil), do: []

  def issues(branch_id, %CatalogSnapshot{provider: provider, products: crm_products}) do
    branch_id
    |> Net.list_branch_products()
    |> with_crm_ids(provider)
    |> CatalogCheck.issues(crm_products)
  end

  defp with_crm_ids(products, provider) do
    crm_ids = products |> Enum.map(& &1.id) |> ProductCrmIds.by_product(provider)

    Enum.map(
      products,
      &%{id: &1.id, name: &1.name, price: &1.price, external_id: crm_ids[&1.id]}
    )
  end

  defp ensure_refresh_available(%CatalogSnapshot{provider: provider} = snapshot, provider) do
    available_at = refresh_available_at(snapshot)

    if DateTime.compare(DateTime.utc_now(), available_at) == :lt,
      do: {:error, {:too_early, available_at}},
      else: :ok
  end

  defp ensure_refresh_available(_snapshot, _name), do: :ok

  defp source(branch_id, provider) do
    with {:ok, name, module} <- Crm.provider_module(provider),
         {:ok, %Branch{info: %{crm: %BranchSettings{} = crm}}} <-
           Identity.get_branch(branch_id, preload: [:info]),
         %{} = settings <- Map.get(crm, name) do
      {:ok, module, settings}
    else
      {:error, :unknown_provider} -> {:error, :unknown_provider}
      _ -> {:error, :missing_settings}
    end
  end

  defp save(snapshot, branch_id, provider, catalog) do
    Repo.insert_or_update!(
      Ecto.Changeset.change(snapshot || %CatalogSnapshot{branch_id: branch_id}, %{
        provider: to_string(provider),
        products: Enum.map(catalog, &Map.new(&1, fn {key, value} -> {to_string(key), value} end)),
        checked_at: DateTime.utc_now(:second)
      })
    )
  end
end
