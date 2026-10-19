defmodule DelivestWeb.Client.Cart.CartController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Oms.Carts
  alias DelivestWeb.Helpers.{ApiError, CookieHelper}
  alias DelivestWeb.Schemas.CartSchemas.CartResponse
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

    case Carts.get_or_create_cart(cart_opts) do
      {:ok, cart_view} ->
        render(conn, :show, cart: cart_view)

      {:error, _changeset} ->
        ApiError.send_error(conn, :unprocessable_entity, :bad_request, "Failed to create cart")
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

  def clear(conn, %{"cart_id" => cart_id}) do
    with :ok <- authorize_cart(conn, cart_id),
         {:ok, cart_view} <- Carts.clear_cart(cart_id) do
      render(conn, :show, cart: cart_view)
    else
      _ -> cart_not_found(conn)
    end
  end

  def add_item(conn, %{"cart_id" => cart_id, "product_id" => product_id}) do
    with :ok <- authorize_cart(conn, cart_id),
         {:ok, _item, cart_view} <- Carts.add_item(cart_id, product_id) do
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
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "UUID товара"
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
         {:ok, product_uuid} <- cast_uuid(product_id),
         {:ok, _status, cart_view} <- Carts.remove_item(cart_id, product_uuid, opts) do
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

  defp build_cart_opts(conn, params) do
    session_id = CookieHelper.get_cookie(conn, "session_id")
    branch_id = params["branch_id"] || CookieHelper.get_cookie(conn, "active_branch_id")
    force? = Map.get(params, "force") in ["true", true]

    [session_id: session_id, branch_id: branch_id, force: force?]
  end
end
