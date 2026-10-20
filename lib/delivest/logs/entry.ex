defmodule Delivest.Logs.Entry do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @derive {
    Flop.Schema,
    filterable: [:level, :message],
    sortable: [:inserted_at],
    default_order: %{order_by: [:inserted_at], order_directions: [:desc]},
    default_limit: 50,
    max_limit: 100
  }

  schema "app_logs" do
    field :level, :string
    field :message, :string
    field :source, :string
    field :metadata, :map, default: %{}
    field :inserted_at, :utc_datetime_usec
  end
end
