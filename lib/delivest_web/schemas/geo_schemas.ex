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
        longitude: %Schema{type: :number, format: :float, nullable: true},
        fias_id: %Schema{type: :string, nullable: true, description: "ФИАС дома"},
        postal_code: %Schema{type: :string, nullable: true, example: "625000"},
        district: %Schema{type: :string, nullable: true, example: "Центральный р-н"},
        geo_precision: %Schema{
          type: :integer,
          nullable: true,
          description: "Точность координат DaData qc_geo: 0 — точные, 5 — не определены"
        }
      },
      required: [
        :value,
        :city,
        :street,
        :house,
        :latitude,
        :longitude,
        :fias_id,
        :postal_code,
        :district,
        :geo_precision
      ]
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
