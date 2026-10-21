defmodule Delivest.Franchise.Documents do
  alias Delivest.Repo
  alias Delivest.Franchise.{LegalDocument, Templates}

  def list do
    stored = LegalDocument |> Repo.all() |> Map.new(&{&1.kind, &1})
    Enum.map(LegalDocument.kinds(), &entry(&1, stored[&1]))
  end

  def get(kind) when is_atom(kind), do: entry(kind, Repo.get_by(LegalDocument, kind: kind))

  def save(kind, body) do
    (Repo.get_by(LegalDocument, kind: kind) || %LegalDocument{kind: kind})
    |> LegalDocument.changeset(%{body: body})
    |> Repo.insert_or_update()
  end

  def reset(kind) do
    case Repo.get_by(LegalDocument, kind: kind) do
      nil -> {:ok, nil}
      document -> Repo.delete(document)
    end
  end

  def parse_kind(value) do
    Enum.find(LegalDocument.kinds(), :error, &(to_string(&1) == value))
  end

  defp entry(kind, nil),
    do: %{kind: kind, body: Templates.default(kind), custom: false, updated_at: nil}

  defp entry(kind, document),
    do: %{kind: kind, body: document.body, custom: true, updated_at: document.updated_at}
end
