defmodule Delivest.Integrations.Crm.BranchSettings do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Integrations.Crm.Registry

  @providers Registry.keys()

  @primary_key false
  embedded_schema do
    field :enabled, :boolean, default: false
    field :provider, Ecto.Enum, values: @providers

    for module <- Registry.modules() do
      embeds_one module.key(), module.settings_schema(), on_replace: :update
    end
  end

  def providers, do: @providers

  def changeset(settings, attrs) do
    changeset = cast(settings, attrs, [:enabled, :provider])

    Registry.modules()
    |> Enum.reduce(changeset, &cast_provider(&2, &1, active?(changeset, &1.key())))
    |> validate_active_provider()
  end

  def active_provider(%__MODULE__{enabled: true, provider: provider}), do: provider
  def active_provider(_settings), do: nil

  defp cast_provider(changeset, module, required?) do
    cast_embed(changeset, module.key(),
      with: &module.settings_schema().changeset(&1, &2, required?)
    )
  end

  defp validate_active_provider(changeset) do
    case get_field(changeset, :enabled) && get_field(changeset, :provider) do
      false -> changeset
      nil -> validate_required(changeset, [:provider])
      provider -> validate_required(changeset, [provider])
    end
  end

  defp active?(changeset, provider),
    do: get_field(changeset, :enabled) == true and get_field(changeset, :provider) == provider
end
