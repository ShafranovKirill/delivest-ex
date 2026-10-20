defmodule Delivest.Audit.Event do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @actor_types [:staff, :client, :guest, :system]

  @primary_key {:id, :binary_id, autogenerate: true}

  @derive {
    Flop.Schema,
    filterable: [:subject_type, :actor_type, :actor_id, :action, :branch_id],
    sortable: [:inserted_at, :actor_name, :action, :branch_name],
    join_fields: [branch_name: [binding: :branch, field: :name, ecto_type: :string]],
    default_order: %{order_by: [:inserted_at], order_directions: [:desc]},
    default_limit: 50,
    max_limit: 100
  }

  schema "audit_events" do
    field :action, :string
    field :actor_type, Ecto.Enum, values: @actor_types
    field :actor_id, :binary_id
    field :actor_name, :string
    field :subject_type, :string
    field :subject_id, :string
    field :subject_label, :string
    field :branch_id, :binary_id
    field :metadata, :map, default: %{}
    field :branch_name, :string, virtual: true

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def actor_types, do: @actor_types
end
