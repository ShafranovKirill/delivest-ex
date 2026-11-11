defmodule Delivest.Advertising.OrderAttribution do
  @moduledoc "Immutable advertising touch fixed in the order creation transaction."
  use Ecto.Schema

  @primary_key {:order_id, :binary_id, autogenerate: false}
  schema "advertising_order_receipts" do
    field :link_id, :binary_id
    field :landing_branch_id, :binary_id
    field :clicked_at, :utc_datetime_usec
    field :as_of_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
  end
end
