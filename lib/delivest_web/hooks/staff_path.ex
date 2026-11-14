defmodule DelivestWeb.Hooks.StaffPath do
  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> attach_hook(:set_current_path, :handle_params, &set_current_path/3)}
  end

  defp set_current_path(params, url, socket) do
    path = URI.parse(url).path
    stripped = DelivestWeb.StaffBranchPath.strip(path)

    page =
      cond do
        stripped == "/staff/marketing" -> marketing_section_page(params["section"])
        String.match?(stripped, ~r{^/staff/branches/[^/]+/edit(?:/|$)}) -> :settings
        true -> determine_page_by_path(stripped)
      end

    socket =
      socket
      |> assign(:current_path, path)
      |> assign(
        :current_uri,
        URI.parse(url)
        |> then(fn uri -> uri.path <> if(uri.query, do: "?" <> uri.query, else: "") end)
      )
      |> assign(
        :current_page,
        page
      )

    {:cont, socket}
  end

  @pages [
    {"/staff/dashboard", :dashboard},
    {"/staff/statistics", :statistics},
    {"/staff/orders/new", :orders_new},
    {"/staff/orders", :orders},
    {"/staff/deliveries", :deliveries},
    {"/staff/couriers", :couriers},
    {"/staff/finance/payments", :payments},
    {"/staff/finance/transactions", :payments},
    {"/staff/finance/receipts", :receipts},
    {"/staff/categories", :categories},
    {"/staff/menu/popular", :popular},
    {"/staff/products/stops", :stops},
    {"/staff/products/tags", :tags},
    {"/staff/products/suggested", :suggested},
    {"/staff/products", :products},
    {"/staff/stocks", :stocks},
    {"/staff/promotions", :promotions},
    {"/staff/loyalty", :loyalty},
    {"/staff/settings", :settings},
    {"/staff/delivery", :settings},
    {"/staff/branches/select", :branches_select},
    {"/staff/branches", :settings},
    {"/staff/clients", :clients},
    {"/staff/segments", :segments},
    {"/staff/marketing/bonuses", :loyalty},
    {"/staff/marketing", :marketing_policies},
    {"/staff/advertising-links", :advertising_links},
    {"/staff/employee", :employee},
    {"/staff/roles", :roles},
    {"/staff/franchise", :settings},
    {"/staff/integrations", :settings},
    {"/staff/diagnostics", :metrics},
    {"/staff/metrics", :metrics},
    {"/staff/logs", :logs}
  ]

  defp determine_page_by_path(path) when is_binary(path) do
    Enum.find_value(@pages, :unknown, fn {prefix, page} ->
      if String.starts_with?(path, prefix), do: page
    end)
  end

  defp marketing_section_page("stocks"), do: :stocks
  defp marketing_section_page("promotions"), do: :promotions
  defp marketing_section_page("loyalty"), do: :loyalty
  defp marketing_section_page("links"), do: :advertising_links
  defp marketing_section_page(_), do: :marketing
end
