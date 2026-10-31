defmodule Delivest.Fiscal.BranchSettings do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Fiscal.Vat
  alias Delivest.Integrations.AtolOnline

  @modes [:own, :external, :off]
  @snos [:osn, :usn_income, :usn_income_outcome, :esn, :patent]
  @courier_cards [:receipt, :terminal]

  @primary_key false
  embedded_schema do
    field :mode, Ecto.Enum, values: @modes, default: :off
    field :provider, Ecto.Enum, values: [:atol], default: :atol
    field :inn, :string
    field :sno, Ecto.Enum, values: @snos, default: :usn_income
    field :payment_address, :string
    field :email, :string
    field :vat, Ecto.Enum, values: Vat.rates(), default: :none
    field :delivery_vat, Ecto.Enum, values: Vat.rates(), default: :none
    field :courier_card, Ecto.Enum, values: @courier_cards, default: :receipt
    embeds_one :atol, AtolOnline.Settings, on_replace: :update
  end

  def modes, do: @modes
  def snos, do: @snos
  def courier_cards, do: @courier_cards

  def changeset(settings, attrs) do
    changeset =
      settings
      |> cast(attrs, [
        :mode,
        :provider,
        :inn,
        :sno,
        :payment_address,
        :email,
        :vat,
        :delivery_vat,
        :courier_card
      ])

    own? = get_field(changeset, :mode) == :own

    changeset
    |> cast_embed(:atol, with: &AtolOnline.Settings.changeset(&1, &2, own?))
    |> validate_own(own?)
    |> validate_format(:inn, ~r/^\d{10}(\d{2})?$/)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/)
  end

  def own?(%__MODULE__{mode: :own}), do: true
  def own?(_settings), do: false

  defp validate_own(changeset, true),
    do: validate_required(changeset, [:inn, :sno, :payment_address, :email, :atol])

  defp validate_own(changeset, false), do: changeset
end
