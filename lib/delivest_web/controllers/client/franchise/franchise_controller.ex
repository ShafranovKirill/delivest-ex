defmodule DelivestWeb.Client.Franchise.FranchiseController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.{Franchise, Identity}
  alias Delivest.Integrations.Dadata
  alias DelivestWeb.Helpers.ApiError
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias DelivestWeb.Schemas.FranchiseSchemas.{DocumentResponse, FranchiseResponse}
  alias OpenApiSpex.Schema

  operation(:show,
    summary: "Настройки франшизы",
    description:
      "Название, описание, основной цвет, логотипы, реквизиты продавца и список документов.",
    tags: ["Franchise"],
    responses: [ok: {"Настройки франшизы", "application/json", FranchiseResponse}]
  )

  def show(conn, _params) do
    render(conn, :show,
      settings: Franchise.get_settings(),
      documents: Franchise.list_documents(),
      address_map: Dadata.active?(),
      client_auth: Identity.client_auth_enabled?(),
      login_call_mode: Delivest.Integrations.Zvonok.login_call_mode(),
      rating: Delivest.Integrations.YandexRating.current()
    )
  end

  operation(:document,
    summary: "Юридический документ",
    description: "Текст документа с подставленными реквизитами.",
    tags: ["Franchise"],
    parameters: [
      kind: [
        in: :path,
        schema: %Schema{type: :string, enum: ["privacy", "consent", "offer", "terms"]},
        required: true
      ]
    ],
    responses: [
      ok: {"Документ", "application/json", DocumentResponse},
      not_found: {"Документ не найден", "application/json", ErrorResponse}
    ]
  )

  def document(conn, %{"kind" => kind}) do
    case Franchise.parse_document_kind(kind) do
      :error -> ApiError.send_error(conn, :not_found, :document_not_found, "Document not found")
      kind -> render(conn, :document, document: Franchise.get_document(kind))
    end
  end
end
