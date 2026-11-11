defmodule Delivest.Advertising.Links do
  @moduledoc "Staff-managed, branch-scoped registry of safe advertising redirects."
  import Ecto.Query

  alias Delivest.{Audit, Features, Repo}
  alias Delivest.Advertising.Link
  alias Delivest.Identity.{Acl, Branch}

  @page_size 50

  def list(staff, branch_id, cursor \\ nil) do
    with :ok <- authorized(staff, branch_id),
         true <- Features.enabled?("analytics_links", {:branch, branch_id}),
         {:ok, query} <- page_query(branch_id, cursor) do
      results = Repo.all(from l in query, limit: @page_size + 1)
      links = Enum.take(results, @page_size)
      has_more = length(results) > @page_size
      last = List.last(links)

      {:ok,
       %{
         links: links,
         has_more: has_more,
         next_cursor: if(has_more, do: {last.inserted_at, last.id})
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  def create(staff, branch_id, attrs) do
    with :ok <- authorized(staff, branch_id),
         {:ok, generation} <- Features.snapshot("analytics_links", {:branch, branch_id}) do
      link = %Link{
        branch_id: branch_id,
        token: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
      }

      changeset = Link.changeset(link, attrs)

      if changeset.valid? do
        Features.with_enabled("analytics_links", {:branch, branch_id}, generation, fn ->
          Repo.insert!(changeset)
        end)
        |> Audit.track(staff, "advertising_link.created", branch_id: branch_id)
      else
        {:error, changeset}
      end
    else
      _ -> {:error, :unavailable}
    end
  end

  def set_enabled(staff, branch_id, id, enabled) when is_boolean(enabled) do
    mutate(staff, branch_id, id, "advertising_link.updated", fn link ->
      Ecto.Changeset.change(link, enabled: enabled)
    end)
  end

  def archive(staff, branch_id, id) do
    mutate(staff, branch_id, id, "advertising_link.archived", fn link ->
      Ecto.Changeset.change(link,
        archived_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      )
    end)
  end

  def resolve(token) when is_binary(token) and byte_size(token) == 32 do
    Repo.one(
      from l in Link,
        join: b in Branch,
        on: b.id == l.branch_id,
        where: l.token == ^token and b.is_active == true and is_nil(b.deleted_at),
        select: {l, b.slug}
    )
  end

  def resolve(_), do: nil

  defp authorized(staff, branch_id) do
    with {:ok, branch_id} <- Ecto.UUID.cast(branch_id),
         :ok <- Acl.authorize(staff, "statistics.read", branch_id),
         %Branch{is_active: true, deleted_at: nil} <- Repo.get(Branch, branch_id) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  defp page_query(branch_id, nil) do
    {:ok,
     from(l in Link,
       where: l.branch_id == ^branch_id,
       order_by: [desc: l.inserted_at, desc: l.id]
     )}
  end

  defp page_query(branch_id, {%DateTime{} = inserted_at, id}) when is_binary(id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok,
       from(l in Link,
         where:
           l.branch_id == ^branch_id and
             (l.inserted_at < ^inserted_at or (l.inserted_at == ^inserted_at and l.id < ^id)),
         order_by: [desc: l.inserted_at, desc: l.id]
       )}
    end
  end

  defp page_query(_, _), do: {:error, :invalid_cursor}

  defp mutate(staff, branch_id, id, action, fun) do
    with :ok <- authorized(staff, branch_id),
         {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, generation} <- Features.snapshot("analytics_links", {:branch, branch_id}) do
      Features.with_enabled("analytics_links", {:branch, branch_id}, generation, fn ->
        case Repo.one(
               from l in Link,
                 where: l.id == ^id and l.branch_id == ^branch_id and is_nil(l.archived_at),
                 lock: "FOR UPDATE"
             ) do
          nil -> Repo.rollback(:not_found)
          link -> Repo.update!(fun.(link))
        end
      end)
      |> Audit.track(staff, action, branch_id: branch_id)
    else
      _ -> {:error, :unavailable}
    end
  end
end
