defmodule DelivestWeb.Schemas.PromotionSchemas do
  alias OpenApiSpex.Schema

  defmodule RunningPromotion do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RunningPromotion",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string, example: "Скидка 10% на самовывоз"},
        description: %Schema{type: :string, nullable: true},
        ends_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :name, :description, :ends_at]
    })
  end

  defmodule RunningPromotionsResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RunningPromotionsResponse",
      type: :object,
      properties: %{data: %Schema{type: :array, items: RunningPromotion}},
      required: [:data]
    })
  end
end
