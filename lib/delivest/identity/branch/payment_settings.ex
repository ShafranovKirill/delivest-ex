defmodule Delivest.Identity.Branch.PaymentSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @methods [:cash, :card_offline, :online]

  @primary_key false

  embedded_schema do
    field :cash, :boolean, default: true
    field :card_offline, :boolean, default: true
    field :online, :boolean, default: false
    field :skip_confirmation_call, :boolean, default: false
  end

  def methods, do: @methods

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:cash, :card_offline, :online, :skip_confirmation_call])
    |> clear_call_without_online()
    |> validate_any_method()
  end

  def enabled(%__MODULE__{} = settings, online_ready? \\ true) do
    Enum.filter(@methods, fn
      :online -> settings.online and online_ready?
      method -> Map.fetch!(settings, method)
    end)
  end

  defp clear_call_without_online(changeset) do
    if get_field(changeset, :online),
      do: changeset,
      else: put_change(changeset, :skip_confirmation_call, false)
  end

  defp validate_any_method(changeset) do
    if Enum.any?(@methods, &get_field(changeset, &1)),
      do: changeset,
      else: add_error(changeset, :cash, "Enable at least one payment method")
  end
end
