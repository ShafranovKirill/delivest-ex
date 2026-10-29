defmodule DelivestWeb.Client.Order.OrderController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  alias Delivest.{Identity, Oms}
  alias Delivest.Oms.Carts
  alias DelivestWeb.Helpers.{ApiError, CookieHelper}
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse

  alias DelivestWeb.Schemas.OrderSchemas.{
    ActiveOrdersResponse,
    ClientOrdersResponse,
    CreateOrderRequest,
    OrderResponse
  }

  operation(:create,
    summary: "Создать заказ",
    description: "Создаёт заказ по cart_id и branch_id из тела запроса.",
    tags: ["Orders"],
    request_body: {"Создание заказа", "application/json", CreateOrderRequest},
    responses: [
      ok: {"Созданный заказ", "application/json", OrderResponse},
      unprocessable_entity: {"Ошибка создания заказа", "application/json", ErrorResponse},
      too_many_requests: {"Слишком много запросов", "application/json", ErrorResponse}
    ]
  )

  @public_fields ~w(cart_id branch_id customer_phone customer_name fulfillment_type
                    payment_method cook_by comment persons cash_given address expected_total)

  def create(conn, params) do
    session_id = CookieHelper.get_cookie(conn, "session_id")
    client = conn.assigns.current_client

    attrs =
      params
      |> Map.take(@public_fields)
      |> Map.put("session_id", session_id)
      |> put_client(client)

    with {:ok, _branch} <- fetch_public_branch(attrs["branch_id"]),
         true <-
           Carts.owned_by_session?(attrs["cart_id"], session_id) || {:error, :cart_not_found},
         {:ok, order} <- Oms.create_order(attrs, update_client: false) do
      remember_address(client, order)
      render(conn, :create, order: order)
    else
      {:error, reason} -> render_error(conn, reason)
      {:error, _step, reason} -> render_error(conn, reason)
    end
  end

  operation(:active,
    summary: "Активные заказы",
    description:
      "Заказы текущей сессии, которые ещё не завершены и созданы не раньше нескольких часов назад. " <>
        "Статус берётся из CRM, если заказ обрабатывается в ней.",
    tags: ["Orders"],
    responses: [ok: {"Активные заказы", "application/json", ActiveOrdersResponse}]
  )

  def active(conn, _params) do
    session_id = CookieHelper.get_cookie(conn, "session_id")
    orders = Oms.list_active_orders(session_id, client_id(conn.assigns.current_client))
    render(conn, :active, orders: orders)
  end

  operation(:index,
    summary: "Мои заказы",
    description: "Все заказы авторизованного клиента, новые сначала.",
    tags: ["Orders"],
    security: [%{"bearer" => []}],
    responses: [
      ok: {"Заказы клиента", "application/json", ClientOrdersResponse},
      unauthorized: {"Нужна авторизация", "application/json", ErrorResponse}
    ]
  )

  def index(conn, _params) do
    orders = Oms.list_client_orders(conn.assigns.current_client.id, :all)
    render(conn, :index, orders: orders)
  end

  defp put_client(attrs, nil), do: attrs

  defp put_client(attrs, client),
    do: Map.merge(attrs, %{"client_id" => client.id, "customer_phone" => client.phone})

  defp client_id(nil), do: nil
  defp client_id(client), do: client.id

  defp remember_address(nil, _order), do: :ok

  defp remember_address(client, %{
         fulfillment_type: :delivery,
         address: %{street: street} = address
       })
       when is_binary(street) do
    Identity.remember_client_address(client.id, Map.from_struct(address))
  end

  defp remember_address(_client, _order), do: :ok

  defp fetch_public_branch(nil), do: {:error, :branch_id_required}

  defp fetch_public_branch(branch_id) do
    case Identity.get_branch(branch_id) do
      {:ok, %{is_active: true} = branch} -> {:ok, branch}
      _ -> {:error, :branch_not_found}
    end
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset) do
    ApiError.send_error(
      conn,
      :unprocessable_entity,
      :validation_failed,
      "Validation failed",
      ApiError.changeset_errors(changeset)
    )
  end

  defp render_error(conn, {:below_minimum, min_order}) do
    ApiError.send_error(
      conn,
      :unprocessable_entity,
      :delivery_below_minimum,
      "Delivery needs an order from #{min_order}",
      %{min_order: min_order}
    )
  end

  defp render_error(conn, :outside_zones),
    do:
      ApiError.send_error(
        conn,
        :unprocessable_entity,
        :delivery_outside_zones,
        "No delivery to this address"
      )

  defp render_error(conn, :no_coordinates),
    do:
      ApiError.send_error(
        conn,
        :unprocessable_entity,
        :delivery_no_coordinates,
        "Pick the address on the map"
      )

  defp render_error(conn, reason)
       when reason in [
              :branch_id_required,
              :branch_not_found,
              :cart_not_found,
              :cart_is_empty,
              :cart_already_ordered,
              :cart_branch_mismatch,
              :product_unavailable,
              :client_blocked,
              :price_changed,
              :promo_unavailable
            ] do
    ApiError.send_error(conn, :unprocessable_entity, reason, Phoenix.Naming.humanize(reason))
  end

  defp render_error(conn, reason) do
    Logger.error("Order creation failed: #{inspect(reason)}")
    ApiError.send_error(conn, :unprocessable_entity, :order_failed, "Failed to create order")
  end
end
