defmodule Delivest.SiteSnapshot.Branches do
  @moduledoc """
  Target branch resolution and branch record writes shared by the import plan
  and its application phase.
  """

  alias Delivest.Repo
  alias Delivest.Identity.Branch
  alias Delivest.SiteSnapshot.Mapping

  @entity "branches"

  def entity, do: @entity

  def find_target(source, source_id, slug) do
    mapped =
      Repo.get_by(Mapping,
        source_installation_id: source,
        entity_type: @entity,
        source_id: source_id
      )

    cond do
      mapped -> Repo.get(Branch, mapped.target_id)
      is_binary(slug) -> Repo.get_by(Branch, slug: slug)
      true -> nil
    end
  end

  def put_mapping!(source, target_id, source_id) do
    existing =
      Repo.get_by(Mapping,
        source_installation_id: source,
        entity_type: @entity,
        source_id: source_id
      )

    cond do
      existing && existing.target_id == target_id ->
        :ok

      existing ->
        abort!({:conflicting_mapping, @entity, source_id, [existing.target_id, target_id]})

      Repo.get_by(Mapping,
        source_installation_id: source,
        entity_type: @entity,
        target_id: target_id
      ) ->
        abort!({:ambiguous_branch, source_id, target_id})

      true ->
        Repo.insert!(%Mapping{
          source_installation_id: source,
          target_branch_id: target_id,
          entity_type: @entity,
          source_id: source_id,
          target_id: target_id
        })
    end
  end

  def put!(branch, attrs, opts \\ []) do
    if Keyword.get(opts, :validate_conflicts, true), do: validate_conflicts!(attrs, branch)

    code = resolve_code(attrs["code"], attrs["slug"], branch)

    branch
    |> Branch.changeset(Map.put(attrs, "code", code))
    |> Ecto.Changeset.put_change(:deleted_at, nil)
    |> save!()
  end

  defp validate_conflicts!(attrs, branch) do
    slug = attrs["slug"]
    slug_match = if is_binary(slug), do: Repo.get_by(Branch, slug: slug)

    if slug_match && slug_match.id != branch.id, do: abort!({:branch_conflict, :slug})

    name = attrs["name"]
    name_match = if is_binary(name), do: Repo.get_by(Branch, name: name)

    if name_match && name_match.id != branch.id, do: abort!({:branch_conflict, :name})
  end

  defp resolve_code(code, slug, branch) do
    preferred =
      case normalize_code(code) do
        value when is_binary(value) and byte_size(value) >= 2 -> value
        _ -> slug |> Branch.code_from() |> pad_code()
      end

    cond do
      branch.id && branch.code == preferred ->
        preferred

      branch.id && is_binary(branch.code) ->
        branch.code

      true ->
        free_code(preferred, branch.id)
    end
  end

  defp normalize_code(code) when is_binary(code) do
    code
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]/, "")
    |> String.slice(0, 6)
  end

  defp normalize_code(_code), do: nil

  defp pad_code(code) when byte_size(code) >= 2, do: code
  defp pad_code(_code), do: "BR"

  defp free_code(base, branch_id) do
    base = String.slice(base, 0, 6)

    candidates =
      [base] ++
        Enum.map(1..99, fn number ->
          suffix = Integer.to_string(number)
          String.slice(base, 0, 6 - String.length(suffix)) <> suffix
        end)

    Enum.find(candidates, fn candidate ->
      String.length(candidate) in 2..6 and
        case Repo.get_by(Branch, code: candidate) do
          nil -> true
          %Branch{id: id} -> id == branch_id
        end
    end) || abort!(:branch_code_conflict)
  end

  defp save!(changeset) do
    case Repo.insert_or_update(changeset) do
      {:ok, record} -> record
      {:error, reason} -> abort!(reason)
    end
  end

  defp abort!(reason), do: throw({:snapshot_abort, reason})
end
