defmodule Delivest.Relations.EntityRelations do
  import Ecto.Query
  alias Delivest.Repo
  alias Delivest.Relations.EntityRelation

  def create_relation(from_type, from_id, to_type, to_id, payload \\ %{}) do
    %EntityRelation{}
    |> EntityRelation.changeset(%{
      from_entity_type: from_type,
      from_id: from_id,
      to_entity_type: to_type,
      to_id: to_id,
      payload: payload
    })
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:from_entity_type, :from_id, :to_entity_type, :to_id]
    )
  end

  def delete_relation(from_type, from_id, to_type, to_id) do
    from(er in EntityRelation,
      where: er.from_entity_type == ^from_type and er.from_id == ^from_id,
      where: er.to_entity_type == ^to_type and er.to_id == ^to_id
    )
    |> Repo.delete_all()
  end

  def list_target_ids(from_type, from_id, target_type) do
    from(er in EntityRelation,
      where: er.from_entity_type == ^from_type and er.from_id == ^from_id,
      where: er.to_entity_type == ^target_type,
      select: er.to_id
    )
    |> Repo.all()
  end

  def list_source_ids(target_type, target_id, source_type) do
    from(er in EntityRelation,
      where: er.to_entity_type == ^target_type and er.to_id == ^target_id,
      where: er.from_entity_type == ^source_type,
      select: er.from_id
    )
    |> Repo.all()
  end
end
