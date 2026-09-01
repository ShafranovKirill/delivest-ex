defmodule DelivestWeb.Client.Branch.BranchJSON do
  def index(%{branches: branches}) do
    %{data: for(branch <- branches, do: branch_data(branch))}
  end

  def show(%{branch: branch}) do
    %{data: branch_data(branch)}
  end

  defp branch_data(branch) do
    %{
      id: branch.id,
      name: branch.name,
      slug: branch.slug,
      is_active: branch.is_active,
      branch_info: branch_info(branch.info)
    }
  end

  defp branch_info(%Ecto.Association.NotLoaded{}), do: nil
  defp branch_info(nil), do: nil

  defp branch_info(info) do
    %{
      id: info.id,
      address: info.address,
      phone_number: info.phone_number
    }
  end
end
