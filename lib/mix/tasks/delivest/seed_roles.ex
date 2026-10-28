defmodule Mix.Tasks.Delivest.SeedRoles do
  use Mix.Task

  alias Delivest.Identity.RolePresets

  @shortdoc "Seeds the preset roles that are missing"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Enum.each(RolePresets.seed(), fn {result, name} ->
      Mix.shell().info("-> #{result}: #{name}")
    end)

    Mix.shell().info("Roles seeding completed.")
  end
end
