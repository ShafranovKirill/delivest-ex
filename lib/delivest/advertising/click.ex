defmodule Delivest.Advertising.Click do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "advertising_clicks" do
    field :link_id, :binary_id
    field :branch_id, :binary_id
    field :guest_id, :binary_id
    field :client_id, :binary_id
    field :clicked_at, :utc_datetime_usec
  end
end
