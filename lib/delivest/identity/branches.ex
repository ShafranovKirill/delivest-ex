defmodule Delivest.Identity.Branches do
  import Ecto.Query
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Identity.{Branch}
  alias Delivest.{Repo, Identity}
  alias Delivest.Audit

  @integrations [
    "crm",
    "channels",
    "yandex_delivery",
    "fiscal",
    :crm,
    :channels,
    :yandex_delivery,
    :fiscal
  ]
  @own_settings @integrations ++ ["couriers", :couriers]

  @spec list_branch_for_staff(Delivest.Identity.Staff.t(), keyword()) :: [Branch.t()]
  def list_branch_for_staff(staff, opts \\ []) do
    permissions = staff.role.permissions || []

    Branch
    |> where([b], is_nil(b.deleted_at))
    |> then(fn query ->
      cond do
        "admin" in permissions ->
          query

        true ->
          branch_ids = Enum.map(staff.branches || [], & &1.id)
          where(query, [b], b.id in ^branch_ids)
      end
    end)
    |> maybe_preload_query(opts[:preload])
    |> Repo.all()
  end

  def list_branches(opts \\ []) do
    Branch
    |> where([b], is_nil(b.deleted_at) and b.is_active == true)
    |> maybe_preload_query(opts[:preload])
    |> Repo.all()
  end

  defp maybe_preload_query(query, nil), do: query
  defp maybe_preload_query(query, preloads), do: preload(query, ^preloads)

  @spec get_branch(binary()) :: {:ok, Branch.t()} | {:error, :not_found}
  def get_branch(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case Cachex.get(:branch_cache, id) do
      {:ok, nil} -> fetch_from_db_and_cache(id, opts)
      {:ok, %Branch{} = branch} -> ensure_preloaded_and_cached(branch, preloads, id, opts)
      _ -> {:error, :not_found}
    end
  end

  @spec get_branch_by_slug(binary(), keyword()) :: {:ok, Branch.t()} | {:error, :not_found}
  def get_branch_by_slug(slug, opts \\ []) do
    slug_cache_key = "slug:#{slug}"

    case Cachex.get(:branch_cache, slug_cache_key) do
      {:ok, branch_id} when is_binary(branch_id) ->
        get_branch(branch_id, opts)

      _ ->
        query = from(b in Branch, where: b.slug == ^slug and is_nil(b.deleted_at), select: b.id)

        case Repo.one(query) do
          nil ->
            {:error, :not_found}

          branch_id ->
            Cachex.put(:branch_cache, slug_cache_key, branch_id, ttl: :timer.hours(24))

            get_branch(branch_id, opts)
        end
    end
  end

  def update_branch(staff, %Branch{} = branch, branch_attrs, info_attrs) do
    staff
    |> do_update_branch(
      "branches.update",
      branch,
      branch_attrs,
      Map.drop(info_attrs, @own_settings)
    )
    |> Audit.track(staff, "branch.updated")
  end

  def update_integrations(staff, %Branch{} = branch, info_attrs) do
    staff
    |> do_update_branch("integrations.update", branch, %{}, Map.take(info_attrs, @integrations))
    |> Audit.track(staff, "branch.updated")
  end

  def get_branch_by_board_token(token) when is_binary(token) and token != "" do
    Branch
    |> join(:inner, [b], i in assoc(b, :info))
    |> where([b, i], i.board_token == ^token and is_nil(b.deleted_at))
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      branch -> {:ok, branch}
    end
  end

  def get_branch_by_board_token(_token), do: {:error, :not_found}

  def reset_board_token(staff, %Branch{} = branch) do
    staff
    |> do_reset_board_token(branch)
    |> Audit.track(staff, "branch.updated")
  end

  defp do_reset_board_token(staff, branch) do
    with :ok <- Identity.authorize(staff, "branches.update", branch.id) do
      branch = Repo.preload(branch, :info, force: true)

      (branch.info || Ecto.build_assoc(branch, :info))
      |> BranchInfo.board_token_changeset(new_board_token())
      |> Repo.insert_or_update()
      |> case do
        {:ok, info} -> {:ok, %{branch | info: info}}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp new_board_token, do: 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  def update_couriers(staff, %Branch{} = branch, attrs) do
    staff
    |> do_update_branch("delivery.update", branch, %{}, %{"couriers" => attrs})
    |> Audit.track(staff, "branch.updated")
  end

  defp do_update_branch(staff, permission, %Branch{} = branch, branch_attrs, info_attrs) do
    with :ok <- Identity.authorize(staff, permission, branch.id) do
      branch = Repo.preload(branch, :info)

      Ecto.Multi.new()
      |> Ecto.Multi.update(:branch, Branch.changeset(branch, branch_attrs))
      |> Ecto.Multi.run(:info, fn repo, _changes ->
        upsert_branch_info(repo, branch, info_attrs)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{branch: updated_branch, info: updates_info}} ->
          Cachex.clear(:branch_cache)
          {:ok, %{updated_branch | info: updates_info}}

        {:error, failed_operation, changeset, _changes} ->
          {:error, failed_operation, changeset}
      end
    end
  end

  defp upsert_branch_info(repo, branch, attrs) do
    if branch.info do
      branch.info
      |> BranchInfo.changeset(attrs)
      |> repo.update()
    else
      Ecto.build_assoc(branch, :info)
      |> BranchInfo.changeset(attrs)
      |> repo.insert()
    end
  end

  def create_branch(staff, branch_attrs, info_attrs) do
    staff
    |> do_create_branch(branch_attrs, info_attrs)
    |> Audit.track(staff, "branch.created")
  end

  defp do_create_branch(staff, branch_attrs, info_attrs) do
    if Identity.can?(staff, "branches.create") do
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:branch, Branch.changeset(%Branch{}, with_code(branch_attrs)))
      |> Ecto.Multi.insert(:branch_info, fn %{branch: branch} ->
        branch
        |> Ecto.build_assoc(:info)
        |> BranchInfo.changeset(info_attrs)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{branch: branch, branch_info: branch_info}} ->
          {:ok, %{branch | info: branch_info}}

        {:error, failed_operation, changeset, _changes} ->
          {:error, failed_operation, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  defp with_code(attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    case attrs["code"] do
      code when is_binary(code) and code != "" -> attrs
      _blank -> Map.put(attrs, "code", free_code(attrs["slug"] || attrs["name"]))
    end
  end

  defp free_code(text) do
    base = text |> Branch.code_from() |> String.pad_trailing(2, "0")

    [base | Enum.map(2..99, &(String.slice(base, 0, 4) <> Integer.to_string(&1)))]
    |> Enum.find(base, &(not Repo.exists?(from(b in Branch, where: b.code == ^&1))))
  end

  @spec soft_delete_branch(Delivest.Identity.Staff.t(), Branch.t()) ::
          {:ok, Branch.t()}
          | {:error, atom(), Ecto.Changeset.t() | term(), map()}
          | {:error, :forbidden}
  def soft_delete_branch(staff, %Branch{} = branch) do
    staff
    |> do_soft_delete_branch(branch)
    |> Audit.track(staff, "branch.deleted")
  end

  defp do_soft_delete_branch(staff, %Branch{} = branch) do
    if Identity.authorize(staff, "branches.delete", branch.id) == :ok do
      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(
        :delete_staff_branches,
        from(sb in "staff_branches", where: sb.branch_id == type(^branch.id, :binary_id))
      )
      |> Ecto.Multi.update(
        :soft_delete_branch,
        Ecto.Changeset.change(branch, %{deleted_at: DateTime.utc_now(:second)})
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{soft_delete_branch: deleted_branch}} ->
          Cachex.del(:branch_cache, deleted_branch.id)
          Cachex.del(:branch_cache, "slug:#{deleted_branch.slug}")

          {:ok, deleted_branch}

        {:error, failed_operation, reason, changes} ->
          {:error, failed_operation, reason, changes}
      end
    else
      {:error, :forbidden}
    end
  end

  defp ensure_preloaded_and_cached(branch, preloads, id, opts) do
    if needs_preload?(branch, preloads) do
      branch = maybe_preload_branch(branch, opts)
      cache_branch(id, branch)
      {:ok, branch}
    else
      {:ok, branch}
    end
  end

  defp needs_preload?(branch, preloads) do
    preloads
    |> List.wrap()
    |> Enum.any?(fn
      {assoc, _nested} -> match?(%Ecto.Association.NotLoaded{}, Map.get(branch, assoc))
      assoc -> match?(%Ecto.Association.NotLoaded{}, Map.get(branch, assoc))
    end)
  end

  defp maybe_preload_branch(branch, opts) do
    case Keyword.get(opts, :preload) do
      nil -> branch
      preloads -> Repo.preload(branch, preloads)
    end
  end

  defp fetch_from_db_and_cache(id, opts) do
    case fetch_not_deleted(id) do
      nil ->
        {:error, :not_found}

      branch ->
        branch = maybe_preload_branch(branch, opts)
        cache_branch(id, branch)
        {:ok, branch}
    end
  end

  defp fetch_not_deleted(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.one(from(b in Branch, where: b.id == ^uuid and is_nil(b.deleted_at)))
      :error -> nil
    end
  end

  @spec cache_branch(integer(), Branch.t()) ::
          {:commit, true} | {:commit, false} | {:error, term()}
  defp cache_branch(id, branch) do
    Cachex.put(:branch_cache, id, branch, ttl: :timer.hours(1))
  end
end
