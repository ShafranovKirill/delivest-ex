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
        intercom: %Schema{type: :string, nullable: true}
      },
      required: [:id, :street]
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
