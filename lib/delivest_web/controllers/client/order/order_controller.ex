defmodule DelivestWeb.Client.Order.OrderController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  alias Delivest.{Identity, Oms}
  alias Delivest.Oms.{Carts, Order}
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
                    payment_method cook_by comment persons cash_given address expected_total spend_points)

  def create(conn, params) do
    session_id = CookieHelper.get_cookie(conn, "session_id")
    client = conn.assigns.current_client

    attrs =
      params
      |> Map.take(@public_fields)
      |> Map.put("session_id", session_id)
      |> put_client(client)

    with {:ok, branch} <- fetch_public_branch(attrs["branch_id"]),
         :ok <- ensure_accepting(branch),
         :ok <- ensure_payment_method(branch, attrs["payment_method"]),
         true <-
           Carts.owned_by_session?(attrs["cart_id"], session_id) || {:error, :cart_not_found},
         {:ok, order} <-
           Oms.create_order(attrs,
             update_client: false,
             online: attrs["payment_method"] == "online"
           ),
         {:ok, confirmation_url} <- begin_payment(order) do
      remember_address(client, order)
      render(conn, :create, order: order, confirmation_url: confirmation_url)
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

  defp ensure_accepting(branch) do
    case Delivest.Intake.status(branch.id) do
      %{mode: :paused} = status -> {:error, {:branch_paused, status}}
      _status -> :ok
    end
  end

  defp begin_payment(%Order{awaiting_payment: true} = order) do
    case Delivest.Payments.Online.start(order) do
      {:ok, url} ->
        {:ok, url}

      {:error, reason} ->
        Logger.error(
          "online payment of order #{order.number} was not started: #{inspect(reason)}"
        )

        Delivest.Payments.Online.abandon(order)
        {:error, :payment_unavailable}
    end
  end

  defp begin_payment(_order), do: {:ok, nil}

  defp ensure_payment_method(_branch, nil), do: :ok

  defp ensure_payment_method(branch, method) do
    if method in Enum.map(Delivest.Payments.enabled_methods(branch), &to_string/1),
      do: :ok,
      else: {:error, :payment_method_disabled}
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

  defp render_error(conn, :payment_unavailable),
    do:
      ApiError.send_error(
        conn,
        :bad_gateway,
        :payment_unavailable,
        "The online payment is not available now, choose another way to pay"
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
              :promo_unavailable,
              :points_unavailable,
              :insufficient_points,
              :points_over_limit
            ] do
    ApiError.send_error(conn, :unprocessable_entity, reason, Phoenix.Naming.humanize(reason))
  end

  defp render_error(conn, reason) do
    Logger.error("Order creation failed: #{inspect(reason)}")
    ApiError.send_error(conn, :unprocessable_entity, :order_failed, "Failed to create order")
  end
end
