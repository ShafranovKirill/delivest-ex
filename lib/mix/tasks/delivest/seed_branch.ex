defmodule Mix.Tasks.Delivest.SeedBranch do
  use Mix.Task

  @shortdoc "Fills the first branch info and the franchise settings with example data"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Delivest.ExampleSeed.seed_branch()
  end
end
