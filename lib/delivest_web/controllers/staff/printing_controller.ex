defmodule DelivestWeb.Staff.PrintingController do
  use DelivestWeb, :controller

  alias Delivest.{Identity, Printing}
  alias Delivest.Oms.{Order, OrderItem}

  def show(%{assigns: %{current_staff: staff}} = conn, params) when not is_nil(staff) do
    with {:ok, branch} <- Identity.get_branch_by_slug(params["branch_slug"]),
         {:ok, type} <- type(params["type"]),
         {:ok, pdf, _paper} <- document(staff, branch.id, params["order_id"], type) do
      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("content-disposition", disposition(params))
      |> send_resp(:ok, pdf)
    else
      {:error, :renderer_unavailable} -> send_resp(conn, :service_unavailable, "")
      _ -> send_resp(conn, :not_found, "")
    end
  end

  def show(conn, _), do: send_resp(conn, :unauthorized, "")

  defp type("kitchen"), do: {:ok, :kitchen}
  defp type("customer"), do: {:ok, :customer}
  defp type(_), do: {:error, :invalid_type}

  defp document(staff, branch_id, "demo", type) do
    if Printing.allowed?(staff, branch_id, type) and
         Identity.authorize(staff, "integrations.update", branch_id) == :ok do
      demo = %Order{
        number: "DEMO-123",
        branch_id: branch_id,
        comment: "Без лука. Пожалуйста, упакуйте отдельно.",
        total_amount: 74_500,
        items: [
          %OrderItem{
            title: "Пицца с очень длинным названием и дополнительным сыром",
            quantity: 2,
            price: 34_000,
            modifiers: []
          },
          %OrderItem{title: "Чай облепиховый", quantity: 1, price: 6500, modifiers: []}
        ]
      }

      Printing.render(demo, type, Printing.settings(branch_id))
    else
      {:error, :forbidden}
    end
  end

  defp document(staff, branch_id, order_id, type),
    do: Printing.render_order(staff, branch_id, order_id, type)

  defp disposition(%{"download" => "1", "type" => "kitchen"}),
    do: "attachment; filename=\"kitchen-ticket.pdf\""

  defp disposition(%{"download" => "1", "type" => "customer"}),
    do: "attachment; filename=\"customer-order.pdf\""

  defp disposition(_), do: "inline"
end
