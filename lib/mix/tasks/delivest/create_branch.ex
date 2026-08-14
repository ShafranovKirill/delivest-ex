defmodule Mix.Tasks.Delivest.CreateBranch do
  use Mix.Task

  alias Delivest.Repo
  alias Delivest.Net.Branch

  @shortdoc "Creates a default branch if not exists"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    branch_name = Application.get_env(:delivest, :default_branch_name, "Main Branch")
    branch_address = Application.get_env(:delivest, :default_branch_address, "Central Street 1")

    case Repo.get_by(Branch, name: branch_name) do
      nil ->
        branch_params = %{
          name: branch_name,
          address: branch_address
        }

        changeset = Branch.changeset(%Branch{}, branch_params)

        case Repo.insert(changeset) do
          {:ok, branch} ->
            Mix.shell().info("Default branch created: #{branch.name} (ID: #{branch.id})")

          {:error, changeset} ->
            Mix.shell().error("Failed to create default branch:")
            IO.inspect(changeset.errors)
        end

      _branch ->
        Mix.shell().info("Default branch already exists.")
    end
  end
end
