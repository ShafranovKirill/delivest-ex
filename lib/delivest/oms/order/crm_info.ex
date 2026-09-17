defmodule Delivest.Oms.Order.CrmInfo do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :last_error, :string
    field :sent_at, :utc_datetime
  end

  def changeset(crm_info, attrs) do
    crm_info
    |> cast(attrs, [:status, :attempts, :last_error, :sent_at])
    |> validate_required([:status])
    |> validate_number(:attempts, greater_than_or_equal_to: 0)
  end
end
