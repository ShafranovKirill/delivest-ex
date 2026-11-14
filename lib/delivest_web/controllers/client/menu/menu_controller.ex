defmodule DelivestWeb.Client.Menu.MenuController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.{Net, Promo}
  alias DelivestWeb.Helpers.ApiError
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias DelivestWeb.Schemas.MenuSchemas.MenuResponse
  alias OpenApiSpex.Schema

  @popular_category_id "00000000-0000-4000-8000-000000000001"
  @popular_label gettext_noop("Popular")

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
      bad_request: {"Ошибка получения меню", "application/json", ErrorResponse}
    ]
  )

  defp menu_modifiers(menu) do
    categories =
      if is_map(menu) and Map.has_key?(menu, :categories), do: menu.categories, else: menu

    categories
    |> Enum.flat_map(&(&1.products || []))
    |> Enum.map(& &1.id)
    |> Net.Modifiers.for_products()
  end

  def index(conn, %{"branch_id" => branch_id}) do
    case Net.get_menu_for_branch(branch_id) do
      {:ok, menu} ->
        menu = Promo.overlay_menu(menu, branch_id)

        render(conn, :index,
          menu: localize_popular_category(menu, conn),
          rewards: Map.new(Net.list_branch_products(branch_id), &{&1.id, &1.stars_reward}),
          stopped: Net.Stops.stopped_ids(branch_id),
          modifiers: menu_modifiers(menu),
          stopped_modifiers: Net.Modifiers.stopped_ids(branch_id)
        )

      {:error, _reason} ->
        ApiError.send_error(conn, :bad_request, :bad_request, "Failed to fetch menu")
    end
  end

  defp localize_popular_category(menu, conn) do
    Enum.map(menu, fn
      %{id: @popular_category_id} = category -> %{category | name: popular_name(conn)}
      category -> category
    end)
  end

  defp popular_name(conn) do
    locale =
      conn
      |> get_req_header("accept-language")
      |> List.first()
      |> case do
        nil ->
          DelivestWeb.Plugs.Locale.default_locale()

        header ->
          case header
               |> String.split(",", parts: 2)
               |> hd()
               |> String.trim()
               |> String.downcase() do
            "ru" <> _ -> "ru"
            "en" <> _ -> "en"
            _ -> DelivestWeb.Plugs.Locale.default_locale()
          end
      end

    Gettext.with_locale(DelivestWeb.Gettext, locale, fn ->
      Gettext.gettext(DelivestWeb.Gettext, @popular_label)
    end)
  end
end
