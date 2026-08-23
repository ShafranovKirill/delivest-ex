defmodule Delivest.Relations do
  alias Delivest.Relations.EntityRelations

  defdelegate create_relation(from_type, from_id, to_type, to_id, payload \\ %{}),
    to: EntityRelations

  defdelegate delete_relation(from_type, from_id, to_type, to_id), to: EntityRelations
  defdelegate list_target_ids(from_type, from_id, target_type), to: EntityRelations
  defdelegate list_source_ids(target_type, target_id, source_type), to: EntityRelations
end
