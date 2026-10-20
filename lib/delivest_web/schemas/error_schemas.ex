defmodule DelivestWeb.Schemas.ErrorSchemas do
  alias OpenApiSpex.Schema

  defmodule ErrorResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      description:
        "Ошибка API. `error` — стабильный машиночитаемый код, по нему клиент выбирает текст для пользователя.",
      type: :object,
      properties: %{
        error: %Schema{
          type: :string,
          example: "validation_failed",
          enum: [
            "bad_request",
            "branch_id_required",
            "branch_not_found",
            "cart_not_found",
            "cart_is_empty",
            "cart_already_ordered",
            "cart_branch_mismatch",
            "product_unavailable",
            "client_blocked",
            "quantity_limit_exceeded",
            "item_not_found",
            "validation_failed",
            "order_failed",
            "too_many_requests",
            "internal_error"
          ]
        },
        message: %Schema{type: :string, example: "Validation failed"},
        details: %Schema{
          type: :object,
          nullable: true,
          description: "Ошибки валидации по полям: {поле: [сообщения]}",
          additionalProperties: true,
          example: %{customer_phone: ["must be in format +7XXXXXXXXXX"]}
        }
      },
      required: [:error, :message]
    })
  end
end
