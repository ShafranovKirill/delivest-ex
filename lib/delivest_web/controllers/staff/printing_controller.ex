defmodule DelivestWeb.Staff.PrintingController do
  use DelivestWeb, :controller

  alias Delivest.{Identity, Printing}

  @print_controls """
  <style>
    #document-print { display: block; margin: 0 0 16px auto; padding: 8px 14px; font: inherit; cursor: pointer }
    @media print { #document-print { display: none } }
  </style>
  <button id="document-print" type="button">Печать</button>
  <script>
    document.getElementById('document-print').addEventListener('click', () => window.print());
    window.addEventListener('load', () => window.print(), { once: true });
  </script>
  """

  def settings_redirect(conn, _params), do: redirect(conn, to: ~p"/staff/franchise/printing")

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

  def print(%{assigns: %{current_staff: staff}} = conn, params) when not is_nil(staff) do
    with {:ok, branch} <- Identity.get_branch_by_slug(params["branch_slug"]),
         {:ok, type} <- type(params["type"]),
         {:ok, document} <- Printing.render_order_html(staff, branch.id, params["order_id"], type) do
      conn
      |> put_resp_content_type("text/html")
      |> put_resp_header("cache-control", "private, no-store")
      |> send_resp(:ok, browser_print_document(document))
    else
      {:error, :renderer_unavailable} -> send_resp(conn, :service_unavailable, "")
      _ -> send_resp(conn, :not_found, "")
    end
  end

  def print(conn, _), do: send_resp(conn, :unauthorized, "")

  defp browser_print_document(document) do
    document =
      if Regex.match?(~r/<body data-paper="roll(?:58|80)">/, document) do
        String.replace(document, "</head>", "<style>@page{size:auto}</style></head>",
          global: false
        )
      else
        document
      end

    Regex.replace(~r/<body\b[^>]*>/, document, &(&1 <> @print_controls), global: false)
  end

  defp type("kitchen"), do: {:ok, :kitchen}
  defp type("customer"), do: {:ok, :customer}
  defp type(_), do: {:error, :invalid_type}

  defp document(staff, branch_id, "demo", type) do
    if Printing.allowed?(staff, branch_id, type) and
         Identity.authorize(staff, "integrations.update", branch_id) == :ok do
      Printing.render_sample(type, Printing.settings(branch_id), branch_id)
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
