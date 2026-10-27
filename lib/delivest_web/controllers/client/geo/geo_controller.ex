defmodule DelivestWeb.Client.Geo.GeoController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Integrations.Dadata
  alias DelivestWeb.Helpers.ApiError
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias DelivestWeb.Schemas.GeoSchemas.GeoAddressListResponse
  alias OpenApiSpex.Schema

  @min_query_length 3

  operation(:suggest,
    summary: "Подсказки адресов",
    description: "Адреса DaData по введённой строке, в пределах города, если он передан.",
    tags: ["Geo"],
    parameters: [
      query: [in: :query, type: :string, required: true, description: "Введённый адрес"],
      city: [in: :query, type: :string, description: "Город филиала"]
    ],
    responses: [
      ok: {"Адреса", "application/json", GeoAddressListResponse},
      service_unavailable: {"Подсказки выключены", "application/json", ErrorResponse}
    ]
  )

  def suggest(conn, %{"query" => query} = params) do
    query = String.trim(query)

    if String.length(query) < @min_query_length,
      do: render(conn, :index, addresses: []),
      else: query |> Dadata.suggest(blank_to_nil(params["city"])) |> respond(conn)
  end

  def suggest(conn, _params), do: render(conn, :index, addresses: [])

  operation(:reverse,
    summary: "Адрес по координатам",
    description: "Ближайший дом к точке на карте.",
    tags: ["Geo"],
    parameters: [
      latitude: [in: :query, schema: %Schema{type: :number}, required: true],
      longitude: [in: :query, schema: %Schema{type: :number}, required: true]
    ],
    responses: [
      ok: {"Адреса", "application/json", GeoAddressListResponse},
      unprocessable_entity: {"Неверные координаты", "application/json", ErrorResponse},
      service_unavailable: {"Подсказки выключены", "application/json", ErrorResponse}
    ]
  )

  def reverse(conn, params) do
    with {:ok, latitude} <- coordinate(params["latitude"], 90),
         {:ok, longitude} <- coordinate(params["longitude"], 180) do
      latitude |> Dadata.geolocate(longitude) |> respond(conn)
    else
      :error ->
        ApiError.send_error(
          conn,
          :unprocessable_entity,
          :invalid_coordinates,
          "Invalid coordinates"
        )
    end
  end

  defp coordinate(value, limit) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} when abs(number) <= limit -> {:ok, number}
      _ -> :error
    end
  end

  defp coordinate(_value, _limit), do: :error

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: String.trim(value)

  defp respond({:ok, addresses}, conn), do: render(conn, :index, addresses: addresses)

  defp respond({:error, :dadata_not_configured}, conn),
    do:
      ApiError.send_error(
        conn,
        :service_unavailable,
        :address_suggestions_disabled,
        "Address suggestions are disabled"
      )

  defp respond({:error, _reason}, conn),
    do:
      ApiError.send_error(
        conn,
        :bad_gateway,
        :address_suggestions_failed,
        "Address suggestions failed"
      )
end
