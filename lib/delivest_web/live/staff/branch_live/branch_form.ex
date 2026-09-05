defmodule DelivestWeb.Staff.BranchLive.BranchForm do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Identity
  alias Delivest.Repo

  use Gettext, backend: Delivest.Gettext

  @primary_key false
  embedded_schema do
    field :name, :string
    field :slug, :string
    field :is_active, :boolean

    field :address, :string
    field :phone_number, :string
    field :vk_url, :string
    field :whatsapp_url, :string
    field :instagram_url, :string
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [
      :name,
      :address,
      :phone_number,
      :vk_url,
      :whatsapp_url,
      :instagram_url,
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
      vk_url: info && info.vk_url,
      whatsapp_url: info && info.whatsapp_url,
      instagram_url: info && info.instagram_url
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
      |> Map.take([:address, :phone_number])
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    {branch_params, info_params}
  end
end
