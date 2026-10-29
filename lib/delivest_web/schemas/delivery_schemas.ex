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
        price: %Schema{type: :integer, nullable: true, example: 15_000},
        min_order: %Schema{type: :integer, nullable: true, example: 50_000},
        free_from: %Schema{type: :integer, nullable: true, example: 150_000},
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

  defmodule DeliveryZone do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DeliveryZone",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string, example: "Центр"},
        color: %Schema{type: :string, example: "#2563eb"},
        polygon: %Schema{
          type: :object,
          description: "GeoJSON Polygon, точки [долгота, широта]",
          properties: %{
            type: %Schema{type: :string, enum: ["Polygon"]},
            coordinates: %Schema{
              type: :array,
              items: %Schema{
                type: :array,
                items: %Schema{type: :array, items: %Schema{type: :number}}
              }
            }
          },
          required: [:type, :coordinates]
        }
      },
      required: [:id, :name, :color, :polygon]
    })
  end

  defmodule DeliveryZonesResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DeliveryZonesResponse",
      type: :object,
      properties: %{data: %Schema{type: :array, items: DeliveryZone}},
      required: [:data]
    })
  end
end
