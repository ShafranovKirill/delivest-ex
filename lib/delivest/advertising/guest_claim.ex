defmodule Delivest.Advertising.GuestClaim do
  use Ecto.Schema

  @primary_key {:guest_id, :binary_id, autogenerate: false}
  schema "advertising_guest_claims" do
    field :client_id, :binary_id
    field :claimed_at, :utc_datetime_usec
  end
end
