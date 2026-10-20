defmodule Delivest.Integrations.Crm.CatalogHints do
  require Logger

  def report(issues, branch_name, provider_name) do
    Enum.each(
      issues,
      &Logger.warning("#{provider_name} · #{branch_name}: #{message(&1, provider_name)}")
    )
  end

  defp message(%{"type" => "missing_crm_id", "name" => name}, provider),
    do: "product «#{name}» has no CRM ID, orders with it will not reach #{provider}"

  defp message(%{"type" => "missing_in_crm", "name" => name, "external_id" => id}, provider),
    do: "product «#{name}» with CRM ID #{id} is not found in #{provider}"

  defp message(%{"type" => "price_mismatch"} = issue, provider) do
    "product «#{issue["name"]}» with CRM ID #{issue["external_id"]} costs " <>
      "#{issue["app_price"]} ₽ in the app and #{issue["crm_price"]} ₽ in #{provider}"
  end
end
