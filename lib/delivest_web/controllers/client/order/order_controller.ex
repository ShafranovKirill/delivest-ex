defmodule DelivestWeb.Client.Order.OrderController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  alias Delivest.{Identity, Oms}
  alias Delivest.Oms.Carts
  alias DelivestWeb.Helpers.{ApiError, CookieHelper}
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias DelivestWeb.Schemas.OrderSchemas.{ActiveOrdersResponse, CreateOrderRequest, OrderResponse}

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
                    payment_method cook_by comment address)

  def create(conn, params) do
    session_id = CookieHelper.get_cookie(conn, "session_id")
    attrs = params |> Map.take(@public_fields) |> Map.put("session_id", session_id)

    with {:ok, _branch} <- fetch_public_branch(attrs["branch_id"]),
         true <-
           Carts.owned_by_session?(attrs["cart_id"], session_id) || {:error, :cart_not_found},
         {:ok, order} <- Oms.create_order(attrs, update_client: false) do
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
    orders = conn |> CookieHelper.get_cookie("session_id") |> Oms.list_active_orders()
    render(conn, :active, orders: orders)
  end

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

  defp render_error(conn, reason)
       when reason in [
              :branch_id_required,
              :branch_not_found,
              :cart_not_found,
              :cart_is_empty,
              :cart_already_ordered,
              :cart_branch_mismatch
            ] do
    ApiError.send_error(conn, :unprocessable_entity, reason, Phoenix.Naming.humanize(reason))
  end

  defp render_error(conn, reason) do
    Logger.error("Order creation failed: #{inspect(reason)}")
    ApiError.send_error(conn, :unprocessable_entity, :order_failed, "Failed to create order")
  end
end
