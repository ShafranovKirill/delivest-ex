defmodule Delivest.Popular.Settings do
  @moduledoc """
  Per-branch settings for the popular products shown to customers.

  `mode` controls where the list comes from:

    * `:off` – the popular block is hidden;
    * `:auto` – the top `auto_limit` products by sales are computed on the fly;
    * `:manual` – the ordered list from `popular_products` is used.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @modes [:off, :auto, :manual]
  @auto_limit_range 1..24

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "popular_settings" do
    field :mode, Ecto.Enum, values: @modes, default: :off
    field :auto_limit, :integer, default: 6
    field :show_in_menu, :boolean, default: false
    field :show_in_cart, :boolean, default: true
    belongs_to :branch, Delivest.Identity.Branch

    timestamps(type: :utc_datetime)
  end

  def modes, do: @modes
  def auto_limit_range, do: @auto_limit_range

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:mode, :auto_limit, :show_in_menu, :show_in_cart])
    |> validate_required([:mode, :show_in_menu, :show_in_cart])
    |> validate_inclusion(:mode, @modes)
    |> validate_number(:auto_limit,
      greater_than_or_equal_to: @auto_limit_range.first,
      less_than_or_equal_to: @auto_limit_range.last
    )
  end
end
