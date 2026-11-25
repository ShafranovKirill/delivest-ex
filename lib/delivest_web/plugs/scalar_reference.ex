defmodule DelivestWeb.Plugs.ScalarReference do
  @behaviour Plug

  import Plug.Conn

  @script "https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.84.0"

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(conn, _options) do
    html = """
    <!doctype html>
    <html lang="ru">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Delivest API</title>
      </head>
      <body>
        <div id="app"></div>
        <script src="#{@script}"></script>
        <script>
          Scalar.createApiReference('#app', {
            url: '/api/scalar/openapi',
            proxyUrl: '',
            withDefaultFonts: false,
            telemetry: false,
            persistAuth: false,
            agent: { disabled: true }
          })
        </script>
      </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html", "utf-8")
    |> send_resp(:ok, html)
  end
end
