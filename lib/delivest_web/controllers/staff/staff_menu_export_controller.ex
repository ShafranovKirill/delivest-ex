defmodule DelivestWeb.Staff.StaffMenuExportController do
  use DelivestWeb, :controller

  alias Delivest.Identity
  alias Delivest.Net.MenuExport

  def show(%{assigns: %{current_staff: %{} = staff}} = conn, %{"branch_slug" => slug}) do
    with {:ok, branch} <- Identity.get_branch_by_slug(slug),
         {:ok, csv} <- MenuExport.csv(staff, branch.id) do
      send_download(conn, {:binary, csv},
        filename: MenuExport.filename(branch),
        content_type: "text/csv; charset=utf-8"
      )
    else
      _ -> send_resp(conn, :not_found, "")
    end
  end

  def show(conn, _params), do: send_resp(conn, :unauthorized, "")
end
