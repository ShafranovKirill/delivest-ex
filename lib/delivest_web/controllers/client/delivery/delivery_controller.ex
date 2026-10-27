defmodule DelivestWeb.Client.Delivery.DeliveryController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.{Delivery, Identity}
  alias DelivestWeb.Helpers.ApiError
  alias DelivestWeb.Schemas.DeliverySchemas.{DeliveryQuoteResponse, DeliveryZonesResponse}
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias OpenApiSpex.Schema

  operation(:quote,
    summary: "Стоимость доставки",
    description:
      "Стоимость доставки по точке адреса и сумме корзины: " <>
        "`ok` — доставляем, `below_minimum` — сумма меньше минимальной, `outside_zones` — сюда не доставляем, " <>
        "`no_coordinates` — у адреса нет точки на карте.",
    tags: ["Delivery"],
    parameters: [
      branch_id: [in: :query, type: :string, required: true],
      latitude: [in: :query, schema: %Schema{type: :number}],
      longitude: [in: :query, schema: %Schema{type: :number}],
      subtotal: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Сумма корзины со скидками"
      ]
    ],
    responses: [
      ok: {"Стоимость", "application/json", DeliveryQuoteResponse},
      not_found: {"Нет филиала", "application/json", ErrorResponse}
    ]
  )

  def quote(conn, params) do
    case Identity.get_branch(params["branch_id"] || "") do
      {:ok, %{is_active: true} = branch} ->
        quote = Delivery.check(branch.id, point(params), integer(params["subtotal"]))
        render(conn, :quote, quote: quote)

      _ ->
        ApiError.send_error(conn, :not_found, :branch_not_found, "Branch not found")
    end
  end

  operation(:zones,
    summary: "Зоны доставки",
    description:
      "Зоны доставки филиала для показа на карте. Пустой список, если доставка без зон " <>
        "или в админке не стоит галочка показывать зоны клиенту.",
    tags: ["Delivery"],
    parameters: [branch_id: [in: :query, type: :string, required: true]],
    responses: [
      ok: {"Зоны", "application/json", DeliveryZonesResponse},
      not_found: {"Нет филиала", "application/json", ErrorResponse}
    ]
  )

  def zones(conn, params) do
    case Identity.get_branch(params["branch_id"] || "") do
      {:ok, %{is_active: true} = branch} ->
        render(conn, :zones, zones: Delivery.list_public_zones(branch.id))

      _ ->
        ApiError.send_error(conn, :not_found, :branch_not_found, "Branch not found")
    end
  end

  defp point(%{"latitude" => lat, "longitude" => lng}) do
    with {:ok, lat} <- coordinate(lat, 90),
         {:ok, lng} <- coordinate(lng, 180),
         do: {lat, lng},
         else: (_ -> nil)
  end

  defp point(_params), do: nil

  defp coordinate(value, limit) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} when abs(number) <= limit -> {:ok, number}
      _ -> :error
    end
  end

  defp coordinate(_value, _limit), do: :error

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> number
      _ -> 0
    end
  end

  defp integer(_value), do: 0
end
