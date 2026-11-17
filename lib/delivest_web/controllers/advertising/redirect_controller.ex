defmodule DelivestWeb.Advertising.RedirectController do
  use DelivestWeb, :controller

  alias Delivest.Advertising.{Clicks, Links}
  alias DelivestWeb.{AdvertisingDestination, AnalyticsIdentity}

  @numeric_parameters ~w(yclid campaign_id ad_id)
  @utm_parameters ~w(utm_source utm_medium utm_campaign)
  @parameters @numeric_parameters ++ @utm_parameters ++ ["product"]

  def show(conn, %{"token" => token}) do
    conn = fetch_query_params(conn)

    with {link, slug} <- Links.resolve(token),
         {:ok, destination} <- AdvertisingDestination.for_branch(slug) do
      existing_guest =
        case AnalyticsIdentity.guest_id(conn) do
          {:ok, id} -> id
          :error -> nil
        end

      guest_id = existing_guest || AnalyticsIdentity.guest_or_new(conn)

      conn =
        case Clicks.capture(link, %{client_id: nil, guest_id: guest_id}) do
          {:ok, captured_guest} when captured_guest != existing_guest ->
            AnalyticsIdentity.put_guest_cookie(conn, captured_guest)

          _ ->
            conn
        end

      conn
      |> put_resp_header("cache-control", "no-store")
      |> redirect(external: carry_parameters(destination, conn.query_params))
    else
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end

  defp carry_parameters(destination, params) do
    query =
      params
      |> Map.take(@parameters)
      |> Enum.filter(fn {key, value} -> valid_parameter?(key, value) end)
      |> Enum.sort_by(&elem(&1, 0))
      |> URI.encode_query()

    if query == "", do: destination, else: destination <> "?" <> query
  end

  defp valid_parameter?(key, value) when key in @numeric_parameters and is_binary(value),
    do: byte_size(value) in 1..128 and Regex.match?(~r/^[0-9]+$/, value)

  defp valid_parameter?(key, value) when key in @utm_parameters and is_binary(value) do
    byte_size(value) in 1..64 and Regex.match?(~r/^[a-z0-9]+(?:[-_][a-z0-9]+)*$/, value) and
      String.length(String.replace(value, ~r/\D/, "")) < 7
  end

  defp valid_parameter?("product", value) when is_binary(value) do
    byte_size(value) in 1..80 and
      (match?({:ok, _}, Ecto.UUID.cast(value)) or
         Regex.match?(~r/^[a-z0-9]+(?:[-_][a-z0-9]+)*$/, value))
  end

  defp valid_parameter?(_key, _value), do: false
end
