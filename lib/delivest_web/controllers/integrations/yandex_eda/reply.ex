defmodule DelivestWeb.Integrations.YandexEda.Reply do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  require Logger

  @codes %{
    bad_request: 100,
    invalid_client: 101,
    restaurant_not_found: 102,
    order_not_found: 103,
    invalid_item: 104,
    not_supported: 105,
    internal: 500
  }

  def errors(conn, status, reason, description) do
    conn
    |> put_status(status)
    |> json([%{code: Map.fetch!(@codes, reason), description: description}])
  end

  def failure(conn, :restaurant_not_found),
    do: errors(conn, :not_found, :restaurant_not_found, "Restaurant not found")

  def failure(conn, :order_not_found),
    do: errors(conn, :not_found, :order_not_found, "Order not found")

  def failure(conn, :invalid_status),
    do: errors(conn, :bad_request, :bad_request, "Unknown order status")

  def failure(conn, %Ecto.Changeset{} = changeset),
    do: errors(conn, :bad_request, :bad_request, describe(changeset))

  def failure(conn, description) when is_binary(description),
    do: errors(conn, :bad_request, :bad_request, description)

  def failure(conn, reason) do
    Logger.error("yandex eda request failed: #{inspect(reason)}")
    errors(conn, :internal_server_error, :internal, "Internal error")
  end

  defp describe(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> inspect()
  end

  def unavailable(conn, items) do
    names = Enum.map(items, & &1.name)

    conn
    |> put_status(:not_acceptable)
    |> json(%{
      type: "unavailable_goods",
      message: "На данный момент товар недоступен для заказа: " <> Enum.join(names, ", "),
      goods: Map.new(items, &{&1.product_id, &1.name})
    })
  end

  def unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{reason: "Access token is missing, invalid or expired. Request a new one"})
    |> halt()
  end

  def typed(conn, type, body) do
    conn
    |> put_resp_content_type("application/#{type}+json")
    |> send_resp(200, Jason.encode_to_iodata!(body))
  end
end
