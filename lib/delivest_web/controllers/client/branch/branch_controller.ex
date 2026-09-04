defmodule DelivestWeb.Client.Branch.BranchController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Identity
  alias DelivestWeb.Schemas.BranchSchemas.{BranchListResponse, BranchResponse}
  alias OpenApiSpex.Schema
  alias DelivestWeb.Helpers.CookieHelper

  @active_branch_cookie_opts [
    http_only: false,
    same_site: "Lax"
  ]

  operation(:index,
    summary: "Получить список филиалов",
    description: "Возвращает список всех активных филиалов.",
    tags: ["Branches"],
    responses: [
      ok: {"Список филиалов", "application/json", BranchListResponse},
      internal_server_error:
        {"Ошибка получения списка", "application/json",
         %Schema{
           type: :object,
           properties: %{
             error: %Schema{type: :string, example: "Failed to fetch branches"}
           }
         }}
    ]
  )

  def index(conn, _params) do
    try do
      branches = Identity.list_branches()
      render(conn, :index, branches: branches)
    rescue
      _ ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to fetch branches"})
    end
  end

  operation(:select,
    summary: "Выбрать филиал по ID",
    description: "Возвращает детальную информацию о филиале и устанавливает cookie.",
    tags: ["Branches"],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "UUID филиала",
        example: "c4a3b8e0-1234-5678-9abc-def012345678"
      ]
    ],
    responses: [
      ok: {"Детальная информация о филиале", "application/json", BranchResponse},
      not_found:
        {"Филиал не найден", "application/json",
         %Schema{
           type: :object,
           properties: %{
             error: %Schema{type: :string, example: "Branch not found"}
           },
           required: [:error]
         }}
    ]
  )

  def select(conn, %{"id" => id}) do
    case Identity.get_branch(id, preload: [:info]) do
      {:ok, branch} ->
        conn
        |> CookieHelper.put_cookie("active_branch_id", branch.id, @active_branch_cookie_opts)
        |> render(:show, branch: branch)

      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Branch not found"})
    end
  end

  operation(:clear_active,
    summary: "Очистить активный филиал",
    description: "Удаляет куку active_branch_id.",
    tags: ["Branches"],
    responses: [
      ok:
        {"Кука активного филиала удалена", "application/json",
         %Schema{
           type: :object,
           properties: %{
             message: %Schema{type: :string, example: "Active branch cleared"}
           }
         }}
    ]
  )

  operation(:select_by_slug,
    summary: "Выбрать филиал по Slug",
    description: "Возвращает детальную информацию о филиале по его slug и устанавливает cookie.",
    tags: ["Branches"],
    parameters: [
      slug: [
        in: :path,
        schema: %Schema{type: :string},
        required: true,
        description: "Slug филиала",
        example: "sochi-central"
      ]
    ],
    responses: [
      ok: {"Детальная информация о филиале", "application/json", BranchResponse},
      not_found: {"Филиал не найден", "application/json", %Schema{type: :object}}
    ]
  )

  def select_by_slug(conn, %{"slug" => slug}) do
    case Identity.get_branch_by_slug(slug, preload: [:info]) do
      {:ok, branch} ->
        conn
        |> CookieHelper.put_cookie("active_branch_id", branch.id, @active_branch_cookie_opts)
        |> render(:show, branch: branch)

      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Branch not found"})
    end
  end

  def clear_active(conn, _params) do
    conn
    |> CookieHelper.delete_cookie("active_branch_id", @active_branch_cookie_opts)
    |> json(%{message: "Active branch cleared"})
  end
end
