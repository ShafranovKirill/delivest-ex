defmodule Delivest.Segments do
  @moduledoc "Staff-facing segment operations. Every entry point checks the feature and domain scope."
  import Ecto.Query

  alias Delivest.{Audit, Background, Features, Identity, Repo}
  alias Delivest.Features.Gate
  alias Delivest.Identity.{Branch, Client, Staff}
  alias Delivest.Oms.Order
  alias Delivest.Segments.Segment

  @page_size 50
  @client_page_size 20

  @doc "Pin a published dynamic snapshot while an internal bounded consumer scans it. Caller owns transaction."
  def lease_snapshot(%Segment{} = segment, owner_type, owner_id)
      when is_binary(owner_type) and is_binary(owner_id) do
    current = Repo.one(from s in Segment, where: s.id == ^segment.id, lock: "FOR SHARE")

    if current && (current.kind == :manual or current.published_snapshot_id) do
      if current.kind == :dynamic do
        Repo.insert_all(
          "segment_snapshot_leases",
          [
            %{
              snapshot_id: Ecto.UUID.dump!(current.published_snapshot_id),
              owner_type: owner_type,
              owner_id: Ecto.UUID.dump!(owner_id),
              inserted_at: DateTime.utc_now(:second)
            }
          ],
          on_conflict: {:replace, [:snapshot_id, :inserted_at]},
          conflict_target: [:owner_type, :owner_id]
        )
      end

      {:ok, current.published_snapshot_id}
    else
      {:error, :snapshot_unavailable}
    end
  end

  def release_snapshot(owner_type, owner_id) do
    Repo.delete_all(
      from l in "segment_snapshot_leases",
        where: l.owner_type == ^owner_type and l.owner_id == type(^owner_id, :binary_id)
    )

    :ok
  end

  @doc "Published membership for internal consumers; never builds an ad hoc segment snapshot."
  def published_member_page(%Segment{} = segment, after_id, limit, snapshot_id \\ nil)
      when is_integer(limit) and limit > 0 and limit <= 250 do
    snapshot_id = snapshot_id || segment.published_snapshot_id

    membership =
      if segment.kind == :manual do
        from m in "segment_manual_members",
          where: m.segment_id == type(^segment.id, :binary_id),
          select: m.client_id
      else
        from m in "segment_dynamic_members",
          where:
            m.segment_id == type(^segment.id, :binary_id) and
              m.snapshot_id == type(^snapshot_id, :binary_id),
          select: m.client_id
      end

    Repo.all(
      from c in Client,
        where:
          c.id in subquery(membership) and c.id > ^after_id and
            c.status == :active and is_nil(c.deleted_at),
        order_by: [asc: c.id],
        limit: ^limit,
        select: c.id
    )
  end

  def published_member?(%Segment{} = segment, client_id) do
    if segment.kind == :manual do
      Repo.exists?(
        from m in "segment_manual_members",
          where:
            m.segment_id == type(^segment.id, :binary_id) and
              m.client_id == type(^client_id, :binary_id)
      )
    else
      segment.published_snapshot_id != nil and
        Repo.exists?(
          from m in "segment_dynamic_members",
            where:
              m.segment_id == type(^segment.id, :binary_id) and
                m.snapshot_id == type(^segment.published_snapshot_id, :binary_id) and
                m.client_id == type(^client_id, :binary_id)
        )
    end
  end

  def available?(%Staff{} = staff) do
    Identity.can?(staff, "segments.read") and Features.enabled?("segments", :franchise) and
      (Identity.can?(staff, "segments.network") or
         Repo.exists?(
           from sb in "staff_branches",
             join: b in Branch,
             on: b.id == sb.branch_id,
             join: g in Gate,
             on:
               g.feature == "segments" and g.scope_key == fragment("'branch:' || ?::text", b.id),
             where:
               sb.staff_id == type(^staff.id, :binary_id) and
                 is_nil(b.deleted_at) and g.enabled
         ))
  end

  def available?(_), do: false

  def list(%Staff{} = staff, opts \\ []) do
    with :ok <- authorize(staff, "segments.read"),
         true <- available?(staff),
         {:ok, after_id} <- cursor(Keyword.get(opts, :after)),
         {:ok, limit} <- limit(Keyword.get(opts, :limit, @page_size)) do
      allowed = allowed_branch_ids(staff)
      allowed_raw = Enum.map(allowed, &Ecto.UUID.dump!/1)

      branch_links =
        from sb in "segment_branches",
          where: sb.segment_id == parent_as(:segment).id,
          select: 1

      hidden_links =
        from sb in "segment_branches",
          left_join: g in Gate,
          on:
            g.feature == "segments" and
              g.scope_key == fragment("'branch:' || ?::text", sb.branch_id),
          where: sb.segment_id == parent_as(:segment).id,
          where: sb.branch_id not in ^allowed_raw or is_nil(g.feature) or g.enabled == false,
          select: 1

      Segment
      |> from(as: :segment)
      |> preload(:branches)
      |> where([s], s.id > ^after_id)
      |> where(
        [s],
        (s.scope == :franchise and ^Identity.can?(staff, "segments.network")) or
          (s.scope == :branches and exists(branch_links) and not exists(hidden_links))
      )
      |> order_by([s], asc: s.id)
      |> limit(^limit)
      |> Repo.all()
      |> then(&{:ok, &1})
    else
      false -> {:error, :disabled}
      error -> error
    end
  end

  def get(%Staff{} = staff, id) do
    with :ok <- authorize(staff, "segments.read"),
         true <- available?(staff),
         {:ok, id} <- uuid(id),
         %Segment{} = segment <- Repo.get(Segment, id) |> Repo.preload(:branches),
         true <- visible?(staff, segment, allowed_branch_ids(staff)) do
      {:ok, segment}
    else
      _ -> {:error, :not_found}
    end
  end

  def recalculate_now(%Staff{} = staff, id) do
    with :ok <- authorize(staff, "segments.manage"),
         {:ok, %Segment{kind: :dynamic}} <- get(staff, id),
         {:ok, _} <- Background.run_now("segments.refresh", :franchise) do
      calculation_status(staff, id)
    else
      {:ok, _} -> {:error, :not_dynamic}
      error -> error
    end
  end

  def calculation_status(%Staff{} = staff, id) do
    with {:ok, %Segment{kind: :dynamic}} <- get(staff, id) do
      Background.calculation_status("segments.refresh", :franchise)
    else
      {:ok, _} -> {:error, :not_dynamic}
      error -> error
    end
  end

  def create(%Staff{} = staff, attrs, branch_ids \\ [], client_ids \\ [])
      when is_map(attrs) and is_list(branch_ids) and is_list(client_ids) do
    with :ok <- authorize(staff, "segments.manage"),
         {:ok, token} <- Features.snapshot("segments", :franchise),
         {:ok, ids} <- validate_scope(staff, attrs, branch_ids),
         {:ok, initial_ids} <- validate_initial_ids(attrs, client_ids),
         {:ok, branches} <- fetch_branches(ids) do
      changeset =
        %Segment{}
        |> Segment.create_changeset(attrs)
        |> Ecto.Changeset.put_assoc(:branches, branches)

      case Features.with_enabled("segments", :franchise, token, fn ->
             if not initial_ids_eligible?(attrs, ids, initial_ids),
               do: Repo.rollback(:invalid_members)

             case Repo.insert(changeset) do
               {:ok, segment} = result ->
                 if initial_ids != [] do
                   now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

                   Repo.insert_all(
                     "segment_manual_members",
                     Enum.map(initial_ids, fn client_id ->
                       %{
                         segment_id: Ecto.UUID.dump!(segment.id),
                         client_id: Ecto.UUID.dump!(client_id),
                         inserted_at: now,
                         updated_at: now
                       }
                     end)
                   )
                 end

                 {:ok, _} =
                   Audit.record(staff, "segment.created", :franchise,
                     metadata: %{
                       segment_id: segment.id,
                       scope: segment.scope,
                       branch_ids: ids,
                       kind: segment.kind,
                       rules: segment.rules,
                       revision: segment.revision,
                       initial_member_count: length(initial_ids)
                     }
                   )

                 result

               error ->
                 error
             end
           end) do
        {:ok, result} -> result
        error -> error
      end
    end
  end

  def update(%Staff{} = staff, id, attrs) when is_map(attrs) do
    with :ok <- authorize(staff, "segments.manage"),
         {:ok, token} <- Features.snapshot("segments", :franchise),
         {:ok, segment} <- get(staff, id) do
      expected = Map.get(attrs, "expected_revision", Map.get(attrs, :expected_revision))

      if expected != segment.revision and expected != Integer.to_string(segment.revision) do
        {:error, :stale}
      else
        case Features.with_enabled("segments", :franchise, token, fn ->
               current =
                 Repo.one(from s in Segment, where: s.id == ^segment.id, lock: "FOR UPDATE")

               if is_nil(current) or current.revision != segment.revision,
                 do: Repo.rollback(:stale)

               require_policy_confirmation!(current, attrs)

               case segment
                    |> Segment.update_changeset(attrs)
                    |> Repo.update(stale_error_field: :name) do
                 {:ok, updated} = result ->
                   {:ok, _} =
                     Audit.record(staff, "segment.updated", :franchise,
                       metadata: %{
                         segment_id: segment.id,
                         revision_before: segment.revision,
                         revision_after: updated.revision,
                         rules_before: segment.rules,
                         rules_after: updated.rules
                       }
                     )

                   result

                 error ->
                   error
               end
             end) do
          {:ok, result} -> result
          error -> error
        end
      end
    end
  end

  def add_member(%Staff{} = staff, segment_id, client_id, opts \\ %{}),
    do: change_member(staff, segment_id, client_id, :add, opts)

  def remove_member(%Staff{} = staff, segment_id, client_id, opts \\ %{}),
    do: change_member(staff, segment_id, client_id, :remove, opts)

  def list_members(%Staff{} = staff, segment_id, opts \\ []) do
    with {:ok, segment} <- get(staff, segment_id),
         {:ok, after_id} <- cursor(Keyword.get(opts, :after)),
         {:ok, limit} <- limit(Keyword.get(opts, :limit, @page_size)) do
      if segment.kind == :dynamic and is_nil(segment.published_snapshot_id) do
        {:ok, []}
      else
        membership_query =
          if segment.kind == :manual do
            from m in "segment_manual_members",
              where: m.segment_id == type(^segment.id, :binary_id),
              select: m.client_id
          else
            from m in "segment_dynamic_members",
              where:
                m.segment_id == type(^segment.id, :binary_id) and
                  m.snapshot_id == type(^segment.published_snapshot_id, :binary_id),
              select: m.client_id
          end

        query =
          from c in Client,
            where:
              c.id in subquery(membership_query) and c.id > ^after_id and
                c.status == :active and is_nil(c.deleted_at),
            order_by: [asc: c.id],
            limit: ^limit

        query =
          if segment.scope == :branches do
            ids = Enum.map(segment.branches, & &1.id)

            where(
              query,
              [c],
              c.id in subquery(
                from o in Order,
                  where: o.branch_id in ^ids and is_nil(o.deleted_at),
                  select: o.client_id
              )
            )
          else
            query
          end

        clients = Repo.all(query)

        {:ok, clients}
      end
    end
  end

  @doc "A fixed-size, searchable page for the staff segment's Clients tab."
  def paginated_clients(%Staff{} = staff, segment_id, params \\ %{}) when is_map(params) do
    mode = Map.get(params, "mode", "members")

    search =
      case Map.get(params, "search", "") do
        nil -> ""
        value when is_binary(value) -> String.trim(value)
        _ -> :invalid
      end

    with {:ok, segment} <- get(staff, segment_id),
         :ok <- authorize_client_page(staff, segment, mode),
         true <- is_binary(search) and String.length(search) <= 100 do
      sort = if Map.get(params, "sort") in ["name", "phone"], do: params["sort"], else: "name"
      direction = if params["direction"] == "desc", do: "desc", else: "asc"
      query = client_page_query(segment, mode, search)
      total_count = Repo.aggregate(query, :count, :id)
      total_pages = max(1, div(total_count + @client_page_size - 1, @client_page_size))
      page = params |> Map.get("page") |> client_page_number() |> min(total_pages)
      sort_field = if sort == "phone", do: :phone, else: :name
      sort_direction = if direction == "desc", do: :desc_nulls_last, else: :asc_nulls_last
      offset_count = (page - 1) * @client_page_size

      clients =
        query
        |> order_by([c], [{^sort_direction, field(c, ^sort_field)}, asc: c.id])
        |> limit(^@client_page_size)
        |> offset(^offset_count)
        |> Repo.all()

      {:ok,
       %{
         clients: clients,
         page: page,
         page_size: @client_page_size,
         total_pages: total_pages,
         total_count: total_count,
         sort: sort,
         direction: direction,
         search: search,
         mode: mode
       }}
    else
      false -> {:error, :invalid_search}
      error -> error
    end
  end

  defp authorize_client_page(_staff, _segment, "members"), do: :ok

  defp authorize_client_page(staff, %Segment{kind: :manual}, "available"),
    do: authorize(staff, "segments.manage")

  defp authorize_client_page(_staff, _segment, _mode), do: {:error, :forbidden}

  defp client_page_query(
         %Segment{kind: :dynamic, published_snapshot_id: nil} = segment,
         "members",
         search
       ),
       do: segment |> client_page_base_query(search) |> where([c], false)

  defp client_page_query(segment, mode, search) do
    membership_query =
      if segment.kind == :manual do
        from m in "segment_manual_members",
          where: m.segment_id == type(^segment.id, :binary_id),
          select: m.client_id
      else
        from m in "segment_dynamic_members",
          where:
            m.segment_id == type(^segment.id, :binary_id) and
              m.snapshot_id == type(^segment.published_snapshot_id, :binary_id),
          select: m.client_id
      end

    query = client_page_base_query(segment, search)

    case mode do
      "members" -> where(query, [c], c.id in subquery(membership_query))
      "available" -> where(query, [c], c.id not in subquery(membership_query))
    end
  end

  defp client_page_base_query(segment, search) do
    query =
      from c in Client,
        as: :client,
        where: c.status == :active and is_nil(c.deleted_at)

    query =
      if segment.scope == :branches do
        branch_ids = Enum.map(segment.branches, & &1.id)

        where(
          query,
          [c],
          exists(
            from o in Order,
              where:
                o.client_id == parent_as(:client).id and o.branch_id in ^branch_ids and
                  is_nil(o.deleted_at)
          )
        )
      else
        query
      end

    if search == "" do
      query
    else
      escaped =
        search
        |> String.replace("\\", "\\\\")
        |> String.replace("%", "\\%")
        |> String.replace("_", "\\_")

      where(query, [c], ilike(c.name, ^"%#{escaped}%") or ilike(c.phone, ^"%#{escaped}%"))
    end
  end

  defp client_page_number(page) when is_integer(page) and page > 0, do: page

  defp client_page_number(page) when is_binary(page) do
    case Integer.parse(page) do
      {number, ""} when number > 0 -> number
      _ -> 1
    end
  end

  defp client_page_number(_), do: 1

  def search_eligible_clients(%Staff{} = staff, segment_id, term, opts \\ [])
      when is_binary(term) do
    with true <- String.length(String.trim(term)) >= 2 and String.length(term) <= 100,
         {:ok, segment} <- get(staff, segment_id),
         {:ok, limit} <- limit(Keyword.get(opts, :limit, 20)) do
      {:ok,
       search_query(term, segment.scope, Enum.map(segment.branches, & &1.id), limit) |> Repo.all()}
    else
      false -> {:error, :invalid_search}
      error -> error
    end
  end

  def search_candidates(%Staff{} = staff, attrs, branch_ids, term)
      when is_map(attrs) and is_list(branch_ids) and is_binary(term) do
    with :ok <- authorize(staff, "segments.manage"),
         :ok <- feature_on?(),
         true <- String.length(String.trim(term)) >= 2 and String.length(term) <= 100,
         {:ok, ids} <- validate_scope(staff, attrs, branch_ids) do
      scope = Map.get(attrs, "scope", Map.get(attrs, :scope))
      {:ok, search_query(term, scope, ids, 20) |> Repo.all()}
    else
      false -> {:error, :invalid_search}
      error -> error
    end
  end

  defp search_query(term, scope, ids, limit) do
    escaped =
      term
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    query =
      from c in Client,
        as: :client,
        where: c.status == :active and is_nil(c.deleted_at),
        where: ilike(c.name, ^"%#{escaped}%") or ilike(c.phone, ^"%#{escaped}%"),
        order_by: [asc: c.id],
        limit: ^limit

    if scope in [:branches, "branches"] do
      where(
        query,
        [c],
        exists(
          from o in Order,
            where:
              o.client_id == parent_as(:client).id and o.branch_id in ^ids and
                is_nil(o.deleted_at)
        )
      )
    else
      query
    end
  end

  defp change_member(staff, segment_id, client_id, action, opts) do
    with :ok <- authorize(staff, "segments.manage"),
         {:ok, token} <- Features.snapshot("segments", :franchise),
         {:ok, segment} <- get(staff, segment_id),
         true <- segment.kind == :manual,
         {:ok, client_id} <- uuid(client_id),
         %Client{status: :active, deleted_at: nil} <- Repo.get(Client, client_id),
         true <- eligible?(segment, client_id) do
      result =
        Features.with_enabled("segments", :franchise, token, fn ->
          current = Repo.one!(from s in Segment, where: s.id == ^segment.id, lock: "FOR UPDATE")

          expected = Map.get(opts, "expected_revision", Map.get(opts, :expected_revision))

          if expected && expected != current.revision &&
               expected != Integer.to_string(current.revision),
             do: Repo.rollback(:stale)

          member? =
            Repo.exists?(
              from m in "segment_manual_members",
                where:
                  m.segment_id == type(^segment.id, :binary_id) and
                    m.client_id == type(^client_id, :binary_id)
            )

          changes? = (action == :add and not member?) or (action == :remove and member?)

          if changes?, do: require_policy_confirmation!(current, opts)

          outcome =
            case {action, changes?} do
              {:add, true} ->
                now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

                Repo.insert_all(
                  "segment_manual_members",
                  [
                    %{
                      segment_id: Ecto.UUID.dump!(segment.id),
                      client_id: Ecto.UUID.dump!(client_id),
                      inserted_at: now,
                      updated_at: now
                    }
                  ],
                  on_conflict: :nothing
                )

              {:remove, true} ->
                Repo.delete_all(
                  from m in "segment_manual_members",
                    where:
                      m.segment_id == type(^segment.id, :binary_id) and
                        m.client_id == type(^client_id, :binary_id)
                )

              {_, false} ->
                {0, nil}
            end

          if elem(outcome, 0) > 0 do
            Repo.update_all(from(s in Segment, where: s.id == ^segment.id),
              inc: [revision: 1]
            )
          end

          if changes? do
            {:ok, _} =
              Audit.record(staff, "segment.member_#{action}", :franchise,
                metadata: %{
                  segment_id: segment.id,
                  client_id: client_id,
                  scope: segment.scope,
                  branch_ids: Enum.map(segment.branches, & &1.id)
                }
              )
          end

          outcome
        end)

      case result do
        {:ok, _} -> :ok
        error -> error
      end
    else
      _ -> {:error, :forbidden}
    end
  end

  defp require_policy_confirmation!(segment, attrs) do
    impact = Delivest.Marketing.segment_impact(segment.id)
    confirmed = Map.get(attrs, "policy_confirmation", Map.get(attrs, :policy_confirmation))
    expected = Map.get(attrs, "expected_revision", Map.get(attrs, :expected_revision))

    if impact.policies != [] and
         (confirmed != impact.fingerprint or
            (expected != segment.revision and expected != Integer.to_string(segment.revision))),
       do: Repo.rollback({:policy_confirmation_required, impact})
  end

  defp eligible?(%Segment{scope: :franchise}, _client_id), do: true

  defp eligible?(segment, client_id) do
    ids = Enum.map(segment.branches, & &1.id)

    Repo.exists?(
      from o in Order,
        where: o.client_id == ^client_id and o.branch_id in ^ids and is_nil(o.deleted_at)
    )
  end

  defp validate_initial_ids(attrs, client_ids) when length(client_ids) <= 100 do
    kind = Map.get(attrs, "kind", Map.get(attrs, :kind))

    if client_ids != [] and kind not in [:manual, "manual"],
      do: {:error, :invalid_members},
      else: canonical_ids(client_ids)
  end

  defp validate_initial_ids(_, _), do: {:error, :invalid_members}

  defp initial_ids_eligible?(_attrs, _branch_ids, []), do: true

  defp initial_ids_eligible?(attrs, branch_ids, client_ids) do
    scope = Map.get(attrs, "scope", Map.get(attrs, :scope))

    query =
      from c in Client,
        where: c.id in ^client_ids and c.status == :active and is_nil(c.deleted_at),
        select: c.id

    query =
      if scope in [:branches, "branches"] do
        where(
          query,
          [c],
          c.id in subquery(
            from o in Order,
              where: o.branch_id in ^branch_ids and is_nil(o.deleted_at),
              select: o.client_id
          )
        )
      else
        query
      end

    Repo.aggregate(query, :count) == length(client_ids)
  end

  defp validate_scope(staff, attrs, branch_ids) do
    scope = Map.get(attrs, "scope", Map.get(attrs, :scope))

    with {:ok, ids} <- canonical_ids(branch_ids) do
      cond do
        scope in ["franchise", :franchise] and ids == [] and
            Identity.can?(staff, "segments.network") ->
          {:ok, []}

        scope in ["branches", :branches] and ids != [] and
          Enum.all?(ids, &(&1 in allowed_branch_ids(staff))) and
            Enum.all?(ids, &Features.enabled?("segments", {:branch, &1})) ->
          {:ok, ids}

        true ->
          {:error, :forbidden}
      end
    end
  end

  defp fetch_branches([]), do: {:ok, []}

  defp fetch_branches(ids) do
    branches = Repo.all(from b in Branch, where: b.id in ^ids and is_nil(b.deleted_at))
    if length(branches) == length(ids), do: {:ok, branches}, else: {:error, :invalid_branches}
  end

  defp visible?(staff, %{scope: :franchise}, _allowed),
    do: Identity.can?(staff, "segments.network")

  defp visible?(_staff, segment, allowed) do
    ids = Enum.map(segment.branches, & &1.id)

    ids != [] and
      Enum.all?(ids, &(&1 in allowed and Features.enabled?("segments", {:branch, &1})))
  end

  defp allowed_branch_ids(staff) do
    if Identity.can?(staff, "admin") do
      Repo.all(from b in Branch, where: is_nil(b.deleted_at), select: b.id)
    else
      staff = Repo.preload(staff, :branches)
      Enum.map(staff.branches, & &1.id)
    end
  end

  defp authorize(staff, permission),
    do: if(Identity.can?(staff, permission), do: :ok, else: {:error, :forbidden})

  defp feature_on?,
    do: if(Features.enabled?("segments", :franchise), do: :ok, else: {:error, :disabled})

  defp uuid(id) when is_binary(id), do: Ecto.UUID.cast(id)
  defp uuid(_), do: {:error, :invalid_id}

  defp canonical_ids(ids) when length(ids) <= 100 do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case uuid(id) do
        {:ok, canonical} -> {:cont, {:ok, [canonical | acc]}}
        _ -> {:halt, {:error, :invalid_branches}}
      end
    end)
    |> case do
      {:ok, valid} -> {:ok, Enum.uniq(valid)}
      other -> other
    end
  end

  defp canonical_ids(_), do: {:error, :invalid_branches}

  defp cursor(nil), do: {:ok, "00000000-0000-0000-0000-000000000000"}
  defp cursor(id), do: uuid(id)
  defp limit(value) when is_integer(value) and value > 0 and value <= @page_size, do: {:ok, value}
  defp limit(_), do: {:error, :invalid_limit}
end
