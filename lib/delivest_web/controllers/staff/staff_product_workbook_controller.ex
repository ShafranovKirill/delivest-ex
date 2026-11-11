defmodule DelivestWeb.Staff.StaffProductWorkbookController do
  use DelivestWeb, :controller
  alias Delivest.{Identity, Net.ProductOperations}

  def show(%{assigns: %{current_staff: %{} = staff}} = conn, %{"branch_slug" => slug}) do
    with {:ok, branch} <- Identity.get_branch_by_slug(slug),
         {:ok, workbook} <- ProductOperations.export(staff, branch.id) do
      send_download(conn, {:binary, workbook},
        filename: "products-#{branch.slug}.xlsx",
        content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      )
    else
      _ -> send_resp(conn, :not_found, "")
    end
  end

  def show(conn, _), do: send_resp(conn, :unauthorized, "")
end
