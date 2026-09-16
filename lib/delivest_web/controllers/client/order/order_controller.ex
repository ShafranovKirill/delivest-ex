defmodule DelivestWeb.Client.Order.OrderController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Oms
  alias DelivestWeb.Schemas.OrderSchemas.{CreateOrderRequest, OrderResponse}
  alias OpenApiSpex.Schema

  operation(:create,
    summary: "Создать заказ",
    description: "Создаёт заказ по cart_id и branch_id из тела запроса.",
    tags: ["Orders"],
    request_body: {"Создание заказа", "application/json", CreateOrderRequest},
    responses: [
      ok: {"Созданный заказ", "application/json", OrderResponse},
      unprocessable_entity:
        {"Ошибка создания заказа", "application/json",
         %Schema{
           type: :object,
           properties: %{
             error: %Schema{type: :string, example: "Failed to create order"},
             details: %Schema{type: :object, additionalProperties: true, nullable: true}
           }
         }}
    ]
  )

  def create(conn, params) do
    case Oms.create_order(params) do
      {:ok, order} ->
        render(conn, :create, order: order)

      {:error, :branch_id_required} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Branch id is required"})

      {:error, :branch_not_found} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Branch not found"})

      {:error, :cart_not_found} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Cart not found"})

      {:error, :cart_is_empty} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Cart is empty"})

      {:error, _step, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Validation failed",
          details: Ecto.Changeset.traverse_errors(changeset, & &1)
        })

      {:error, _step, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create order", reason: inspect(reason)})
    end
  end
end
