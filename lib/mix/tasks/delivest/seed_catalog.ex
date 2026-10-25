defmodule Mix.Tasks.Delivest.SeedCatalog do
  use Mix.Task

  @shortdoc "Seeds the first branch with the example catalog and product photos from priv/images"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Delivest.ExampleSeed.seed_catalog()
  end
end
