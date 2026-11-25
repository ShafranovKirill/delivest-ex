defmodule DelivestWeb.OpenApi do
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}
  alias DelivestWeb.{Endpoint, Router}
  @behaviour OpenApi

  @impl OpenApi
  def spec do
    build_spec(Server.from_endpoint(Endpoint))
  end

  @doc "Build the same contract without starting the Endpoint or connecting to a database."
  def export_spec do
    build_spec(%Server{url: "/"})
  end

  defp build_spec(server) do
    %OpenApi{
      servers: [server],
      info: %Info{
        title: "My App",
        version: "1.0",
        description: "Все суммы — в копейках, целым числом."
      },
      components: %Components{
        securitySchemes: %{
          "bearer" => %SecurityScheme{type: "http", scheme: "bearer", bearerFormat: "JWT"},
          "yandexEdaBearer" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            description: "OAuth token from /integrations/yandex-eda/security/oauth/token"
          }
        }
      },
      paths: Paths.from_router(Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
