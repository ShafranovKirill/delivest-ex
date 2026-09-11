defmodule DelivestWeb.Client.Cart.CartController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Oms.Carts
  alias DelivestWeb.Helpers.CookieHelper
  alias DelivestWeb.Schemas.CartSchemas.CartResponse
  alias OpenApiSpex.Schema

  operation(:show,
    summary: "Получить корзину пользователя",
    description: "Извлекает session_id из кук и возвращает состав текущей корзины.",
    tags: ["Cart"],
    responses: [
      ok: {"Данные корзины", "application/json", CartResponse},
      unprocessable_entity:
        {"Ошибка создания корзины", "application/json", %Schema{type: :object}}
    ]
  )

  def show(conn, _params) do
    cart_opts = build_cart_opts(conn)

    case Carts.get_or_create_cart(cart_opts) do
      {:ok, cart_view} ->
        render(conn, :show, cart: cart_view)

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create cart"})
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
      ]
    ],
    request_body:
      {"Данные товара", "application/json",
       %Schema{
         type: :object,
         properties: %{
           product_id: %Schema{type: :string, format: :uuid}
         },
         required: [:product_id]
       }},
    responses: [
      ok: {"Обновленная корзина", "application/json", CartResponse},
      unprocessable_entity:
        {"Ошибка добавления товара", "application/json", %Schema{type: :object}}
    ]
  )

  def add_item(conn, %{"cart_id" => cart_id, "product_id" => product_id}) do
    case Carts.add_item(cart_id, product_id) do
      {:ok, _item, cart_view} ->
        render(conn, :show, cart: cart_view)

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to add item"})
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
      ]
    ],
    responses: [
      ok: {"Обновленная корзина", "application/json", CartResponse},
      not_found: {"Товар не найден в корзине", "application/json", %Schema{type: :object}}
    ]
  )

  def remove_item(conn, %{"cart_id" => cart_id, "product_id" => product_id}) do
    case Carts.remove_item(cart_id, product_id) do
      {:ok, _status, cart_view} ->
        render(conn, :show, cart: cart_view)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Item not found in cart"})
    end
  end

  defp build_cart_opts(conn) do
    session_id = CookieHelper.get_cookie(conn, "session_id")
    branch_id = CookieHelper.get_cookie(conn, "active_branch_id")

    [session_id: session_id, branch_id: branch_id]
  end
end
