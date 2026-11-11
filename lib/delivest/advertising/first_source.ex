defmodule Delivest.Advertising.FirstSource do
  use Ecto.Schema

  @primary_key {:client_id, :binary_id, autogenerate: false}
  schema "client_first_sources" do
    field :link_id, :binary_id
    field :landing_branch_id, :binary_id
    field :clicked_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
  end
end
