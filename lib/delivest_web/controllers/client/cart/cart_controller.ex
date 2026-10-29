defmodule DelivestWeb.Client.Cart.CartController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Oms
  alias Delivest.Oms.Carts
  alias DelivestWeb.Helpers.{ApiError, CookieHelper}

  alias DelivestWeb.Schemas.CartSchemas.{
    AddItemRequest,
    CartContextRequest,
    CartResponse,
    PromoCodeRequest
  }

  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias OpenApiSpex.Schema

  operation(:show,
    summary: "Получить корзину пользователя",
    description: "Извлекает branch_id из query или кук и возвращает состав текущей корзины.",
    tags: ["Cart"],
    parameters: [
      force: [
        in: :query,
        schema: %Schema{type: :boolean, default: false},
        required: false,
        description: "Принудительно пересчитать и обновить кэш корзины"
      ],
      branch_id: [
        in: :query,
        schema: %Schema{type: :string, format: :uuid},
        required: false,
        description: "ID активного филиала"
      ]
    ],
    responses: [
      ok: {"Данные корзины", "application/json", CartResponse},
      unprocessable_entity: {"Ошибка создания корзины", "application/json", ErrorResponse}
    ]
  )

  def show(conn, params) do
    cart_opts = build_cart_opts(conn, params)

    with {:ok, cart_view} <- Carts.get_or_create_cart(cart_opts),
         {:ok, cart_view} <- Oms.bind_cart_client(cart_view, current_client_id(conn)) do
      render(conn, :show, cart: cart_view)
    else
      {:error, _changeset} ->
        ApiError.send_error(conn, :unprocessable_entity, :bad_request, "Failed to create cart")
    end
  end

  operation(:apply_promo_code,
    summary: "Применить промокод",
    description:
      "Проверяет промокод и прикрепляет его к корзине. Если условия акции ещё не выполнены, " <>
        "код сохраняется со статусом `pending` и применится автоматически, когда условия выполнятся.",
    tags: ["Cart"],
    parameters: [
      cart_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body: {"Промокод", "application/json", PromoCodeRequest},
    responses: [
      ok: {"Обновлённая корзина", "application/json", CartResponse},
      unprocessable_entity:
        {"Промокод не может быть применён", "application/json", ErrorResponse},
      not_found: {"Корзина не найдена", "application/json", ErrorResponse},
      too_many_requests: {"Слишком много попыток", "application/json", ErrorResponse}
    ]
  )

  def apply_promo_code(conn, %{"cart_id" => cart_id} = params) do
    with :ok <- authorize_cart(conn, cart_id),
         {:ok, cart_view} <- Oms.apply_promo_code(cart_id, params["code"]) do
      render(conn, :show, cart: cart_view)
    else
      {:error, {:promo, reason}} -> promo_error(conn, reason)
      _ -> cart_not_found(conn)
    end
  end

  operation(:remove_promo_code,
    summary: "Убрать промокод",
    tags: ["Cart"],
    parameters: [
      cart_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Обновлённая корзина", "application/json", CartResponse},
      not_found: {"Корзина не найдена", "application/json", ErrorResponse}
    ]
  )

  def remove_promo_code(conn, %{"cart_id" => cart_id}) do
    with :ok <- authorize_cart(conn, cart_id),
         {:ok, cart_view} <- Oms.remove_promo_code(cart_id) do
      render(conn, :show, cart: cart_view)
    else
      _ -> cart_not_found(conn)
    end
  end

  operation(:update_context,
    summary: "Обновить способ получения",
    description: "Способ получения влияет на условия акций, поэтому корзина пересчитывается.",
    tags: ["Cart"],
    parameters: [
      cart_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body: {"Контекст корзины", "application/json", CartContextRequest},
    responses: [
      ok: {"Обновлённая корзина", "application/json", CartResponse},
      unprocessable_entity: {"Некорректный способ получения", "application/json", ErrorResponse},
      not_found: {"Корзина не найдена", "application/json", ErrorResponse}
    ]
  )

  def update_context(conn, %{"cart_id" => cart_id} = params) do
    with :ok <- authorize_cart(conn, cart_id),
         {:ok, cart_view} <- Oms.set_cart_fulfillment(cart_id, params["fulfillment_type"]) do
      render(conn, :show, cart: cart_view)
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.send_error(
          conn,
          :unprocessable_entity,
          :validation_failed,
          "Validation failed",
          ApiError.changeset_errors(changeset)
        )

      _ ->
        cart_not_found(conn)
    end
  end

  operation(:add_item,
    summary: "Добавить товар в корзину",
    description: "Добавляет товар в корзину по cart_id и product_id.",
    tags: ["Cart"],
    parameters: [
      cart_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "UUID корзины"
      ],
      product_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "UUID товара"
      ]
    ],
    request_body: {"Количество и модификаторы", "application/json", AddItemRequest},
    responses: [
      ok: {"Обновленная корзина", "application/json", CartResponse},
      unprocessable_entity: {"Ошибка добавления товара", "application/json", ErrorResponse},
      not_found: {"Корзина не найдена", "application/json", ErrorResponse}
    ]
  )

  operation(:clear,
    summary: "Очистить корзину",
    description: "Удаляет все товары из указанной корзины.",
    tags: ["Cart"],
    parameters: [
      cart_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "UUID корзины"
      ]
    ],
    responses: [
      ok: {"Очищенная корзина", "application/json", CartResponse},
      not_found: {"Корзина не найдена", "application/json", ErrorResponse}
    ]
  )

  operation(:repeat,
    summary: "Повторить заказ",
    description:
      "Добавляет в корзину позиции прошлого заказа клиента. Недоступные сейчас товары пропускаются.",
    tags: ["Cart"],
    parameters: [
      cart_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true],
      order_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Обновленная корзина", "application/json", CartResponse},
      not_found: {"Корзина или заказ не найдены", "application/json", ErrorResponse}
    ]
  )

  def repeat(conn, %{"cart_id" => cart_id, "order_id" => order_id}) do
    with :ok <- authorize_cart(conn, cart_id),
         {:ok, cart_view} <- Oms.repeat_order(cart_id, current_client_id(conn), order_id) do
      render(conn, :show, cart: cart_view)
    else
      {:error, :order_not_found} ->
        ApiError.send_error(conn, :not_found, :order_not_found, "Order not found")

      _ ->
        cart_not_found(conn)
    end
  end

  def clear(conn, %{"cart_id" => cart_id}) do
    with :ok <- authorize_cart(conn, cart_id),
         {:ok, cart_view} <- Carts.clear_cart(cart_id) do
      render(conn, :show, cart: cart_view)
    else
      _ -> cart_not_found(conn)
    end
  end

  def add_item(conn, %{"cart_id" => cart_id, "product_id" => product_id} = params) do
    quantity =
      if is_integer(params["quantity"]) and params["quantity"] > 0,
        do: params["quantity"],
        else: 1

    with :ok <- authorize_cart(conn, cart_id),
         {:ok, _item, cart_view} <-
           Carts.add_item(cart_id, product_id, quantity, params["modifiers"]) do
      render(conn, :show, cart: cart_view)
    else
      {:error, :cart_not_found} ->
        cart_not_found(conn)

      {:error, :product_unavailable} ->
        ApiError.send_error(
          conn,
          :unprocessable_entity,
          :product_unavailable,
          "Product is unavailable"
        )

      {:error, reason}
      when reason in [
             :modifier_unavailable,
             :modifiers_required,
             :modifiers_limit,
             :modifier_quantity
           ] ->
        ApiError.send_error(conn, :unprocessable_entity, reason, "Invalid modifiers")

      {:error, :quantity_limit_exceeded} ->
        ApiError.send_error(
          conn,
          :unprocessable_entity,
          :quantity_limit_exceeded,
          "Quantity limit exceeded"
        )

      {:error, _changeset} ->
        ApiError.send_error(conn, :unprocessable_entity, :bad_request, "Failed to add item")
    end
  end

  operation(:remove_item,
    summary: "Удалить товар из корзины",
    description: "Уменьшает количество товара на 1 или удаляет его полностью из корзины.",
    tags: ["Cart"],
    parameters: [
      cart_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "UUID корзины"
      ],
      product_id: [
        in: :path,
        schema: %Schema{type: :string},
        required: true,
        description: "UUID товара или `key` строки корзины"
      ],
      all: [
        in: :query,
        schema: %Schema{type: :boolean, default: false},
        required: false,
        description: "Удалить все единицы товара из корзины"
      ]
    ],
    responses: [
      ok: {"Обновленная корзина", "application/json", CartResponse},
      not_found: {"Корзина или товар не найдены", "application/json", ErrorResponse}
    ]
  )

  def remove_item(conn, %{"cart_id" => cart_id, "product_id" => product_id} = params) do
    opts =
      if Map.get(params, "all") in ["true", true] do
        [all: true]
      else
        []
      end

    with :ok <- authorize_cart(conn, cart_id),
         {product_part, _modifier_key} = Carts.parse_item_key(product_id),
         {:ok, _uuid} <- cast_uuid(product_part),
         {:ok, _status, cart_view} <- Carts.remove_item(cart_id, product_id, opts) do
      render(conn, :show, cart: cart_view)
    else
      {:error, :cart_not_found} ->
        cart_not_found(conn)

      _ ->
        ApiError.send_error(conn, :not_found, :item_not_found, "Item not found in cart")
    end
  end

  defp authorize_cart(conn, cart_id) do
    session_id = CookieHelper.get_cookie(conn, "session_id")

    if Carts.owned_by_session?(cart_id, session_id),
      do: :ok,
      else: {:error, :cart_not_found}
  end

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_uuid}
    end
  end

  defp cart_not_found(conn) do
    ApiError.send_error(conn, :not_found, :cart_not_found, "Cart not found")
  end

  defp promo_error(conn, reason) do
    code = "promo_#{reason}"
    ApiError.send_error(conn, :unprocessable_entity, code, Phoenix.Naming.humanize(code))
  end

  defp current_client_id(%{assigns: %{current_client: %{id: id}}}), do: id
  defp current_client_id(_conn), do: nil

  defp build_cart_opts(conn, params) do
    session_id = CookieHelper.get_cookie(conn, "session_id")
    branch_id = params["branch_id"] || CookieHelper.get_cookie(conn, "active_branch_id")
    force? = Map.get(params, "force") in ["true", true]

    [session_id: session_id, branch_id: branch_id, force: force?]
  end
end
