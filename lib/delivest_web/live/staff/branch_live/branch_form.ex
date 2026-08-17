defmodule DelivestWeb.Staff.BranchLive.BranchForm do
  use Ecto.Schema
  import Ecto.Changeset
  alias Delivest.Repo

  use Gettext, backend: Delivest.Gettext

  @primary_key false
  embedded_schema do
    field :name, :string

    field :address, :string
    field :phone_number, :string
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [:name, :address, :phone_number])
    |> validate_format(:phone_number, ~r/^\+7\d{10}$/,
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
      address: info && info.address,
      phone_number: info && info.phone_number
    }
  end

  def to_params(changeset) do
    data = apply_changes(changeset)

    branch_params =
      data
      |> Map.take([:name])
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    info_params =
      data
      |> Map.take([:address, :phone_number])
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    {branch_params, info_params}
  end
end
