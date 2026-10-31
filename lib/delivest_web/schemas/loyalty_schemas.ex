defmodule DelivestWeb.Schemas.LoyaltySchemas do
  alias OpenApiSpex.Schema

  defmodule LoyaltyEntry do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LoyaltyEntry",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        kind: %Schema{
          type: :string,
          enum: ["accrual", "accrual_reversal", "expire", "adjust", "redeem", "refund"]
        },
        amount: %Schema{type: :integer, description: "Звёзды со знаком"},
        order_id: %Schema{type: :string, format: :uuid, nullable: true},
        expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :kind, :amount, :inserted_at]
    })
  end

  defmodule LoyaltyResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LoyaltyResponse",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            products: %Schema{
              type: :array,
              items: %Schema{
                type: :object,
                properties: %{
                  id: %Schema{type: :string, format: :uuid},
                  name: %Schema{type: :string},
                  stars_price: %Schema{type: :integer}
                }
              }
            },
            enabled: %Schema{type: :boolean},
            balance: %Schema{type: :integer},
            history: %Schema{type: :array, items: LoyaltyEntry}
          },
          required: [:enabled, :balance, :history]
        }
      },
      required: [:data]
    })
  end
end
