defmodule DelivestWeb.Hooks.StaffPath do
  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> attach_hook(:set_current_path, :handle_params, &set_current_path/3)}
  end

  defp set_current_path(_params, url, socket) do
    path = URI.parse(url).path

    socket =
      socket
      |> assign(:current_path, path)
      |> assign(:current_page, determine_page_by_path(path))

    {:cont, socket}
  end

  @pages [
    {"/staff/dashboard", :dashboard},
    {"/staff/statistics", :statistics},
    {"/staff/orders/new", :orders_new},
    {"/staff/orders", :orders},
    {"/staff/categories", :categories},
    {"/staff/products", :products},
    {"/staff/stocks", :stocks},
    {"/staff/promotions", :promotions},
    {"/staff/delivery", :delivery},
    {"/staff/branches/select", :branches_select},
    {"/staff/branches", :branches},
    {"/staff/clients", :clients},
    {"/staff/employee", :employee},
    {"/staff/roles", :roles},
    {"/staff/franchise", :franchise},
    {"/staff/integrations", :integrations},
    {"/staff/logs", :logs}
  ]

  defp determine_page_by_path(path) when is_binary(path) do
    Enum.find_value(@pages, :unknown, fn {prefix, page} ->
      if String.starts_with?(path, prefix), do: page
    end)
  end

  defp determine_page_by_path(_path), do: :unknown
end
