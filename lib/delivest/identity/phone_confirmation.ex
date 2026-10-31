defmodule Delivest.Identity.PhoneConfirmation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Identity

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "phone_confirmations" do
    field :phone, :string
    field :session_id, :string
    field :call_id, :string
    field :call_number, :string
    field :mode, Ecto.Enum, values: [:inbound, :flash], default: :inbound
    field :code, :string, redact: true
    field :attempts, :integer, default: 0
    field :confirmed_at, :utc_datetime
    field :consumed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(confirmation, attrs) do
    confirmation
    |> cast(attrs, [:phone, :session_id, :call_id, :call_number, :mode, :code])
    |> validate_required([:phone, :session_id, :call_id])
    |> validate_format(:phone, Identity.phone_regex())
  end
end
