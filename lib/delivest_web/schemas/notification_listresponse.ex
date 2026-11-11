defmodule DelivestWeb.Schemas.NotificationSchemas.ListResponse do
  alias OpenApiSpex.Schema
  alias DelivestWeb.Schemas.NotificationSchemas.Notice
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CustomerNoticeList",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: Notice},
      next_cursor: %Schema{type: :string, nullable: true}
    },
    required: [:data, :next_cursor]
  })
end
