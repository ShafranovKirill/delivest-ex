defmodule DelivestWeb.Schemas.GeoSchemas do
  alias OpenApiSpex.Schema

  defmodule GeoAddress do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "GeoAddress",
      type: :object,
      properties: %{
        value: %Schema{type: :string, example: "ул Республики, д 10"},
        city: %Schema{type: :string, nullable: true, example: "Тюмень"},
        street: %Schema{type: :string, nullable: true, example: "ул Республики"},
        house: %Schema{type: :string, nullable: true, example: "10"},
        latitude: %Schema{type: :number, format: :float, nullable: true},
        longitude: %Schema{type: :number, format: :float, nullable: true}
      },
      required: [:value, :city, :street, :house, :latitude, :longitude]
    })
  end

  defmodule GeoAddressListResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "GeoAddressListResponse",
      type: :object,
      properties: %{data: %Schema{type: :array, items: GeoAddress}},
      required: [:data]
    })
  end
end
