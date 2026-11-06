defmodule DelivestWeb.Client.Order.OrderController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  alias Delivest.Oms
  alias Delivest.Oms.{Checkout, Order, Orders}
  alias DelivestWeb.Helpers.{ApiError, CookieHelper}
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse

  alias DelivestWeb.Schemas.OrderSchemas.{
    ActiveOrdersResponse,
    ClientOrdersResponse,
    CreateOrderRequest,
    OrderResponse,
    PaymentLinkResponse
  }

  operation(:create,
    summary: "Создать заказ",
    description:
      "Создаёт заказ по cart_id и branch_id. Повтор с тем же Idempotency-Key возвращает созданный заказ.",
    tags: ["Orders"],
    parameters: [
      idempotency_key: [
        in: :header,
        name: "Idempotency-Key",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid},
        required: false,
        description: "UUID ключ одного оформления для владельца и филиала"
      ]
    ],
    request_body: {"Создание заказа", "application/json", CreateOrderRequest},
    responses: [
      ok: {"Созданный заказ", "application/json", OrderResponse},
      unauthorized: {"Требуется вход", "application/json", ErrorResponse},
      conflict: {"Ключ уже использован с другим запросом", "application/json", ErrorResponse},
      unprocessable_entity: {"Ошибка создания заказа", "application/json", ErrorResponse},
      bad_gateway: {"Сервис оплаты недоступен", "application/json", ErrorResponse},
      too_many_requests: {"Слишком много запросов", "application/json", ErrorResponse}
    ]
  )

  def create(conn, params) do
    session_id = CookieHelper.get_cookie(conn, "session_id")

    with {:ok, key} <- idempotency_key(conn),
         {:ok, order, confirmation_url} <-
           Checkout.create(params, conn.assigns.current_client, session_id, key) do
      render(conn, :create, order: order, confirmation_url: confirmation_url)
    else
      {:error, reason} -> render_error(conn, reason)
      {:error, _step, reason} -> render_error(conn, reason)
    end
  end

  defp idempotency_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [] ->
        {:ok, nil}

      [value] when byte_size(value) == 36 ->
        Ecto.UUID.cast(value)
        |> case do
          {:ok, key} -> {:ok, key}
          :error -> {:error, :invalid_idempotency_key}
        end

      [_value] ->
        {:error, :invalid_idempotency_key}

      _ ->
        {:error, :invalid_idempotency_key}
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

  operation(:show,
    summary: "Заказ текущей сессии",
    description: "Возвращает конкретный заказ владельцу сессии или вошедшему клиенту.",
    tags: ["Orders"],
    parameters: [id: [in: :path, type: :string, description: "ID заказа"]],
    responses: [
      ok: {"Заказ", "application/json", OrderResponse},
      not_found: {"Заказ не найден", "application/json", ErrorResponse}
    ]
  )

  def show(conn, %{"id" => id}) do
    session_id = CookieHelper.get_cookie(conn, "session_id")

    case Orders.get_order_for_owner(session_id, client_id(conn.assigns.current_client), id) do
      %Order{} = order -> render(conn, :create, order: order)
      nil -> ApiError.send_error(conn, :not_found, :order_not_found, "Order not found")
    end
  end

  operation(:cancel,
    summary: "Отменить заказ",
    description:
      "Только пока заказ в статусе created, без CRM и канала, оплата не онлайн. " <>
        "Дальше отмена — звонком в филиал.",
    tags: ["Orders"],
    parameters: [id: [in: :path, type: :string, description: "ID заказа"]],
    responses: [
      ok: {"Отменённый заказ", "application/json", OrderResponse},
      not_found: {"Заказ не найден", "application/json", ErrorResponse},
      unprocessable_entity: {"Заказ уже нельзя отменить", "application/json", ErrorResponse}
    ]
  )

  def cancel(conn, %{"id" => id}) do
    session_id = CookieHelper.get_cookie(conn, "session_id")

    case Oms.cancel_by_client(session_id, client_id(conn.assigns.current_client), id) do
      {:ok, order} ->
        render(conn, :create, order: order)

      {:error, :not_found} ->
        ApiError.send_error(conn, :not_found, :order_not_found, "Order not found")

      {:error, _reason} ->
        ApiError.send_error(
          conn,
          :unprocessable_entity,
          :order_not_cancellable,
          "The order can no longer be cancelled"
        )
    end
  end

  operation(:pay,
    summary: "Ссылка на оплату",
    description:
      "Для заказа, который ждёт онлайн-оплаты: возвращает страницу оплаты ЮKassa, " <>
        "чтобы клиент мог вернуться и оплатить.",
    tags: ["Orders"],
    parameters: [id: [in: :path, type: :string, description: "ID заказа"]],
    responses: [
      ok: {"Страница оплаты", "application/json", PaymentLinkResponse},
      not_found: {"Заказ не найден", "application/json", ErrorResponse},
      unprocessable_entity: {"Заказ не ждёт оплаты", "application/json", ErrorResponse}
    ]
  )

  def pay(conn, %{"id" => id}) do
    session_id = CookieHelper.get_cookie(conn, "session_id")

    case Oms.payment_link(session_id, client_id(conn.assigns.current_client), id) do
      {:ok, url} ->
        json(conn, %{data: %{confirmation_url: url}})

      {:error, :not_found} ->
        ApiError.send_error(conn, :not_found, :order_not_found, "Order not found")

      {:error, :not_awaiting} ->
        ApiError.send_error(
          conn,
          :unprocessable_entity,
          :order_not_awaiting_payment,
          "The order is not waiting for the payment"
        )

      {:error, _reason} ->
        render_error(conn, :payment_unavailable)
    end
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

  defp client_id(nil), do: nil
  defp client_id(client), do: client.id

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

  defp render_error(conn, {:branch_paused, status}) do
    ApiError.send_error(
      conn,
      :unprocessable_entity,
      :branch_paused,
      "The branch is not taking orders now",
      %{until: status.until, reason: status.reason}
    )
  end

  defp render_error(conn, :branch_closed),
    do:
      ApiError.send_error(
        conn,
        :unprocessable_entity,
        :branch_closed,
        "The branch is closed at the requested time"
      )

  defp render_error(conn, :cook_by_in_past),
    do:
      ApiError.send_error(
        conn,
        :unprocessable_entity,
        :cook_by_in_past,
        "Choose a time in the future"
      )

  defp render_error(conn, :cook_by_outside_hours),
    do:
      ApiError.send_error(
        conn,
        :unprocessable_entity,
        :cook_by_outside_hours,
        "The branch is closed at the requested time"
      )

  defp render_error(conn, :payment_unavailable),
    do:
      ApiError.send_error(
        conn,
        :bad_gateway,
        :payment_unavailable,
        "The online payment is not available now; retry this order"
      )

  defp render_error(conn, :idempotency_conflict),
    do:
      ApiError.send_error(
        conn,
        :conflict,
        :idempotency_conflict,
        "Idempotency key already used with another request"
      )

  defp render_error(conn, :cart_changed),
    do:
      ApiError.send_error(
        conn,
        :conflict,
        :cart_changed,
        "The cart changed; refresh it before ordering"
      )

  defp render_error(conn, :payment_method_disabled),
    do:
      ApiError.send_error(
        conn,
        :unprocessable_entity,
        :payment_method_disabled,
        "This payment method is not available at the branch"
      )

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

  defp render_error(conn, :client_auth_required),
    do:
      ApiError.send_error(
        conn,
        :unauthorized,
        :client_auth_required,
        "Sign in to place the order"
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
              :promo_gift_not_available,
              :fulfillment_unavailable,
              :promo_unavailable,
              :points_unavailable,
              :insufficient_points,
              :points_over_limit,
              :invalid_idempotency_key
            ] do
    ApiError.send_error(conn, :unprocessable_entity, reason, Phoenix.Naming.humanize(reason))
  end

  defp render_error(conn, reason) do
    Logger.error("Order creation failed: #{inspect(reason)}")
    ApiError.send_error(conn, :unprocessable_entity, :order_failed, "Failed to create order")
  end
end
