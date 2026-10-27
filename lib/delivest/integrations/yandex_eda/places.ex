defmodule Delivest.Integrations.YandexEda.Places do
  alias Delivest.Identity
  alias Delivest.Identity.Branch
  alias Delivest.Integrations.YandexEda.BranchSettings

  def list do
    for branch <- Identity.list_branches(preload: [:info]), settings(branch), do: branch
  end

  def fetch(restaurant_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(restaurant_id),
         {:ok, %Branch{} = branch} <- Identity.get_branch(restaurant_id, preload: [:info]),
         %BranchSettings{enabled: true} = settings <- settings(branch) do
      {:ok, branch, settings}
    else
      _ -> {:error, :restaurant_not_found}
    end
  end

  def settings(%Branch{info: %{channels: %{yandex_eda: %BranchSettings{} = settings}}}),
    do: settings

  def settings(_branch), do: nil

  def view(%Branch{} = branch),
    do: %{id: branch.id, title: branch.name, address: address(branch.info)}

  def availability(%Branch{} = branch),
    do: %{id: branch.id, enabled: branch.is_active == true and settings(branch).enabled}

  defp address(%{city: city, address: address}),
    do: [city, address] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq() |> Enum.join(", ")

  defp address(_info), do: ""
end
