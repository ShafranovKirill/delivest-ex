defmodule DelivestWeb.Schemas.DeliverySchemas do
  alias OpenApiSpex.Schema

  defmodule DeliveryQuote do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DeliveryQuote",
      type: :object,
      properties: %{
        status: %Schema{
          type: :string,
          enum: ["ok", "below_minimum", "outside_zones", "no_coordinates"]
        },
        price: %Schema{type: :integer, nullable: true, example: 150},
        min_order: %Schema{type: :integer, nullable: true, example: 500},
        free_from: %Schema{type: :integer, nullable: true, example: 1500},
        minutes: %Schema{type: :integer, nullable: true, example: 45}
      },
      required: [:status, :price, :min_order, :free_from, :minutes]
    })
  end

  defmodule DeliveryQuoteResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DeliveryQuoteResponse",
      type: :object,
      properties: %{data: DeliveryQuote},
      required: [:data]
    })
  end
end
