defmodule DelivestWeb.Client.Promotion.PromotionController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Promo
  alias DelivestWeb.Schemas.PromotionSchemas.RunningPromotionsResponse
  alias OpenApiSpex.Schema

  operation(:index,
    summary: "Действующие акции филиала",
    description: "Автоматические акции, которые сейчас применяются к корзине без промокода.",
    tags: ["Promotions"],
    parameters: [
      branch_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [ok: {"Список акций", "application/json", RunningPromotionsResponse}]
  )

  def index(conn, %{"branch_id" => branch_id}) do
    promotions =
      case Ecto.UUID.cast(branch_id) do
        {:ok, uuid} -> Promo.list_running_promotions(uuid)
        :error -> []
      end

    render(conn, :index, promotions: promotions)
  end
end
