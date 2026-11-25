defmodule Mix.Tasks.Api.Export do
  use Mix.Task

  @shortdoc "Export public or Scalar API OpenAPI JSON without starting the app"

  @impl Mix.Task
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [scalar: :boolean, output: :string])

    if rest != [], do: Mix.raise("Usage: mix api.export [--scalar] [--output PATH]")

    Mix.Task.run("app.config")
    Mix.Task.run("compile", ["--quiet"])

    spec =
      if opts[:scalar],
        do: DelivestWeb.ApiCatalog.scalar_spec(),
        else: DelivestWeb.ApiCatalog.public_spec()

    json = Jason.encode!(spec, pretty: true) <> "\n"

    if path = opts[:output] do
      File.write!(path, json)
      Mix.shell().info("Wrote #{path}")
    else
      IO.write(json)
    end
  end
end
