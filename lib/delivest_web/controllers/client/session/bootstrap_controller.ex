defmodule DelivestWeb.Client.Session.BootstrapController do
  use DelivestWeb, :controller

  alias Delivest.{Identity, Oms}
  alias Delivest.Oms.Carts
  alias DelivestWeb.Client.Cart.CartJSON
  alias DelivestWeb.Client.Order.OrderJSON
  alias DelivestWeb.ClientToken
  alias DelivestWeb.Helpers.CookieHelper

  def show(conn, %{"branch_id" => branch_id}) do
    conn = put_resp_header(conn, "cache-control", "private, no-store")

    with {:ok, uuid} <- Ecto.UUID.cast(branch_id),
         {:ok, %{is_active: true}} <- Identity.get_branch(uuid) do
      client_id = conn.assigns.current_client && conn.assigns.current_client.id
      session_id = session_id(conn)
      cart = Carts.get_cart(session_id: session_id, branch_id: uuid)

      cart_result =
        case cart do
          nil -> {:ok, nil}
          existing -> Oms.bind_cart_client(existing, client_id)
        end

      case cart_result do
        {:ok, bound_cart} ->
          orders = Oms.list_active_orders(session_id, client_id)

          json(conn, %{
            cart: CartJSON.show(%{cart: bound_cart}).data,
            active_orders: OrderJSON.active(%{orders: orders}).data,
            socket_token: ClientToken.issue_socket(session_id, client_id)
          })

        _ ->
          conn |> put_status(:forbidden) |> json(%{error: "cart_owner_mismatch"})
      end
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "branch_not_found"})
    end
  end

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> put_status(:bad_request)
    |> json(%{error: "branch_id_required"})
  end

  defp session_id(conn) do
    case conn.resp_cookies do
      %{"session_id" => %{value: value}} -> value
      _ -> CookieHelper.get_cookie(conn, "session_id")
    end
  end
end
