defmodule Mix.Tasks.Api.Check do
  use Mix.Task

  @shortdoc "Compare HTTP API routes with the OpenAPI contract and gap baseline"

  @impl Mix.Task
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [write_baseline: :boolean])

    if rest != [], do: Mix.raise("Usage: mix api.check [--write-baseline]")

    Mix.Task.run("app.config")
    Mix.Task.run("compile", ["--quiet"])

    catalog = DelivestWeb.ApiCatalog
    missing = catalog.missing()

    Mix.shell().info(
      "HTTP API routes: #{length(catalog.routes())}; undocumented contracts: #{length(missing)}"
    )

    Enum.each(missing, fn {method, path} ->
      Mix.shell().info("  #{String.upcase(method)} #{path}")
    end)

    if opts[:write_baseline] do
      json = missing |> Enum.map(&Tuple.to_list/1) |> Jason.encode!(pretty: true)
      File.write!(catalog.baseline_path(), json <> "\n")
      Mix.shell().info("Updated #{catalog.baseline_path()}")
    else
      {new, resolved} = catalog.baseline_diff(missing)

      if new != [] or resolved != [] do
        Enum.each(new, fn {method, path} ->
          Mix.shell().error("NEW GAP #{String.upcase(method)} #{path}")
        end)

        Enum.each(resolved, fn {method, path} ->
          Mix.shell().error("RESOLVED GAP #{String.upcase(method)} #{path}; update baseline")
        end)

        Mix.raise("API contract gap baseline changed")
      end
    end
  end
end
