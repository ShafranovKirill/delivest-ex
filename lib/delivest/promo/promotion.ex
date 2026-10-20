defmodule Delivest.Promo.Promotion do
  use Ecto.Schema
  import Ecto.Changeset

  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Promo.{Dsl, PromoCode}
  alias Delivest.Promo.Dsl.Error

  @type t :: %__MODULE__{}

  @kinds [:automatic, :public_code, :personal_code]
  @code_format ~r/^[A-Z0-9_-]{3,32}$/

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "promotions" do
    field :branch_id, :binary_id
    field :name, :string
    field :description, :string
    field :kind, Ecto.Enum, values: @kinds, default: :automatic
    field :rules, :string
    field :enabled, :boolean, default: true
    field :combinable, :boolean, default: false
    field :priority, :integer, default: 0
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :usage_limit, :integer
    field :per_client_limit, :integer
    field :code, :string, virtual: true
    field :deleted_at, :utc_datetime

    has_many :codes, PromoCode

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def code_format, do: @code_format

  def changeset(promotion, attrs) do
    promotion
    |> cast(attrs, fields(promotion), empty_values: [nil, ""])
    |> update_change(:code, &PromoCode.normalize/1)
    |> validate_required([:name, :kind, :rules])
    |> validate_length(:name, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_length(:rules, max: 5000)
    |> validate_number(:usage_limit, greater_than: 0)
    |> validate_number(:per_client_limit, greater_than: 0)
    |> validate_number(:priority, greater_than_or_equal_to: -1000, less_than_or_equal_to: 1000)
    |> validate_window()
    |> validate_public_code()
    |> validate_rules()
  end

  def toggle_changeset(promotion), do: change(promotion, enabled: !promotion.enabled)

  def delete_changeset(promotion),
    do: change(promotion, deleted_at: DateTime.utc_now(:second), enabled: false)

  defp fields(%__MODULE__{id: nil}), do: [:kind | editable_fields()]
  defp fields(_promotion), do: editable_fields()

  defp editable_fields do
    [
      :name,
      :description,
      :rules,
      :enabled,
      :combinable,
      :priority,
      :starts_at,
      :ends_at,
      :usage_limit,
      :per_client_limit,
      :code
    ]
  end

  defp validate_window(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(ends_at, starts_at) != :gt,
      do: add_error(changeset, :ends_at, gettext("must be after the start")),
      else: changeset
  end

  defp validate_public_code(changeset) do
    if get_field(changeset, :kind) == :public_code do
      changeset
      |> validate_required([:code])
      |> validate_format(:code, @code_format,
        message: gettext("3–32 latin letters, digits, «-» or «_»")
      )
    else
      changeset
    end
  end

  defp validate_rules(changeset) do
    validate_change(changeset, :rules, fn :rules, rules ->
      case Dsl.parse(rules) do
        {:ok, _strategy} -> []
        {:error, errors} -> Enum.map(errors, &{:rules, Error.to_string(&1)})
      end
    end)
  end
end
