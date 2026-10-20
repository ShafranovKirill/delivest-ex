defmodule DelivestWeb.Staff.LogLive.HintText do
  use Gettext, backend: DelivestWeb.Gettext

  def title(%{"hint" => "missing_crm_id"}), do: gettext("No CRM ID")
  def title(%{"hint" => "missing_in_crm"}), do: gettext("Missing in CRM")
  def title(%{"hint" => "price_mismatch"}), do: gettext("Price differs")
  def title(_metadata), do: gettext("Hint")

  def describe(%{"hint" => "missing_crm_id"} = meta) do
    gettext("Product «%{product}» has no CRM ID: orders with it will not reach %{provider}.",
      product: meta["hint_product"],
      provider: meta["hint_provider"]
    )
  end

  def describe(%{"hint" => "missing_in_crm"} = meta) do
    gettext("Product «%{product}» with ID %{id} is not found in %{provider}.",
      product: meta["hint_product"],
      id: meta["hint_external_id"],
      provider: meta["hint_provider"]
    )
  end

  def describe(%{"hint" => "price_mismatch"} = meta) do
    gettext(
      "Product «%{product}» (ID %{id}) costs %{app} ₽ in the app and %{crm} ₽ in %{provider}.",
      product: meta["hint_product"],
      id: meta["hint_external_id"],
      app: meta["hint_app_price"],
      crm: meta["hint_crm_price"],
      provider: meta["hint_provider"]
    )
  end

  def describe(_metadata), do: nil

  def icon(%{"hint" => "price_mismatch"}), do: "hero-banknotes"
  def icon(_metadata), do: "hero-exclamation-triangle"
end
