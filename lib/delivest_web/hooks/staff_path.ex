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

  defp determine_page_by_path(path) do
    cond do
      path && String.starts_with?(path, "/staff/dashboard") -> :dashboard
      path && String.starts_with?(path, "/staff/branches/select") -> :branches_select
      path && String.starts_with?(path, "/staff/branches") -> :branches
      path && String.starts_with?(path, "/staff/roles") -> :roles
      path && String.starts_with?(path, "/staff/employee") -> :employee
      true -> :unknown
    end
  end
end
