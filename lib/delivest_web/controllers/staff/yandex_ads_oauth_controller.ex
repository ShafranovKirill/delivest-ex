defmodule DelivestWeb.Staff.YandexAdsOAuthController do
  use DelivestWeb, :controller
  alias Delivest.Identity
  alias Delivest.Integrations.YandexAds
  alias Delivest.Integrations.YandexAds.OAuth

  def connect(conn, _) do
    if admin?(conn) do
      settings = YandexAds.get_settings()
      state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      case OAuth.authorize_url(state, settings) do
        {:ok, url} ->
          conn
          |> put_session(:yandex_ads_oauth, %{
            state: state,
            at: System.system_time(:second),
            generation: settings.generation
          })
          |> redirect(external: url)

        _ ->
          fail(
            conn,
            gettext("Set the Yandex OAuth application credentials in integration settings")
          )
      end
    else
      send_resp(conn, :forbidden, "Forbidden")
    end
  end

  def callback(conn, params) do
    saved = get_session(conn, :yandex_ads_oauth)
    conn = delete_session(conn, :yandex_ads_oauth)

    with true <- admin?(conn),
         %{state: state, at: at, generation: generation} <- saved,
         provided when is_binary(provided) <- params["state"],
         true <- byte_size(state) == byte_size(provided),
         true <- Plug.Crypto.secure_compare(state, provided),
         true <- (System.system_time(:second) - at) in 0..600,
         settings = YandexAds.get_settings(),
         true <- settings.generation == generation,
         {:ok, tokens} <- OAuth.exchange(params["code"], settings),
         {:ok, _} <-
           YandexAds.update_settings(
             conn.assigns.current_staff,
             %{
               "direct_token" => tokens["access_token"],
               "metrika_token" => tokens["access_token"],
               "refresh_token" => tokens["refresh_token"]
             },
             generation
           ) do
      conn
      |> put_flash(
        :info,
        "Yandex access connected; choose the counter and enable the required streams"
      )
      |> redirect(to: "/staff/integrations/yandex-ads")
    else
      _ -> fail(conn, "Could not connect Yandex. Check the access settings and try again.")
    end
  end

  defp admin?(conn),
    do: conn.assigns[:current_staff] && Identity.can?(conn.assigns.current_staff, "admin")

  defp fail(conn, message),
    do: conn |> put_flash(:error, message) |> redirect(to: "/staff/integrations/yandex-ads")
end
