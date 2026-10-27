defmodule Delivest.Integrations.Crm.BranchSettings do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Integrations.Crm.Registry

  @providers Registry.keys()

  @primary_key false
  embedded_schema do
    field :enabled, :boolean, default: false
    field :provider, Ecto.Enum, values: @providers
    field :sources, {:array, :string}, default: ~w(app staff)

    for module <- Registry.modules() do
      embeds_one module.key(), module.settings_schema(), on_replace: :update
    end
  end

  def providers, do: @providers

  def changeset(settings, attrs) do
    changeset =
      settings
      |> cast(attrs, [:enabled, :provider, :sources])
      |> validate_subset(:sources, Delivest.Oms.OrderSource.all())

    Registry.modules()
    |> Enum.reduce(changeset, &cast_provider(&2, &1, active?(changeset, &1.key())))
    |> validate_active_provider()
  end

  def active_provider(%__MODULE__{enabled: true, provider: provider}), do: provider
  def active_provider(_settings), do: nil

  def provider_for(%__MODULE__{} = settings, source) do
    if to_string(source) in (settings.sources || []), do: active_provider(settings)
  end

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
