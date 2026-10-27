defmodule DelivestWeb.Schemas.AddressSchemas do
  alias OpenApiSpex.Schema

  defmodule ClientAddress do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ClientAddress",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        city: %Schema{type: :string, nullable: true},
        street: %Schema{type: :string, example: "Ленина"},
        house: %Schema{type: :string, nullable: true, example: "10"},
        apartment: %Schema{type: :string, nullable: true},
        floor: %Schema{type: :string, nullable: true},
        entrance: %Schema{type: :string, nullable: true},
        intercom: %Schema{type: :string, nullable: true},
        comment: %Schema{type: :string, nullable: true, example: "Вход со двора"},
        latitude: %Schema{type: :number, format: :float, nullable: true, example: 57.153},
        longitude: %Schema{type: :number, format: :float, nullable: true, example: 65.534},
        label: %Schema{type: :string, nullable: true, maxLength: 30, example: "Дом"},
        formatted: %Schema{
          type: :string,
          nullable: true,
          example: "г Тюмень, ул Республики, д 10"
        },
        fias_id: %Schema{type: :string, nullable: true, description: "ФИАС дома"},
        postal_code: %Schema{type: :string, nullable: true, example: "625000"},
        district: %Schema{type: :string, nullable: true, example: "Центральный р-н"},
        geo_precision: %Schema{type: :integer, nullable: true, minimum: 0, maximum: 5}
      },
      required: [:id, :street]
    })
  end

  defmodule ClientAddressRequest do
    require OpenApiSpex
    alias DelivestWeb.Schemas.OrderSchemas.AddressRequest

    OpenApiSpex.schema(%{
      title: "ClientAddressRequest",
      allOf: [
        AddressRequest,
        %Schema{
          type: :object,
          properties: %{
            label: %Schema{type: :string, nullable: true, maxLength: 30, example: "Дом"}
          }
        }
      ]
    })
  end

  defmodule AddressResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ClientAddressResponse",
      type: :object,
      properties: %{data: ClientAddress},
      required: [:data]
    })
  end

  defmodule AddressListResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ClientAddressListResponse",
      type: :object,
      properties: %{data: %Schema{type: :array, items: ClientAddress}},
      required: [:data]
    })
  end
end
