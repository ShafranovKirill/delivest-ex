defmodule DelivestWeb.Schemas.AdvertisingSourceClaimResponse do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "AdvertisingSourceClaimResponse",
    type: :object,
    required: [:data],
    properties: %{
      data: %Schema{
        type: :object,
        required: [:claimed],
        properties: %{claimed: %Schema{type: :integer, minimum: 0}}
      }
    }
  })
end
