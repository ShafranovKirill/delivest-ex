defmodule Delivest.Integrations.Crm.BranchSettings do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Integrations.Frontpad

  @providers [:frontpad]

  @primary_key false
  embedded_schema do
    field :enabled, :boolean, default: false
    field :provider, Ecto.Enum, values: @providers
    embeds_one :frontpad, Frontpad.Settings, on_replace: :update
  end

  def providers, do: @providers

  def changeset(settings, attrs) do
    changeset = cast(settings, attrs, [:enabled, :provider])

    changeset
    |> cast_embed(:frontpad,
      with: &Frontpad.Settings.changeset(&1, &2, active?(changeset, :frontpad))
    )
    |> validate_active_provider()
  end

  def active_provider(%__MODULE__{enabled: true, provider: provider}), do: provider
  def active_provider(_settings), do: nil

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
