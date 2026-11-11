defmodule DelivestWeb.Advertising.RedirectController do
  use DelivestWeb, :controller

  alias Delivest.Advertising.{Clicks, Links}
  alias DelivestWeb.{AdvertisingDestination, AnalyticsIdentity}

  def show(conn, %{"token" => token}) do
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

      conn |> put_resp_header("cache-control", "no-store") |> redirect(external: destination)
    else
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end
end
