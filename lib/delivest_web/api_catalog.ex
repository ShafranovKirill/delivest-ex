defmodule DelivestWeb.ApiCatalog do
  @moduledoc """
  Compares the public OpenAPI contract with the HTTP API routes and builds a
  Scalar-only catalogue. Undocumented routes are visible, but explicitly marked
  as lacking a verified contract.
  """

  alias DelivestWeb.{OpenApi, Router}

  @methods ~w(get post put patch delete head options trace)a
  @preferred_tags [
    "Health",
    "Client",
    "Client auth",
    "Client branches",
    "Client storefront",
    "Client session",
    "Client cart",
    "Client orders"
  ]
  @baseline Path.expand("../../priv/api_contract_gaps.json", __DIR__)

  def public_spec do
    OpenApi.export_spec() |> Jason.encode!() |> Jason.decode!()
  end

  def routes do
    Router.__routes__()
    |> Enum.filter(fn route ->
      route.verb in @methods and
        (String.starts_with?(route.path, "/client/") or route.path == "/client" or
           String.starts_with?(route.path, "/integrations/") or
           route.path == "/integrations" or
           route.path in ["/health", "/ready"])
    end)
    |> Enum.map(fn route ->
      {Atom.to_string(route.verb),
       route.path |> String.replace(~r/:([a-zA-Z_][a-zA-Z_0-9]*)/, "{\\1}")}
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def missing(spec \\ public_spec()) do
    Enum.reject(routes(), fn {method, path} -> get_in(spec, ["paths", path, method]) end)
  end

  def baseline do
    @baseline
    |> File.read!()
    |> Jason.decode!()
    |> Enum.map(fn [method, path] -> {method, path} end)
  end

  def baseline_path, do: @baseline

  def baseline_diff(actual \\ missing()) do
    {actual -- baseline(), baseline() -- actual}
  end

  def scalar_spec(base_url \\ "{{baseUrl}}") do
    spec = public_spec()

    paths =
      Enum.reduce(missing(spec), spec["paths"], fn {method, path}, paths ->
        operation = %{
          "summary" => "[Контракт не описан] #{String.upcase(method)} #{path}",
          "description" =>
            "Маршрут существует, но его параметры, тело и ответы пока не подтверждены контрактом. Сверяйтесь с реализацией и тестами перед отправкой.",
          "tags" => [tag_for(path)],
          "x-delivest-contract-status" => "undocumented",
          "parameters" => path_parameters(path),
          "responses" => %{"default" => %{"description" => "Контракт ответа пока не описан"}}
        }

        Map.update(paths, path, %{method => operation}, &Map.put(&1, method, operation))
      end)

    paths =
      Enum.reduce(routes(), paths, fn {method, path}, paths ->
        update_in(paths, [path, method], &Map.put(&1, "tags", [tag_for(path)]))
      end)

    spec
    |> put_in(["info", "title"], "Delivest API")
    |> Map.put("paths", paths)
    |> Map.put("tags", ordered_tags())
    |> Map.put("x-delivest-contract-coverage", %{
      "routeCount" => length(routes()),
      "undocumentedCount" => length(missing(spec))
    })
    |> Map.put("x-scalar-environments", %{
      "local" => %{
        "description" => "Локальная разработка",
        "variables" => [
          %{"name" => "baseUrl", "value" => "http://127.0.0.1:4000"},
          %{"name" => "confirmationId", "value" => ""},
          %{"name" => "accessToken", "value" => ""},
          %{"name" => "refreshToken", "value" => ""}
        ]
      },
      "staging" => %{
        "description" => "Заполните адрес и тестовые учётные данные только в своём окружении",
        "variables" => [
          %{"name" => "baseUrl", "value" => ""},
          %{"name" => "confirmationId", "value" => ""},
          %{"name" => "accessToken", "value" => ""},
          %{"name" => "refreshToken", "value" => ""}
        ]
      }
    })
    |> Map.update!("servers", fn _ -> [%{"url" => base_url}] end)
    |> put_auth_scripts()
    |> put_safe_checks()
  end

  defp path_parameters(path) do
    Regex.scan(~r/\{([^}]+)\}/, path)
    |> Enum.map(fn [_, name] ->
      %{"name" => name, "in" => "path", "required" => true, "schema" => %{"type" => "string"}}
    end)
  end

  defp tag_for("/health"), do: "Health"
  defp tag_for("/ready"), do: "Health"

  defp tag_for(path) do
    case String.split(path, "/", trim: true) do
      ["client", "auth" | _] -> "Client auth"
      ["client", "cart" | _] -> "Client cart"
      ["client", "orders" | _] -> "Client orders"
      ["client", "geo" | _] -> "Client geo"
      ["client", "delivery" | _] -> "Client delivery"
      ["client", "franchise" | _] -> "Client franchise"
      ["client", "analytics" | _] -> "Client analytics"
      ["client", "addresses" | _] -> "Client addresses"
      ["client", "notifications" | _] -> "Client notifications"
      ["client", "storefront" | _] -> "Client storefront"
      ["client", "session" | _] -> "Client session"
      ["client", "branches" | _] -> "Client branches"
      ["integrations", provider | _] -> "Integrations: #{provider}"
      ["client" | _] -> "Client"
      _ -> "Integrations"
    end
  end

  defp ordered_tags do
    all = routes() |> Enum.map(fn {_, path} -> tag_for(path) end) |> Enum.uniq()
    ordered = @preferred_tags |> Enum.filter(&(&1 in all))
    (ordered ++ Enum.sort(all -- ordered)) |> Enum.map(&%{"name" => &1})
  end

  defp put_auth_scripts(spec) do
    spec =
      update_in(spec, ["paths", "/client/auth/call", "post"], fn operation ->
        Map.put(operation, "x-post-response", """
        if (pm.response.code === 200) {
          const id = pm.response.json().data.confirmation_id
          if (id) pm.environment.set('confirmationId', id)
        }
        """)
      end)

    spec =
      Enum.reduce(
        ["/client/auth/call/{id}/complete", "/client/auth/refresh"],
        spec,
        fn path, spec ->
          update_in(spec, ["paths", path, "post"], fn operation ->
            Map.put(operation, "x-post-response", """
            if (pm.response.code === 200) {
              const data = pm.response.json().data
              if (data.access_token && data.refresh_token) {
                pm.environment.set('accessToken', data.access_token)
                pm.environment.set('refreshToken', data.refresh_token)
              }
            }
            """)
          end)
        end
      )

    Enum.reduce(routes(), spec, fn {method, path}, spec ->
      update_in(spec, ["paths", path, method], fn operation ->
        if operation["security"] == [%{"bearer" => []}] do
          Map.put(operation, "x-pre-request", """
          const token = pm.environment.get('accessToken')
          if (token) pm.request.headers.upsert({ key: 'Authorization', value: 'Bearer ' + token })
          """)
        else
          operation
        end
      end)
    end)
  end

  defp put_safe_checks(spec) do
    spec
    |> update_in(["paths", "/client/capabilities", "get"], fn
      nil ->
        nil

      operation ->
        Map.put(operation, "x-post-response", """
        pm.test('Capabilities response', () => {
          pm.response.to.have.status(200)
          pm.expect(pm.response.headers.get('Content-Type')).to.include('application/json')
          pm.expect(pm.response.json().api_version).to.eql(1)
        })
        """)
    end)
    |> update_in(["paths", "/health", "get"], fn operation ->
      Map.put(operation, "x-post-response", """
      pm.test('Health response', () => {
        pm.response.to.have.status(200)
        pm.expect(pm.response.headers.get('Content-Type')).to.include('application/json')
        pm.expect(pm.response.json().status).to.eql('ok')
        pm.expect(pm.response.json().app).to.eql('delivest')
      })
      """)
    end)
  end
end
