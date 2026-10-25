defmodule Mix.Tasks.Delivest.SeedStocks do
  use Mix.Task

  @shortdoc "Seeds the first branch with the example promotions and their photos from priv/images"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Delivest.ExampleSeed.seed_stocks()
  end
end
