defmodule DelivestWeb.ErrorHTML do
  @moduledoc "HTML error pages rendered without the application layout or database."
  use DelivestWeb, :html

  def render("404.html", assigns) do
    set_error_locale(assigns)

    assigns
    |> Map.put(:__changed__, nil)
    |> Map.put(:title, gettext("Page not found"))
    |> Map.put(:message, gettext("The page you requested is unavailable."))
    |> error_page()
  end

  def render("500.html", assigns) do
    set_error_locale(assigns)

    assigns
    |> Map.put(:__changed__, nil)
    |> Map.put(:title, gettext("Something went wrong!"))
    |> Map.put(:message, gettext("Try again in a moment."))
    |> error_page()
  end

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)

  defp set_error_locale(assigns) do
    session_locale =
      case Map.get(assigns, :conn) do
        %Plug.Conn{private: %{plug_session: session}} ->
          Map.get(session, "locale") || Map.get(session, :locale)

        _ ->
          nil
      end

    DelivestWeb.Plugs.Locale.set_locale(
      session_locale || DelivestWeb.Plugs.Locale.default_locale()
    )
  end

  defp error_page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={Gettext.get_locale(DelivestWeb.Gettext)}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@title} · Delivest</title>
        <style phx-no-curly-interpolation>
          :root {
            color-scheme: light;
            font-family: system-ui, sans-serif;
            background: #f5f7fa;
            color: #172033;
          }
          body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            padding: 1.5rem;
            box-sizing: border-box;
          }
          main {
            width: min(100%, 28rem);
            padding: clamp(1.5rem, 5vw, 2.5rem);
            box-sizing: border-box;
            border: 1px solid #dce3ec;
            border-radius: 1rem;
            background: #fff;
            box-shadow: 0 18px 50px #17203310;
          }
          .brand {
            margin: 0 0 2.5rem;
            color: #2762a5;
            font-size: .875rem;
            font-weight: 800;
            letter-spacing: .06em;
            text-transform: uppercase;
          }
          h1 {
            margin: 0;
            font-size: clamp(1.75rem, 6vw, 2.5rem);
            line-height: 1.15;
          }
          p {
            margin: 1rem 0 2rem;
            line-height: 1.6;
            color: #516073;
          }
          a {
            display: inline-block;
            border-radius: .5rem;
            padding: .75rem 1rem;
            background: #2762a5;
            color: #fff;
            font-weight: 650;
            text-decoration: none;
          }
          a:hover { background: #194d87; }
          a:focus-visible {
            outline: 3px solid #2762a5;
            outline-offset: 3px;
          }
          @media (prefers-color-scheme: dark) {
            :root {
              color-scheme: dark;
              background: #161e2a;
              color: #f4f7fb;
            }
            main {
              background: #202d3e;
              border-color: #3b4b60;
              box-shadow: none;
            }
            .brand { color: #83bbf4; }
            p { color: #bdcad9; }
            a { background: #83bbf4; color: #12243a; }
            a:hover { background: #a7d0fb; }
            a:focus-visible { outline-color: #83bbf4; }
          }
        </style>
      </head>
      <body>
        <main>
          <p class="brand">Delivest</p>
          <h1>{@title}</h1>
          <p>{@message}</p>
          <a href="/">{gettext("Home")}</a>
        </main>
      </body>
    </html>
    """
  end
end
