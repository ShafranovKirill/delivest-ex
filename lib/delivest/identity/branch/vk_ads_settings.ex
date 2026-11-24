defmodule Delivest.Identity.Branch.VkAdsSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @counter_id ~r/\A[0-9]{1,20}\z/

  embedded_schema do
    field :enabled, :boolean, default: false
    field :counter_id, :string
    field :privacy_approved, :boolean, default: false
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:enabled, :counter_id, :privacy_approved])
    |> update_change(:counter_id, fn id -> if is_binary(id), do: String.trim(id), else: id end)
    |> validate_format(:counter_id, @counter_id)
    |> validate_activation()
  end

  def public_config(%__MODULE__{enabled: true, privacy_approved: true, counter_id: id})
      when is_binary(id) do
    if Delivest.Integrations.StaffAccess.allowed?(:vk_ads) and valid_counter_id?(id),
      do: %{enabled: true, counter_id: id},
      else: %{enabled: false, counter_id: nil}
  end

  def public_config(_), do: %{enabled: false, counter_id: nil}

  defp validate_activation(changeset) do
    if get_field(changeset, :enabled) do
      changeset
      |> validate_required([:counter_id])
      |> then(fn cs ->
        if valid_counter_id?(get_field(cs, :counter_id)),
          do: cs,
          else: add_error(cs, :counter_id, "must be a positive numeric ID")
      end)
      |> then(fn cs ->
        if get_field(cs, :privacy_approved),
          do: cs,
          else: add_error(cs, :privacy_approved, "must be confirmed before enabling")
      end)
    else
      changeset
    end
  end

  defp valid_counter_id?(id) when is_binary(id),
    do: Regex.match?(@counter_id, id) and String.to_integer(id) > 0

  defp valid_counter_id?(_), do: false
end
