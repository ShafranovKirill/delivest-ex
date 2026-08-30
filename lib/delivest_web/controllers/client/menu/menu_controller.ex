defmodule DelivestWeb.Client.Menu.MenuController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Identity
  alias DelivestWeb.Schemas.MenuSchemas.MenuResponse
  alias OpenApiSpex.Schema

  operation(:index,
    summary: "Получить меню филиала",
    description:
      "Возвращает список категорий с предзагруженными товарами для филиала из кеша или БД.",
    tags: ["Menu"],
    parameters: [
      branch_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "UUID филиала",
        example: "c4a3b8e0-1234-5678-9abc-def012345678"
      ]
    ],
    responses: [
      ok: {"Меню филиала с категориями и товарами", "application/json", MenuResponse},
      bad_request:
        {"Ошибка получения меню", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{
             error: %OpenApiSpex.Schema{type: :string, example: "Failed to fetch menu"}
           }
         }}
    ]
  )

  def index(conn, %{"branch_id" => branch_id}) do
    case Identity.get_menu_for_branch(branch_id) do
      {:ok, menu} ->
        render(conn, :index, menu: menu)

      {:error, _reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to fetch menu"})
    end
  end
end
