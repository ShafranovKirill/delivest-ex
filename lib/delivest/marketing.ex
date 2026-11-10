defmodule Delivest.Marketing do
  @moduledoc "Persistent inactivity policies and their immutable reward issues."
  import Ecto.Query

  alias Delivest.{Background, Features, Identity, Loyalty, Notifications, Repo, Segments}
  alias Delivest.Identity.{Branch, Client, Staff}
  alias Delivest.Marketing.{Issue, Policy}
  alias Delivest.Oms.{Order, OrderTransition}
  alias Delivest.Promo.{Issuing, PromoCode, Promotion}
  alias Delivest.Segments.Segment

  def list(%Staff{} = staff, opts \\ []) do
    if Identity.can?(staff, "marketing.read") and
         Features.enabled?("marketing_policies", :franchise) do
      with {:ok, cursor} <- list_cursor(Keyword.get(opts, :after)),
           limit when is_integer(limit) and limit > 0 and limit <= 50 <-
             Keyword.get(opts, :limit, 50) do
        allowed =
          Repo.all(from b in Branch, where: is_nil(b.deleted_at), select: b.id)
          |> Enum.filter(
            &(Identity.authorize(staff, "marketing.read", &1) == :ok and
                Features.enabled?("marketing_policies", {:branch, &1}))
          )

        allowed_raw = Enum.map(allowed, &Ecto.UUID.dump!/1)

        links =
          from b in "marketing_policy_branches",
            where: b.policy_id == parent_as(:policy).id,
            select: 1

        hidden =
          from b in "marketing_policy_branches",
            where: b.policy_id == parent_as(:policy).id and b.branch_id not in ^allowed_raw,
            select: 1

        policies =
          Policy
          |> from(as: :policy)
          |> where([p], p.id > ^cursor)
          |> where(
            [p],
            (p.scope == :franchise and ^Identity.can?(staff, "marketing.network")) or
              (p.scope == :branches and exists(links) and not exists(hidden))
          )
          |> order_by([p], asc: p.id)
          |> limit(^limit)
          |> preload(:branches)
          |> Repo.all()

        {:ok, policies}
      else
        _ -> {:error, :invalid_cursor}
      end
    else
      {:error, :forbidden}
    end
  end

  defp list_cursor(nil), do: {:ok, "00000000-0000-0000-0000-000000000000"}
  defp list_cursor(id), do: Ecto.UUID.cast(id)

  def segment_impact(segment_id) do
    policies =
      Repo.all(
        from p in Policy,
          where:
            p.status in [:active, :initializing, :paused] and
              (p.segment_id == ^segment_id or
                 p.id in subquery(
                   from e in "marketing_policy_excluded_segments",
                     where: e.segment_id == type(^segment_id, :binary_id),
                     select: e.policy_id
                 )),
          order_by: [asc: p.id],
          select: {p.id, p.name, p.revision, p.status}
      )

    fingerprint =
      policies
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{
      policies: Enum.map(policies, fn {id, name, _, _} -> %{id: id, name: name} end),
      fingerprint: fingerprint
    }
  end

  def get(%Staff{} = staff, id) do
    with true <-
           Identity.can?(staff, "marketing.read") and
             Features.enabled?("marketing_policies", :franchise),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         %Policy{} = policy <-
           Repo.get(Policy, uuid) |> Repo.preload([:branches, :segment, :promotion]),
         true <- visible?(staff, policy) do
      {:ok, policy}
    else
      _ -> {:error, :not_found}
    end
  end

  def exclusions(%Staff{} = staff, id) do
    with {:ok, policy} <- get(staff, id),
         {:ok, audience} <- Segments.get(staff, policy.segment_id) do
      client_ids =
        Repo.all(
          from e in "marketing_policy_excluded_clients",
            where: e.policy_id == type(^policy.id, :binary_id),
            order_by: e.client_id,
            select: type(e.client_id, :binary_id)
        )

      segment_ids =
        Repo.all(
          from e in "marketing_policy_excluded_segments",
            where: e.policy_id == type(^policy.id, :binary_id),
            order_by: e.segment_id,
            select: type(e.segment_id, :binary_id)
        )

      clients =
        client_exclusion_query(audience)
        |> where([c], c.id in ^client_ids)
        |> Repo.all()

      segments =
        segment_exclusion_query(staff, audience)
        |> where([s], s.id in ^segment_ids)
        |> Repo.all()

      {:ok,
       %{
         client_ids: client_ids,
         segment_ids: segment_ids,
         clients: clients,
         segments: segments
       }}
    end
  end

  def search_exclusion_segments(%Staff{} = staff, audience_id, term)
      when is_binary(term) and byte_size(term) <= 100 do
    with true <-
           Identity.can?(staff, "marketing.manage") and
             Features.enabled?("marketing_policies", :franchise) and
             String.length(String.trim(term)) >= 2,
         {:ok, audience} <- Segments.get(staff, audience_id) do
      escaped =
        term
        |> String.replace("\\", "\\\\")
        |> String.replace("%", "\\%")
        |> String.replace("_", "\\_")

      {:ok,
       segment_exclusion_query(staff, audience)
       |> where([s], ilike(s.name, ^"%#{escaped}%"))
       |> order_by([s], asc: s.name, asc: s.id)
       |> limit(20)
       |> Repo.all()}
    else
      _ -> {:error, :invalid_search}
    end
  end

  def search_exclusion_segments(_, _, _), do: {:error, :invalid_search}

  defp client_exclusion_query(audience) do
    query = from c in Client, as: :client, select: %{id: c.id, name: c.name, phone: c.phone}

    if audience.scope == :branches do
      ids = Enum.map(audience.branches, & &1.id)

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

  defp segment_exclusion_query(staff, audience) do
    query =
      from s in Segment,
        as: :segment,
        where: s.scope == ^audience.scope,
        select: %{id: s.id, name: s.name}

    if audience.scope == :branches do
      allowed =
        audience.branches
        |> Enum.map(& &1.id)
        |> Enum.filter(&Features.enabled?("segments", {:branch, &1}))
        |> Enum.map(&Ecto.UUID.dump!/1)

      links =
        from b in "segment_branches",
          where: b.segment_id == parent_as(:segment).id,
          select: 1

      hidden =
        from b in "segment_branches",
          where: b.segment_id == parent_as(:segment).id and b.branch_id not in ^allowed,
          select: 1

      where(query, [s], exists(links) and not exists(hidden))
    else
      if Identity.can?(staff, "segments.network"), do: query, else: where(query, [s], false)
    end
  end

  def create(
        %Staff{} = staff,
        attrs,
        branch_ids \\ [],
        excluded_client_ids \\ [],
        excluded_segment_ids \\ []
      ) do
    attrs = normalize_policy_attrs(attrs)

    with {:ok, token} <- Features.snapshot("marketing_policies", :franchise),
         {:ok, branches, segment} <- validate_policy(staff, attrs, branch_ids),
         {:ok, excludes} <-
           validate_exclusions(excluded_client_ids, excluded_segment_ids, segment) do
      policy =
        %Policy{} |> Policy.changeset(attrs) |> Ecto.Changeset.put_assoc(:branches, branches)

      case Features.with_enabled("marketing_policies", :franchise, token, fn ->
             case Repo.insert(policy) do
               {:ok, saved} ->
                 save_exclusions(saved.id, excludes)
                 audit(saved, staff.id, "created", %{})
                 saved

               {:error, changeset} ->
                 Repo.rollback(changeset)
             end
           end) do
        {:ok, saved} -> {:ok, saved}
        error -> error
      end
    end
  end

  def update(%Staff{} = staff, id, attrs, branch_ids, excluded_client_ids, excluded_segment_ids) do
    attrs = normalize_policy_attrs(attrs)

    with {:ok, current} <- get(staff, id),
         true <- current.status == :draft,
         true <- expected_revision?(current, attrs),
         {:ok, token} <- Features.snapshot("marketing_policies", :franchise),
         {:ok, branches, segment} <- validate_policy(staff, attrs, branch_ids),
         {:ok, excludes} <-
           validate_exclusions(excluded_client_ids, excluded_segment_ids, segment) do
      case Features.with_enabled("marketing_policies", :franchise, token, fn ->
             locked = Repo.one(from p in Policy, where: p.id == ^current.id, lock: "FOR UPDATE")

             if locked.revision != current.revision or locked.status != :draft,
               do: Repo.rollback(:stale)

             changeset =
               locked
               |> Repo.preload(:branches)
               |> Policy.changeset(attrs)
               |> Ecto.Changeset.put_assoc(:branches, branches)
               |> Ecto.Changeset.put_change(:revision, locked.revision + 1)

             case Repo.update(changeset) do
               {:ok, saved} ->
                 clear_exclusions(saved.id)
                 save_exclusions(saved.id, excludes)
                 audit(saved, staff.id, "updated", %{})
                 saved

               {:error, changeset} ->
                 Repo.rollback(changeset)
             end
           end) do
        {:ok, saved} -> {:ok, saved}
        error -> error
      end
    else
      false -> {:error, :stale}
      error -> error
    end
  end

  def preview(%Staff{} = staff, id) do
    with {:ok, policy} <- get(staff, id),
         true <- Identity.can?(staff, "marketing.manage"),
         :draft <- policy.status,
         {:ok, generation} <- Features.snapshot("marketing_policies", :franchise) do
      row =
        Repo.query!(
          "SELECT policy_revision, segment_revision, feature_generation, segment_snapshot_id, status, eligible_count, completed_at FROM marketing_previews WHERE policy_id=$1",
          [Ecto.UUID.dump!(policy.id)]
        ).rows

      current_snapshot =
        if(policy.segment.published_snapshot_id,
          do: Ecto.UUID.dump!(policy.segment.published_snapshot_id)
        )

      case row do
        [
          [
            revision,
            segment_revision,
            feature_generation,
            snapshot_raw,
            "ready",
            count,
            counted_at
          ]
        ]
        when revision == policy.revision and segment_revision == policy.segment.revision and
               snapshot_raw == current_snapshot and feature_generation == generation.franchise ->
          {:ok,
           %{
             status: :ready,
             eligible_clients: count,
             bonus_points: if(policy.bonus_amount, do: policy.bonus_amount * count),
             sms_cost: nil,
             reward_branch_id: policy.reward_branch_id,
             initial_mode: policy.initial_mode,
             attribution_days: policy.attribution_days,
             counted_at: counted_at
           }}

        [[revision, segment_revision, feature_generation, snapshot_raw, "pending", _, _]]
        when revision == policy.revision and segment_revision == policy.segment.revision and
               snapshot_raw == current_snapshot and feature_generation == generation.franchise ->
          {:ok, %{status: :pending}}

        _ ->
          now = DateTime.utc_now(:second)

          request =
            Features.with_enabled("marketing_policies", :franchise, generation, fn ->
              locked = Repo.one(from p in Policy, where: p.id == ^policy.id, lock: "FOR UPDATE")

              if locked == nil or locked.status != :draft or locked.revision != policy.revision,
                do: Repo.rollback(:stale)

              segment =
                Repo.one(from s in Segment, where: s.id == ^locked.segment_id, lock: "FOR SHARE")

              if segment == nil, do: Repo.rollback(:missing_segment)
              policy_raw = Ecto.UUID.dump!(locked.id)

              snapshot_raw =
                if(segment.published_snapshot_id,
                  do: Ecto.UUID.dump!(segment.published_snapshot_id)
                )

              existing =
                Repo.query!(
                  """
                  SELECT policy_revision, segment_revision, feature_generation, segment_snapshot_id, status
                    FROM marketing_previews WHERE policy_id=$1 FOR UPDATE
                  """,
                  [policy_raw]
                ).rows

              if existing == [
                   [
                     locked.revision,
                     segment.revision,
                     generation.franchise,
                     snapshot_raw,
                     "pending"
                   ]
                 ] or
                   existing == [
                     [
                       locked.revision,
                       segment.revision,
                       generation.franchise,
                       snapshot_raw,
                       "ready"
                     ]
                   ] do
                :existing
              else
                snapshot_id =
                  case Segments.lease_snapshot(segment, "marketing_preview", locked.id) do
                    {:ok, id} -> id
                    {:error, reason} -> Repo.rollback(reason)
                  end

                request_raw = Ecto.UUID.dump!(Ecto.UUID.generate())

                Repo.query!(
                  """
                  INSERT INTO marketing_previews (policy_id, request_id, policy_revision,
                    segment_revision, feature_generation, segment_snapshot_id,
                    status, eligible_count, requested_at)
                  VALUES ($1, $2, $3, $4, $5, $6, 'pending', 0, $7)
                  ON CONFLICT (policy_id) DO UPDATE SET request_id=EXCLUDED.request_id,
                    policy_revision=EXCLUDED.policy_revision,
                    segment_revision=EXCLUDED.segment_revision,
                    feature_generation=EXCLUDED.feature_generation,
                    segment_snapshot_id=EXCLUDED.segment_snapshot_id,
                    status='pending', cursor_client_id=NULL, eligible_count=0,
                    requested_at=EXCLUDED.requested_at, completed_at=NULL
                  """,
                  [
                    policy_raw,
                    request_raw,
                    locked.revision,
                    segment.revision,
                    generation.franchise,
                    if(snapshot_id, do: Ecto.UUID.dump!(snapshot_id)),
                    now
                  ]
                )

                :new
              end
            end)

          case request do
            {:ok, :new} ->
              Background.invalidate("marketing.preview", :franchise)
              Background.kick()
              {:ok, %{status: :pending}}

            {:ok, :existing} ->
              {:ok, %{status: :pending}}

            {:error, reason} ->
              {:error, reason}
          end
      end
    else
      false -> {:error, :forbidden}
      {:error, _} = error -> error
      _ -> {:error, :not_draft}
    end
  end

  def activate(%Staff{} = staff, id, expected_revision) do
    change_status(staff, id, :active, expected_revision)
  end

  def pause(%Staff{} = staff, id, expected_revision) do
    change_status(staff, id, :paused, expected_revision)
  end

  defp change_status(staff, id, status, expected_revision) do
    with {:ok, policy} <- get(staff, id),
         true <- Identity.can?(staff, "marketing.manage"),
         true <-
           expected_revision == policy.revision or
             expected_revision == Integer.to_string(policy.revision),
         true <- status == :paused or policy.status in [:draft, :paused],
         {:ok, token} <- Features.snapshot("marketing_policies", :franchise) do
      case Features.with_enabled("marketing_policies", :franchise, token, fn ->
             locked = Repo.one(from p in Policy, where: p.id == ^policy.id, lock: "FOR UPDATE")
             if locked.revision != policy.revision, do: Repo.rollback(:stale)
             now = DateTime.utc_now(:second)

             next_status =
               if status == :active and locked.initial_mode == :future_only and
                    not locked.baseline_complete,
                  do: :initializing,
                  else: status

             segment =
               Repo.one!(from s in Segment, where: s.id == ^locked.segment_id, lock: "FOR SHARE")

             preview_request_id =
               if status == :active and locked.status == :draft do
                 preview =
                   Repo.query!(
                     """
                     SELECT request_id FROM marketing_previews WHERE policy_id=$1 AND policy_revision=$2
                       AND segment_revision=$3 AND feature_generation=$4
                       AND segment_snapshot_id IS NOT DISTINCT FROM $5
                       AND status='ready'
                     """,
                     [
                       Ecto.UUID.dump!(locked.id),
                       locked.revision,
                       segment.revision,
                       token.franchise,
                       if(segment.published_snapshot_id,
                         do: Ecto.UUID.dump!(segment.published_snapshot_id)
                       )
                     ]
                   ).rows

                 if preview == [], do: Repo.rollback(:preview_required)
                 [[request_raw]] = preview
                 Ecto.UUID.load!(request_raw)
               else
                 nil
               end

             baseline_snapshot_id =
               if next_status == :initializing do
                 preview_request_id || locked.baseline_snapshot_id
               else
                 locked.baseline_snapshot_id
               end

             updated =
               Repo.update!(
                 Ecto.Changeset.change(locked,
                   status: next_status,
                   revision: locked.revision + 1,
                   activated_at: if(locked.activated_at, do: locked.activated_at, else: now),
                   baseline_snapshot_id: baseline_snapshot_id,
                   cursor_client_id:
                     if(locked.status == :draft, do: nil, else: locked.cursor_client_id)
                 )
               )

             audit(updated, staff.id, Atom.to_string(status), %{})
             updated
           end) do
        {:ok, updated} -> {:ok, updated}
        error -> error
      end
    else
      false -> {:error, :stale}
      error -> error
    end
  end

  @doc "A source is current only while its policy, scope, client and purchase cycle remain current."
  def notification_current?(source_id, client_id, phase) when phase in [:send, :show] do
    case Repo.get(Issue, source_id) do
      %Issue{client_id: ^client_id} = issue ->
        policy = Repo.get(Policy, issue.policy_id)
        now = DateTime.utc_now(:second)

        policy && policy.status == :active && DateTime.compare(now, issue.expires_at) == :lt &&
          Features.enabled?("marketing_policies", :franchise) &&
          Features.enabled?("marketing_policies", {:branch, issue.branch_id}) &&
          latest_cycle(client_id, branch_scope(policy)) == issue.cycle_order_id &&
          reward_current?(issue, policy, now)

      _ ->
        false
    end
  end

  def notification_current?(_, _, _), do: false

  @doc "Trusted scope and immutable feature epoch of a reward notification source."
  def notification_scope(source_id, client_id) do
    case Repo.get(Issue, source_id) do
      %Issue{client_id: ^client_id} = issue ->
        {:ok, {:branch, issue.branch_id},
         %{franchise: issue.source_generation_franchise, branch: issue.source_generation_branch}}

      _ ->
        :error
    end
  end

  @doc "Batch source currentness for the bounded client notice page."
  def notification_current_many?(source_ids, client_id, :show)
      when is_list(source_ids) and length(source_ids) <= 31 and is_binary(client_id) do
    now = DateTime.utc_now(:second)

    issues =
      Repo.all(
        from i in Issue,
          where: i.id in ^source_ids and i.client_id == ^client_id and i.expires_at > ^now
      )

    policies =
      issues
      |> Enum.map(& &1.policy_id)
      |> Enum.uniq()
      |> then(&Repo.all(from p in Policy, where: p.id in ^&1))
      |> Map.new(&{&1.id, &1})

    branch_ids = Repo.all(from b in Branch, where: is_nil(b.deleted_at), select: b.id)
    enabled = Features.enabled_branches("marketing_policies", branch_ids)
    policy_ids = Map.keys(policies)

    links =
      Repo.all(
        from b in "marketing_policy_branches",
          where: b.policy_id in type(^policy_ids, {:array, :binary_id}),
          select: {type(b.policy_id, :binary_id), type(b.branch_id, :binary_id)}
      )
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    valid_policy_ids =
      policy_ids
      |> Enum.filter(fn id ->
        policy = policies[id]

        policy.status == :active and
          (policy.scope == :franchise or
             (Map.get(links, id, []) != [] and
                Enum.all?(links[id], &MapSet.member?(enabled, &1))))
      end)

    cycles =
      if valid_policy_ids == [] or MapSet.size(enabled) == 0 or
           not Features.enabled?("marketing_policies", :franchise) do
        %{}
      else
        Repo.query!(
          """
          SELECT p.id, cycle.id FROM marketing_policies p
          JOIN LATERAL (
            SELECT o.id FROM orders o
            JOIN order_transitions t ON t.order_id=o.id
            WHERE o.client_id=$1 AND o.status='completed' AND o.deleted_at IS NULL
              AND t.to='completed' AND t.reverted_at IS NULL
              AND o.branch_id=ANY($2::uuid[])
              AND (p.scope='franchise' OR EXISTS (
                SELECT 1 FROM marketing_policy_branches pb
                WHERE pb.policy_id=p.id AND pb.branch_id=o.branch_id))
            ORDER BY t.inserted_at DESC, t.id DESC LIMIT 1
          ) cycle ON true WHERE p.id=ANY($3::uuid[])
          """,
          [
            Ecto.UUID.dump!(client_id),
            Enum.map(enabled, &Ecto.UUID.dump!/1),
            Enum.map(valid_policy_ids, &Ecto.UUID.dump!/1)
          ]
        ).rows
        |> Map.new(fn [policy_raw, order_raw] ->
          {Ecto.UUID.load!(policy_raw), Ecto.UUID.load!(order_raw)}
        end)
      end

    candidates =
      issues
      |> Enum.group_by(& &1.policy_id)
      |> Enum.flat_map(fn {policy_id, group} ->
        cycle_id = cycles[policy_id]

        if is_nil(cycle_id) do
          []
        else
          Enum.filter(group, fn issue ->
            issue.cycle_order_id == cycle_id and MapSet.member?(enabled, issue.branch_id) and
              (policies[policy_id].scope == :franchise or
                 issue.branch_id in Map.get(links, policy_id, []))
          end)
        end
      end)

    valid_rewards = current_reward_ids(candidates, policies, now)

    candidates
    |> Enum.filter(&MapSet.member?(valid_rewards, &1.id))
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  def notification_current_many?(_, _, _), do: MapSet.new()

  defp current_reward_ids(issues, policies, now) do
    bonus_ids = for issue <- issues, issue.reward_type == "bonus", do: issue.reward_id

    valid_bonus =
      Repo.all(
        from e in Delivest.Loyalty.Entry,
          where: e.id in ^bonus_ids and e.remaining > 0 and e.expires_at > ^now,
          select: e.id
      )
      |> MapSet.new()

    promo_ids = for issue <- issues, issue.reward_type == "promo", do: issue.reward_id
    codes = Repo.all(from c in PromoCode, where: c.id in ^promo_ids) |> Map.new(&{&1.id, &1})

    promotion_ids =
      issues
      |> Enum.map(& &1.policy_id)
      |> Enum.map(fn id -> policies[id] && policies[id].promotion_id end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    promotions =
      Repo.all(from p in Promotion, where: p.id in ^promotion_ids)
      |> Map.new(&{&1.id, &1})

    redemptions =
      Repo.all(
        from r in "promo_redemptions",
          where: r.promo_code_id in type(^promo_ids, {:array, :binary_id}),
          group_by: r.promo_code_id,
          select: {type(r.promo_code_id, :binary_id), count(r.id)}
      )
      |> Map.new()

    issues
    |> Enum.filter(fn issue ->
      case issue.reward_type do
        "bonus" ->
          MapSet.member?(valid_bonus, issue.reward_id)

        "promo" ->
          code = codes[issue.reward_id]
          policy = policies[issue.policy_id]
          promotion = policy && promotions[policy.promotion_id]

          code && code.client_id == issue.client_id && code.expires_at &&
            DateTime.compare(code.expires_at, now) == :gt &&
            promotion_live?(promotion, issue.branch_id, now) &&
            Map.get(redemptions, code.id, 0) < code.usage_limit

        _ ->
          false
      end
    end)
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  def issue(policy, client_id, context, now \\ DateTime.utc_now(:second))

  def issue(
        %Policy{} = policy,
        client_id,
        %{feature: "marketing_policies", scope: :franchise, generation: %{franchise: _}} = context,
        now
      ) do
    with true <- policy.status == :active,
         true <- eligible?(policy, client_id, now),
         {:ok, token} <-
           Features.snapshot("marketing_policies", {:branch, policy.reward_branch_id}),
         :ok <-
           if(token.franchise == context.generation.franchise,
             do: :ok,
             else: {:error, :disabled}
           ),
         {:ok, notifications_token} <-
           Features.snapshot("notifications", {:branch, policy.reward_branch_id}) do
      # Serialize with status completion on this client; do not hold this lock during provider I/O.
      case Background.publish(
             context,
             {:branch, policy.reward_branch_id},
             token,
             [{"notifications", {:branch, policy.reward_branch_id}, notifications_token}],
             fn ->
               client_lock(client_id)
               current = Repo.one(from p in Policy, where: p.id == ^policy.id, lock: "FOR UPDATE")

               if current.status != :active or current.revision != policy.revision,
                 do: Repo.rollback(:stale)

               cycle_id = latest_cycle(client_id, branch_scope(current))

               cond do
                 cycle_id == nil ->
                   :skipped

                 not eligible?(current, client_id, now) ->
                   :skipped

                 current.max_issues && current.issued_count >= current.max_issues ->
                   :skipped

                 Repo.exists?(
                   from i in Issue,
                     where:
                       i.policy_id == ^current.id and
                         i.client_id == ^client_id and i.cycle_order_id == ^cycle_id
                 ) ->
                   :skipped

                 true ->
                   issue_locked(current, client_id, cycle_id, now, token)
               end
             end
           ) do
        {:ok, result} -> {:ok, result}
        error -> error
      end
    else
      {:error, :disabled} -> {:error, :disabled}
      _ -> {:ok, :skipped}
    end
  end

  def issue(_, _, _, _), do: {:error, :disabled}

  def report(%Staff{} = staff, id, filters \\ %{}) do
    with {:ok, policy} <- get(staff, id),
         true <- Identity.can?(staff, "marketing.reports"),
         true <- report_branch_allowed?(staff, filters) do
      Delivest.Marketing.Report.request(policy, filters)
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  def compare_reports(staff, ids, filters \\ %{})

  def compare_reports(%Staff{} = staff, ids, filters)
      when is_list(ids) and length(ids) in 1..10 do
    with true <- Identity.can?(staff, "marketing.reports"),
         true <- report_branch_allowed?(staff, filters),
         true <- Enum.uniq(ids) == ids,
         results <- Enum.map(ids, &get(staff, &1)),
         true <- Enum.all?(results, &match?({:ok, _}, &1)) do
      Delivest.Marketing.Report.compare(
        Enum.map(results, fn {:ok, policy} -> policy end),
        filters
      )
    else
      _ -> {:error, :forbidden}
    end
  end

  def compare_reports(_, _, _), do: {:error, :forbidden}

  def available_promotions(staff, branch_id, search \\ "")

  def available_promotions(%Staff{} = staff, branch_id, search)
      when is_binary(search) and byte_size(search) <= 100 do
    with {:ok, branch_id} <- Ecto.UUID.cast(branch_id),
         :ok <- Identity.authorize(staff, "marketing.manage", branch_id),
         true <- Features.enabled?("marketing_policies", {:branch, branch_id}) do
      now = DateTime.utc_now(:second)

      query =
        from p in Promotion,
          where:
            p.branch_id == ^branch_id and p.kind == :personal_code and p.enabled and
              is_nil(p.deleted_at) and
              (is_nil(p.starts_at) or p.starts_at <= ^now) and
              (is_nil(p.ends_at) or p.ends_at > ^now),
          order_by: [asc: p.name, asc: p.id],
          limit: 50,
          select: {p.name, p.id}

      query =
        if search == "",
          do: query,
          else: where(query, [p], ilike(p.name, ^("%" <> search <> "%")))

      {:ok, Repo.all(query)}
    else
      _ -> {:error, :forbidden}
    end
  end

  def available_promotions(_, _, _), do: {:error, :forbidden}

  defp report_branch_allowed?(staff, filters) when is_map(filters) do
    case Map.get(filters, :branch_id, Map.get(filters, "branch_id")) do
      nil ->
        true

      "" ->
        true

      id ->
        Identity.authorize(staff, "marketing.reports", id) == :ok and
          Features.enabled?("marketing_policies", {:branch, id})
    end
  end

  defp report_branch_allowed?(_, _), do: false

  defp issue_locked(policy, client_id, cycle_id, now, token) do
    expires_at = DateTime.add(now, policy.reward_ttl_days, :day)
    until_at = DateTime.add(now, policy.attribution_days, :day)

    {inserted, rows} =
      Repo.insert_all(
        Issue,
        [
          %{
            id: Ecto.UUID.generate(),
            policy_id: policy.id,
            client_id: client_id,
            cycle_order_id: cycle_id,
            branch_id: policy.reward_branch_id,
            reward_type: if(policy.promotion_id, do: "promo", else: "bonus"),
            reward_amount: policy.bonus_amount,
            issued_at: now,
            expires_at: expires_at,
            attribution_until: until_at,
            policy_revision: policy.revision,
            source_generation_franchise: token.franchise,
            source_generation_branch: token.branch,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:policy_id, :client_id, :cycle_order_id],
        returning: true
      )

    if inserted != 1, do: Repo.rollback(:already_issued)
    [issue] = rows

    client = Repo.get!(Client, client_id)

    reward =
      if policy.promotion_id do
        promotion =
          Repo.one(
            from p in Promotion,
              where: p.id == ^policy.promotion_id,
              lock: "FOR SHARE"
          )

        if not promotion_live?(promotion, policy.reward_branch_id, now),
          do: Repo.rollback(:promotion_unavailable)

        Issuing.issue_system(promotion, client, expires_at)
      else
        Loyalty.grant_system(
          policy.reward_branch_id,
          client_id,
          policy.bonus_amount,
          expires_at,
          "marketing issue #{issue.id}"
        )
      end

    reward =
      case reward do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end

    Repo.update!(Ecto.Changeset.change(issue, reward_id: reward.id))

    Repo.update_all(from(p in Policy, where: p.id == ^policy.id),
      inc: [issued_count: 1],
      set: [last_error: nil]
    )

    cta =
      if policy.promotion_id,
        do: %{type: "apply_promo", value: reward.code},
        else: %{type: "show_bonus", value: Integer.to_string(policy.bonus_amount)}

    case Notifications.publish(
           client_id,
           %{title: policy.message_title, body: policy.message_body, cta: cta},
           idempotency_key: issue.id,
           source_type: "marketing_reward",
           source_id: issue.id,
           branch_id: policy.reward_branch_id,
           expires_at: expires_at,
           channels:
             Enum.map(policy.channels, fn
               "in_app" -> :in_app
               "push" -> :push
               "sms" -> :sms
             end)
         ) do
      {:ok, _} -> issue
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp eligible?(policy, client_id, now, candidate_member? \\ false) do
    segment = Repo.get(Segment, policy.segment_id)
    cycle = latest_order(client_id, branch_scope(policy))

    segment && (candidate_member? or Segments.published_member?(segment, client_id)) &&
      not excluded?(policy, client_id) && cycle &&
      DateTime.diff(now, cycle.completed_at, :second) >= policy.inactivity_days * 86_400 &&
      not suppressed?(policy.id, client_id, cycle.id) &&
      Features.enabled?("marketing_policies", {:branch, policy.reward_branch_id})
  end

  defp suppressed?(policy_id, client_id, cycle_id) do
    Repo.exists?(
      from s in "marketing_suppressions",
        where:
          s.policy_id == type(^policy_id, :binary_id) and
            s.client_id == type(^client_id, :binary_id) and
            s.cycle_order_id == type(^cycle_id, :binary_id)
    )
  end

  defp excluded?(policy, client_id) do
    direct =
      Repo.exists?(
        from e in "marketing_policy_excluded_clients",
          where:
            e.policy_id == type(^policy.id, :binary_id) and
              e.client_id == type(^client_id, :binary_id)
      )

    groups =
      Repo.all(
        from e in "marketing_policy_excluded_segments",
          where: e.policy_id == type(^policy.id, :binary_id),
          select: e.segment_id
      )

    direct or
      Enum.any?(groups, fn id ->
        case Repo.get(Segment, id) do
          nil -> false
          segment -> Segments.published_member?(segment, client_id)
        end
      end)
  end

  defp latest_cycle(client_id, branches) do
    case latest_order(client_id, branches) do
      nil -> nil
      order -> order.id
    end
  end

  defp latest_order(client_id, branches) do
    Repo.one(
      from o in Order,
        join: t in OrderTransition,
        on: t.order_id == o.id,
        where:
          o.client_id == ^client_id and o.status == :completed and is_nil(o.deleted_at) and
            t.to == :completed and is_nil(t.reverted_at) and o.branch_id in ^branches,
        order_by: [desc: t.inserted_at, desc: t.id],
        limit: 1,
        select: %{id: o.id, completed_at: t.inserted_at}
    )
  end

  defp branch_scope(policy) do
    case policy.scope do
      :branches ->
        ids =
          Repo.all(
            from b in "marketing_policy_branches",
              where: b.policy_id == type(^policy.id, :binary_id),
              select: type(b.branch_id, :binary_id)
          )

        if Enum.all?(ids, &Features.enabled?("marketing_policies", {:branch, &1})),
          do: ids,
          else: []

      :franchise ->
        Repo.all(from b in Branch, where: is_nil(b.deleted_at), select: b.id)
        |> Enum.filter(&Features.enabled?("marketing_policies", {:branch, &1}))
    end
  end

  defp visible?(staff, policy) do
    if policy.scope == :franchise do
      Identity.can?(staff, "marketing.network")
    else
      policy.branches != [] and
        Enum.all?(
          policy.branches,
          &(Identity.authorize(staff, "marketing.read", &1.id) == :ok and
              Features.enabled?("marketing_policies", {:branch, &1.id}))
        )
    end
  end

  defp validate_policy(staff, attrs, branch_ids) do
    scope = Map.get(attrs, "scope", Map.get(attrs, :scope))
    segment_id = Map.get(attrs, "segment_id", Map.get(attrs, :segment_id))
    reward_branch_id = Map.get(attrs, "reward_branch_id", Map.get(attrs, :reward_branch_id))
    promotion_id = Map.get(attrs, "promotion_id", Map.get(attrs, :promotion_id))
    bonus = Map.get(attrs, "bonus_amount", Map.get(attrs, :bonus_amount))

    with true <- Identity.can?(staff, "marketing.manage"),
         {:ok, segment_uuid} <- Ecto.UUID.cast(segment_id),
         %Segment{} = segment <- Repo.get(Segment, segment_uuid) |> Repo.preload(:branches),
         {:ok, reward_uuid} <- Ecto.UUID.cast(reward_branch_id),
         %Branch{deleted_at: nil} <- Repo.get(Branch, reward_uuid),
         :ok <- Identity.authorize(staff, "marketing.manage", reward_uuid),
         true <- Features.enabled?("marketing_policies", {:branch, reward_uuid}),
         {:ok, ids} <- canonical_ids(branch_ids),
         true <- valid_scope?(staff, scope, ids, segment, reward_uuid),
         :ok <- valid_reward(promotion_id, bonus, reward_uuid) do
      branches = Repo.all(from b in Branch, where: b.id in ^ids and is_nil(b.deleted_at))
      {:ok, branches, segment}
    else
      _ -> {:error, :invalid_policy_scope_or_reward}
    end
  end

  defp valid_scope?(staff, scope, ids, segment, reward_branch) do
    cond do
      scope in [:franchise, "franchise"] ->
        ids == [] and segment.scope == :franchise and
          Identity.can?(staff, "marketing.network")

      scope in [:branches, "branches"] ->
        ids != [] and reward_branch in ids and
          segment.scope == :branches and
          Enum.sort(ids) == Enum.sort(Enum.map(segment.branches, & &1.id)) and
          Enum.all?(
            ids,
            &(Features.enabled?("marketing_policies", {:branch, &1}) and
                Identity.authorize(staff, "marketing.manage", &1) == :ok)
          )

      true ->
        false
    end
  end

  defp valid_reward(nil, bonus, branch) when is_integer(bonus) and bonus > 0 do
    if Loyalty.enabled?(branch), do: :ok, else: {:error, :points_unavailable}
  end

  defp valid_reward(id, nil, branch) when is_binary(id) do
    case Repo.get(Promotion, id) do
      %Promotion{} = promotion ->
        if promotion_live?(promotion, branch, DateTime.utc_now(:second)),
          do: :ok,
          else: {:error, :invalid_promotion}

      _ ->
        {:error, :invalid_promotion}
    end
  end

  defp valid_reward(_, _, _), do: {:error, :invalid_reward}

  defp promotion_live?(%Promotion{} = promotion, branch, now) do
    promotion.kind == :personal_code and promotion.enabled and is_nil(promotion.deleted_at) and
      promotion.branch_id == branch and
      (is_nil(promotion.starts_at) or DateTime.compare(now, promotion.starts_at) != :lt) and
      (is_nil(promotion.ends_at) or DateTime.compare(now, promotion.ends_at) == :lt)
  end

  defp promotion_live?(_, _, _), do: false

  defp reward_current?(%Issue{reward_type: "bonus"} = issue, _policy, now) do
    Repo.exists?(
      from e in Delivest.Loyalty.Entry,
        where:
          e.id == ^issue.reward_id and e.client_id == ^issue.client_id and
            e.remaining > 0 and e.expires_at > ^now
    )
  end

  defp reward_current?(%Issue{reward_type: "promo"} = issue, policy, now) do
    code = Repo.get(PromoCode, issue.reward_id)
    promotion = Repo.get(Promotion, policy.promotion_id)

    code && code.client_id == issue.client_id && code.expires_at &&
      DateTime.compare(code.expires_at, now) == :gt &&
      promotion_live?(promotion, issue.branch_id, now) &&
      Repo.aggregate(
        from(r in "promo_redemptions",
          where: r.promo_code_id == type(^code.id, :binary_id)
        ),
        :count,
        :id
      ) < code.usage_limit
  end

  defp reward_current?(_, _, _), do: false

  defp validate_exclusions(client_ids, segment_ids, audience) do
    with {:ok, clients} <- canonical_ids(client_ids),
         {:ok, segments} <- canonical_ids(segment_ids),
         true <- Enum.all?(clients, &Repo.exists?(from c in Client, where: c.id == ^&1)),
         true <-
           Enum.all?(segments, fn id ->
             case Repo.get(Segment, id) do
               %Segment{scope: scope} when scope == audience.scope -> true
               _ -> false
             end
           end) do
      {:ok, {clients, segments}}
    else
      _ -> {:error, :invalid_exclusions}
    end
  end

  defp canonical_ids(ids) when is_list(ids) and length(ids) <= 1000 do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case Ecto.UUID.cast(id) do
        {:ok, uuid} -> {:cont, {:ok, [uuid | acc]}}
        _ -> {:halt, {:error, :invalid_id}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.uniq(values)}
      error -> error
    end
  end

  defp canonical_ids(_), do: {:error, :invalid_id}

  defp save_exclusions(policy_id, {clients, segments}) do
    for id <- clients,
        do:
          Repo.insert_all(
            "marketing_policy_excluded_clients",
            [%{policy_id: Ecto.UUID.dump!(policy_id), client_id: Ecto.UUID.dump!(id)}]
          )

    for id <- segments,
        do:
          Repo.insert_all(
            "marketing_policy_excluded_segments",
            [%{policy_id: Ecto.UUID.dump!(policy_id), segment_id: Ecto.UUID.dump!(id)}]
          )
  end

  defp clear_exclusions(policy_id) do
    Repo.delete_all(
      from e in "marketing_policy_excluded_clients",
        where: e.policy_id == type(^policy_id, :binary_id)
    )

    Repo.delete_all(
      from e in "marketing_policy_excluded_segments",
        where: e.policy_id == type(^policy_id, :binary_id)
    )
  end

  defp audit(policy, actor_id, action, details) do
    Repo.insert_all("marketing_policy_audits", [
      %{
        id: Ecto.UUID.dump!(Ecto.UUID.generate()),
        policy_id: Ecto.UUID.dump!(policy.id),
        actor_id: Ecto.UUID.dump!(actor_id),
        action: action,
        revision: policy.revision,
        details: details,
        inserted_at: DateTime.utc_now(:second)
      }
    ])
  end

  defp expected_revision?(policy, attrs) do
    expected = Map.get(attrs, "expected_revision", Map.get(attrs, :expected_revision))
    expected == policy.revision or expected == Integer.to_string(policy.revision)
  end

  defp normalize_policy_attrs(attrs) do
    atom_keys =
      for {key, value} <- attrs, is_atom(key), into: %{}, do: {Atom.to_string(key), value}

    string_keys = for {key, value} <- attrs, is_binary(key), into: %{}, do: {key, value}
    attrs = Map.merge(atom_keys, string_keys)
    amount = Map.get(attrs, "bonus_amount")

    amount =
      if is_binary(amount) and amount != "" do
        case Integer.parse(amount) do
          {number, ""} -> number
          _ -> amount
        end
      else
        amount
      end

    attrs
    |> Map.put("bonus_amount", if(amount == "", do: nil, else: amount))
    |> Map.update("promotion_id", nil, &if(&1 == "", do: nil, else: &1))
  end

  def preview_eligible?(%Policy{} = policy, client_id, now),
    do: eligible?(policy, client_id, now, true)

  @doc "Select candidate snapshot members with fixed-query batch reads; issuance rechecks under locks."
  def candidate_state(%Policy{} = policy, ids, now) when is_list(ids) and length(ids) <= 250 do
    branches = branch_scope(policy)

    if ids == [] or branches == [] or
         not Features.enabled?("marketing_policies", {:branch, policy.reward_branch_id}) do
      %{eligible_ids: [], eligible_cycles: [], excluded_cycles: []}
    else
      raw_ids = Enum.map(ids, &Ecto.UUID.dump!/1)
      policy_raw = Ecto.UUID.dump!(policy.id)

      excluded_raw =
        Repo.query!(
          """
          SELECT client_id FROM marketing_policy_excluded_clients
            WHERE policy_id=$1 AND client_id=ANY($2::uuid[])
          UNION
          SELECT m.client_id FROM marketing_policy_excluded_segments e
            JOIN segments s ON s.id=e.segment_id AND s.kind='manual'
            JOIN segment_manual_members m ON m.segment_id=s.id
            WHERE e.policy_id=$1 AND m.client_id=ANY($2::uuid[])
          UNION
          SELECT m.client_id FROM marketing_policy_excluded_segments e
            JOIN segments s ON s.id=e.segment_id AND s.kind='dynamic'
            JOIN segment_dynamic_members m ON m.segment_id=s.id
              AND m.snapshot_id=s.published_snapshot_id
            WHERE e.policy_id=$1 AND m.client_id=ANY($2::uuid[])
          """,
          [policy_raw, raw_ids]
        ).rows

      excluded =
        excluded_raw
        |> Enum.map(fn [raw] -> Ecto.UUID.load!(raw) end)
        |> MapSet.new()

      cycles =
        Repo.all(
          from o in Order,
            join: t in OrderTransition,
            on: t.order_id == o.id,
            where:
              o.client_id in ^ids and o.branch_id in ^branches and
                o.status == :completed and is_nil(o.deleted_at) and
                t.to == :completed and is_nil(t.reverted_at),
            distinct: o.client_id,
            order_by: [asc: o.client_id, desc: t.inserted_at, desc: t.id],
            select: {o.client_id, o.id, t.inserted_at}
        )
        |> Map.new(fn {client_id, order_id, completed_at} ->
          {client_id, {order_id, completed_at}}
        end)

      suppressed =
        Repo.query!(
          """
          SELECT client_id, cycle_order_id FROM marketing_suppressions
            WHERE policy_id=$1 AND client_id=ANY($2::uuid[])
          """,
          [policy_raw, raw_ids]
        ).rows
        |> MapSet.new(fn [client_raw, cycle_raw] ->
          {Ecto.UUID.load!(client_raw), Ecto.UUID.load!(cycle_raw)}
        end)

      excluded_cycles =
        for id <- ids,
            MapSet.member?(excluded, id),
            {cycle_id, _} <- [cycles[id]],
            do: {id, cycle_id}

      eligible_ids =
        Enum.filter(ids, fn id ->
          case cycles[id] do
            {cycle_id, completed_at} ->
              not MapSet.member?(excluded, id) and
                DateTime.diff(now, completed_at, :second) >= policy.inactivity_days * 86_400 and
                not MapSet.member?(suppressed, {id, cycle_id})

            nil ->
              false
          end
        end)

      %{
        eligible_ids: eligible_ids,
        eligible_cycles: Enum.map(eligible_ids, fn id -> {id, elem(cycles[id], 0)} end),
        excluded_cycles: excluded_cycles
      }
    end
  end

  defp client_lock(client_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 17))", [
      "marketing-client:" <> client_id
    ])
  end

  @doc "Serialize a new completed order with an in-flight inactivity grant."
  def lock_completion(client_id, branch_id) when is_binary(client_id) do
    if Features.enabled?("marketing_policies", {:branch, branch_id}), do: client_lock(client_id)
    :ok
  end

  def lock_completion(_, _), do: :ok
end
