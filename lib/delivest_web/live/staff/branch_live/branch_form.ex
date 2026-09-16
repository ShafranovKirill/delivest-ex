defmodule DelivestWeb.Staff.BranchLive.BranchForm do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Identity
  alias Delivest.Repo

  use Gettext, backend: DelivestWeb.Gettext

  @primary_key false
  embedded_schema do
    field :name, :string
    field :slug, :string
    field :is_active, :boolean

    field :address, :string
    field :phone_number, :string
    field :delivery_time, :integer
    field :vk_url, :string
    field :whatsapp_url, :string
    field :instagram_url, :string
    field :frontpad_api_key, :string
    field :frontpad_enabled, :boolean, default: false
    field :frontpad_settings, :map, default: %{}
  end

  def changeset(form, attrs) do
    attrs = normalize_frontpad_settings(attrs)

    form
    |> cast(attrs, [
      :name,
      :address,
      :phone_number,
      :delivery_time,
      :vk_url,
      :whatsapp_url,
      :instagram_url,
      :frontpad_api_key,
      :frontpad_enabled,
      :frontpad_settings,
      :slug,
      :is_active
    ])
    |> validate_format(:phone_number, Identity.phone_regex(),
      message:
        dgettext_noop(
          "errors",
          "The number must be in the format +7XXXXXXXXXX"
        )
    )
  end

  def from_branch(branch) do
    branch = Repo.preload(branch, :info)
    info = branch.info

    %__MODULE__{
      name: branch.name,
      slug: branch.slug,
      is_active: branch.is_active,
      address: info && info.address,
      phone_number: info && info.phone_number,
      delivery_time: info && info.delivery_time,
      vk_url: info && info.vk_url,
      whatsapp_url: info && info.whatsapp_url,
      instagram_url: info && info.instagram_url,
      frontpad_api_key: info && info.frontpad_api_key,
      frontpad_enabled: info && info.frontpad_enabled,
      frontpad_settings: encode_frontpad_settings(info && info.frontpad_settings)
    }
  end

  def to_params(changeset) do
    data = apply_changes(changeset)

    branch_params =
      data
      |> Map.take([:name, :slug, :is_active])
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    info_params =
      data
      |> Map.take([
        :address,
        :phone_number,
        :delivery_time,
        :vk_url,
        :whatsapp_url,
        :instagram_url,
        :frontpad_api_key,
        :frontpad_enabled,
        :frontpad_settings
      ])
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    {branch_params, info_params}
  end

  defp normalize_frontpad_settings(%{} = attrs) do
    key =
      if Map.has_key?(attrs, "frontpad_settings"),
        do: "frontpad_settings",
        else: :frontpad_settings

    case Map.get(attrs, key) do
      value when is_binary(value) ->
        case Jason.decode(value) do
          {:ok, %{} = settings} -> Map.put(attrs, key, settings)
          {:ok, settings} when is_list(settings) -> Map.put(attrs, key, %{"items" => settings})
          {:error, _} -> Map.put(attrs, key, %{})
        end

      value when is_map(value) ->
        Map.put(attrs, key, value)

      _ ->
        attrs
    end
  end

  defp normalize_frontpad_settings(other), do: other

  defp encode_frontpad_settings(nil), do: "{}"

  defp encode_frontpad_settings(settings) when is_map(settings) do
    settings
    |> Jason.encode!()
  end

  defp encode_frontpad_settings(settings) when is_binary(settings), do: settings
  defp encode_frontpad_settings(_), do: "{}"
end
