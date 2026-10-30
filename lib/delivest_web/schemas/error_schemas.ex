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
            "document_not_found",
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
            "order_not_found",
            "order_not_cancellable",
            "too_many_requests",
            "unauthorized",
            "invalid_phone",
            "call_failed",
            "confirmation_not_found",
            "invalid_refresh_token",
            "address_not_found",
            "internal_error",
            "price_changed",
            "delivery_below_minimum",
            "delivery_outside_zones",
            "branch_paused",
            "delivery_no_coordinates",
            "promo_unavailable",
            "promo_not_found",
            "promo_inactive",
            "promo_not_started",
            "promo_expired",
            "promo_exhausted",
            "promo_requires_client",
            "promo_client_limit",
            "promo_not_owner",
            "promo_code_used",
            "promo_code_required"
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
