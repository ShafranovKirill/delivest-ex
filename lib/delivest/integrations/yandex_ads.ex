defmodule Delivest.Integrations.YandexAds do
  @moduledoc "Optional advertising integration; OMS remains the source of financial facts."
  import Ecto.Query
  alias Delivest.{Features, Repo}
  alias Delivest.Identity, as: Accounts

  alias Delivest.Integrations.YandexAds.{
    Settings,
    Identity,
    OrderReceipt,
    Conversion,
    ConversionWorker,
    Api,
    Cost,
    OAuth
  }

  @streams %{
    browser: {:browser_enabled, "yandex_browser"},
    conversions: {:conversions_enabled, "yandex_conversions"},
    ecommerce: {:ecommerce_enabled, "yandex_ecommerce"},
    feed: {:feed_enabled, "yandex_feed"},
    costs: {:costs_enabled, "yandex_costs"}
  }
  @identifiers ~w(client_id yclid campaign_id ad_id)

  def get_settings do
    Repo.get(Settings, 1) || %Settings{id: 1}
  rescue
    ArgumentError -> %Settings{id: 1, credential_error: true}
  end

  def change_settings(settings, attrs \\ %{}), do: Settings.changeset(settings, attrs)

  def update_settings(staff, attrs) do
    if Accounts.can?(staff, "admin") do
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended('yandex-ads-settings',0))")
        previous = get_settings()
        if previous.credential_error, do: Repo.rollback(:credentials_unavailable)
        changeset = Settings.changeset(previous, attrs)

        changeset =
          if Ecto.Changeset.changed?(changeset, :direct_token) or
               Ecto.Changeset.changed?(changeset, :client_login) do
            changeset
            |> Ecto.Changeset.put_change(:account_scope, Ecto.UUID.generate())
            |> Ecto.Changeset.put_change(:costs_refreshed_at, nil)
            |> Ecto.Changeset.put_change(:costs_from, nil)
            |> Ecto.Changeset.put_change(:costs_to, nil)
          else
            changeset
          end

        branch_ids = Ecto.Changeset.get_field(changeset, :branch_ids) || []

        known_ids =
          Repo.all(
            from(b in Delivest.Identity.Branch,
              where: b.id in ^branch_ids and is_nil(b.deleted_at) and b.is_active == true,
              select: b.id
            )
          )

        changeset =
          if Enum.sort(known_ids) == Enum.sort(branch_ids),
            do: changeset,
            else:
              Ecto.Changeset.add_error(changeset, :branch_ids, "contains unavailable branches")

        generation =
          if map_size(changeset.changes) == 0,
            do: previous.generation,
            else: previous.generation + 1

        case changeset
             |> Ecto.Changeset.put_change(:generation, generation)
             |> Repo.insert_or_update() do
          {:ok, settings} ->
            Repo.update_all(
              from(c in Conversion,
                where: c.generation != ^settings.generation and c.status in ["pending", "sending"]
              ),
              set: [status: "stale", reason: "connection_changed", updated_at: now()]
            )

            Delivest.Audit.record(staff, "integration.yandex_ads_updated", :franchise,
              metadata: %{generation: settings.generation}
            )

            settings

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
    else
      {:error, :forbidden}
    end
  end

  def enabled?(stream, branch_id), do: enabled?(get_settings(), stream, branch_id)

  def account_key(settings), do: settings.account_scope || "unconfigured"

  def feature_token(stream, branch_id) do
    {_flag, feature} = Map.fetch!(@streams, stream)

    case Features.snapshot(feature, {:branch, branch_id}) do
      {:ok, token} -> %{"franchise" => token.franchise, "branch" => token.branch}
      _ -> nil
    end
  end

  def valid_feature_token?(stream, branch_id, token) when is_map(token),
    do: feature_token(stream, branch_id) == token

  def valid_feature_token?(_, _, _), do: false

  def costs_token(settings) do
    for id <- settings.branch_ids,
        enabled?(settings, :costs, id),
        into: %{},
        do: {id, feature_token(:costs, id)}
  end

  def publication_requests(tokens) do
    for {id, token} <- tokens,
        do:
          {"yandex_costs", {:branch, id},
           %{franchise: token["franchise"], branch: token["branch"]}}
  end

  def enabled?(%Settings{} = settings, stream, branch_id) do
    case @streams[stream] do
      {flag, feature} ->
        settings.enabled and Map.get(settings, flag) == true and branch_id in settings.branch_ids and
          (stream in [:feed, :costs] or settings.privacy_approved) and
          Features.enabled?(feature, {:branch, branch_id})

      _ ->
        false
    end
  end

  def public_config(branch_id) do
    settings = get_settings()

    feature_version =
      {settings.generation,
       Enum.map([:browser, :conversions, :ecommerce], &feature_token(&1, branch_id))}
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    browser = enabled?(settings, :browser, branch_id)

    capture =
      browser or enabled?(settings, :conversions, branch_id) or
        enabled?(settings, :ecommerce, branch_id)

    %{
      enabled: browser,
      counter_id: if(browser, do: settings.counter_id),
      generation: settings.generation,
      feature_version: feature_version,
      ecommerce: browser and enabled?(settings, :ecommerce, branch_id),
      capture: capture,
      collection_basis: if(capture, do: "admin_approved", else: "disabled"),
      webvisor: false
    }
  end

  def capture_identity(branch_id, owner_key, attrs) when is_map(attrs) and is_binary(owner_key) do
    settings = get_settings()

    with true <- public_config(branch_id).capture,
         true <- attrs["generation"] == settings.generation,
         true <- attrs["feature_version"] == public_config(branch_id).feature_version,
         true <-
           Enum.all?(Map.keys(attrs), &(&1 in ["generation", "feature_version" | @identifiers])),
         true <- Enum.any?(@identifiers, &(not is_nil(attrs[&1]))),
         true <- Enum.all?(@identifiers, &valid_identifier?(&1, attrs[&1])) do
      Repo.transaction(fn ->
        lock_settings()

        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", [
          "yandex-owner:" <> owner_key
        ])

        if get_settings().generation != settings.generation or
             attrs["feature_version"] != public_config(branch_id).feature_version or
             not public_config(branch_id).capture,
           do: Repo.rollback(:disabled)

        timestamp = now()

        current =
          Repo.get_by(Identity,
            branch_id: branch_id,
            owner_key: owner_key,
            generation: settings.generation
          )

        values =
          Map.new(@identifiers, &{String.to_existing_atom(&1), attrs[&1]})
          |> Map.reject(fn {_, value} -> is_nil(value) end)

        current =
          current ||
            %Identity{
              branch_id: branch_id,
              owner_key: owner_key,
              generation: settings.generation,
              captured_at: timestamp
            }

        # A new click replaces the previous click fields, while a ClientID refresh
        # alone never resets its attribution time or campaign.
        values =
          if attrs["yclid"] && attrs["yclid"] != current.yclid,
            do: Map.merge(%{captured_at: timestamp, campaign_id: nil, ad_id: nil}, values),
            else: values

        Repo.insert_or_update!(
          Ecto.Changeset.change(current, Map.put(values, :updated_at, timestamp))
        )

        :ok
      end)
    else
      false -> {:error, :invalid_or_disabled}
    end
  end

  def capture_identity(_, _, _), do: {:error, :invalid_or_disabled}

  defp valid_identifier?(_, nil), do: true

  defp valid_identifier?(key, value) when is_binary(value) and byte_size(value) in 1..128 do
    if key == "yclid",
      do: Regex.match?(~r/^[a-zA-Z0-9_-]+$/, value),
      else: Regex.match?(~r/^[0-9]+$/, value)
  end

  defp valid_identifier?(_, _), do: false

  @doc "Called inside initial order creation; replay never replaces the receipt."
  def capture_order(order, opts, as_of) do
    settings = get_settings()

    if enabled?(settings, :conversions, order.branch_id) or
         enabled?(settings, :ecommerce, order.branch_id) do
      owner =
        cond do
          opts[:authenticated_client_id] -> "client:" <> opts[:authenticated_client_id]
          opts[:analytics_guest_id] -> "guest:" <> opts[:analytics_guest_id]
          true -> nil
        end

      identity =
        if owner && opts[:authenticated_client_id],
          do:
            Repo.one(
              from(i in Identity,
                where:
                  i.owner_key == ^owner and i.generation == ^settings.generation and
                    i.captured_at <= ^as_of,
                order_by: [desc: i.updated_at],
                limit: 1
              )
            )

      identity = identity || guest_identity(opts, settings, as_of)

      if identity && DateTime.diff(as_of, identity.updated_at) <= 7 * 86_400 do
        if opts[:authenticated_client_id] && String.starts_with?(identity.owner_key, "guest:") do
          Repo.update!(
            Ecto.Changeset.change(identity, claimed_client_id: opts[:authenticated_client_id])
          )
        end

        click_fields =
          if DateTime.diff(as_of, identity.captured_at) <= 7 * 86_400,
            do: Map.take(identity, [:yclid, :campaign_id, :ad_id]),
            else: %{yclid: nil, campaign_id: nil, ad_id: nil}

        attrs =
          Map.merge(
            %{client_id: identity.client_id, captured_at: identity.updated_at},
            click_fields
          )
          |> Map.merge(%{
            order_id: order.id,
            branch_id: order.branch_id,
            landing_branch_id: identity.branch_id,
            generation: settings.generation,
            counter_id: settings.counter_id,
            inserted_at: now()
          })

        Repo.insert!(struct(OrderReceipt, attrs), on_conflict: :nothing)
      end
    end

    :ok
  end

  defp guest_identity(opts, settings, as_of) do
    if guest = opts[:analytics_guest_id] do
      client = opts[:authenticated_client_id]

      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", [
        "yandex-owner:guest:" <> guest
      ])

      claimed_elsewhere =
        Repo.exists?(
          from(i in Identity,
            where:
              i.owner_key == ^("guest:" <> guest) and not is_nil(i.claimed_client_id) and
                i.claimed_client_id != ^(client || "00000000-0000-0000-0000-000000000000")
          )
        )

      if claimed_elsewhere do
        nil
      else
        Repo.one(
          from(i in Identity,
            where:
              i.owner_key == ^("guest:" <> guest) and i.generation == ^settings.generation and
                i.captured_at <= ^as_of,
            where:
              is_nil(i.claimed_client_id) or
                i.claimed_client_id == ^(client || "00000000-0000-0000-0000-000000000000"),
            order_by: [desc: i.updated_at],
            limit: 1,
            lock: "FOR UPDATE"
          )
        )
      end
    end
  end

  @doc "Short synchronous hook in the OMS transaction. No network calls."
  def record_transition(order, from, to) do
    cond do
      to == :completed -> enqueue_completed(order)
      from == :completed -> invalidate_completed(order.id)
      true -> :ok
    end
  end

  defp enqueue_completed(order) do
    settings = get_settings()
    receipt = Repo.get(OrderReceipt, order.id)

    if receipt && receipt.generation == settings.generation do
      order = Repo.preload(order, items: :modifiers)

      for {channel, stream} <- [{"offline", :conversions}, {"ecommerce", :ecommerce}],
          enabled?(settings, stream, order.branch_id) do
        payload = %{
          feature_generation: feature_token(stream, order.branch_id),
          client_id: receipt.client_id,
          yclid: receipt.yclid,
          goal: settings.goal,
          captured_at: DateTime.to_iso8601(receipt.captured_at),
          campaign_id: receipt.campaign_id,
          provenance: "external_unverified",
          items:
            Enum.map(
              order.items,
              &%{id: &1.product_id, name: &1.title, price: &1.price, quantity: &1.quantity}
            )
        }

        row = %Conversion{
          order_id: order.id,
          branch_id: order.branch_id,
          counter_id: settings.counter_id,
          generation: settings.generation,
          channel: channel,
          amount: order.total_amount,
          occurred_at: now(),
          payload: payload
        }

        Repo.insert!(row, on_conflict: :nothing)

        conversion =
          Repo.get_by!(Conversion,
            order_id: order.id,
            counter_id: settings.counter_id,
            channel: channel
          )

        conversion =
          if conversion.status == "reverted" and is_nil(conversion.attempted_at),
            do:
              Repo.update!(
                Ecto.Changeset.change(conversion,
                  status: "pending",
                  reason: nil,
                  amount: order.total_amount,
                  occurred_at: now(),
                  payload: payload
                )
              ),
            else: conversion

        if conversion.status == "pending",
          do: Oban.insert!(ConversionWorker.new(%{conversion_id: conversion.id}))
      end
    end

    :ok
  end

  defp invalidate_completed(order_id) do
    Repo.update_all(
      from(c in Conversion,
        where:
          c.order_id == ^order_id and c.status in ["pending", "sending", "submitted", "processed"]
      ),
      set: [
        status: "reverted",
        reason: "completion_reverted_review_external_result",
        updated_at: now()
      ]
    )

    :ok
  end

  def check_connections(staff) do
    if Accounts.can?(staff, "admin") do
      settings = get_settings()

      %{
        direct: Api.campaigns(settings),
        metrika: Api.counter(settings),
        metrika_goal: verify_goal(settings)
      }
    else
      {:error, :forbidden}
    end
  end

  defp verify_goal(settings) do
    with {:ok, %{body: %{"goals" => goals}}} <- Api.list_goals(settings),
         goal when is_map(goal) <-
           Enum.find(goals, fn goal ->
             goal["type"] == "action" and
               Enum.any?(
                 goal["conditions"] || [],
                 &(&1["url"] == settings.goal and &1["type"] == "exact")
               )
           end) do
      {:ok, %{id: goal["id"], identifier: settings.goal}}
    else
      nil -> {:error, :selected_goal_unavailable}
      error -> error
    end
  end

  def rotate_guest?(owner_key) do
    Repo.exists?(
      from(i in Identity, where: i.owner_key == ^owner_key and not is_nil(i.claimed_client_id))
    )
  end

  def request_costs(staff, from, to) do
    if account_report_authorized?(staff) do
      settings = get_settings()

      if costs_active?(settings) and valid_period?(from, to),
        do:
          %{generation: settings.generation, from: Date.to_iso8601(from), to: Date.to_iso8601(to)}
          |> Map.put(:feature_generations, costs_token(settings))
          |> Delivest.Integrations.YandexAds.CostWorker.new()
          |> Oban.insert(),
        else: {:error, :disabled_or_invalid_period}
    else
      {:error, :forbidden}
    end
  end

  def costs_active?(settings), do: Enum.any?(settings.branch_ids, &enabled?(settings, :costs, &1))

  def account_report_authorized?(staff) do
    staff = if staff, do: Repo.preload(staff, [:role, :branches])

    if Accounts.can?(staff, "statistics.read") and Accounts.can?(staff, "statistics.network") do
      if Accounts.can?(staff, "admin") do
        true
      else
        all =
          Repo.all(from(b in Delivest.Identity.Branch, where: is_nil(b.deleted_at), select: b.id))
          |> MapSet.new()

        allowed = Accounts.list_branch_for_staff(staff) |> Enum.map(& &1.id) |> MapSet.new()
        MapSet.subset?(all, allowed)
      end
    else
      false
    end
  end

  def refresh_access(staff) do
    if Accounts.can?(staff, "admin") do
      settings = get_settings()

      with token when is_binary(token) <- settings.refresh_token,
           {:ok, result} <- OAuth.refresh(token) do
        Repo.transaction(fn ->
          Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended('yandex-ads-settings',0))")
          current = get_settings()
          if current.generation != settings.generation, do: Repo.rollback(:connection_changed)

          current
          |> Settings.changeset(%{
            "direct_token" => result["access_token"],
            "metrika_token" => result["access_token"],
            "refresh_token" => result["refresh_token"]
          })
          |> Repo.update!()
        end)
      else
        _ -> {:error, :refresh_unavailable}
      end
    else
      {:error, :forbidden}
    end
  end

  def refresh_connection(staff), do: refresh_access(staff)

  def ensure_goal(staff) do
    if Accounts.can?(staff, "admin") do
      settings = get_settings()

      with {:ok, %{body: %{"goals" => goals}}} <- Api.list_goals(settings) do
        case Enum.find(goals, fn goal ->
               Enum.any?(
                 goal["conditions"] || [],
                 &(&1["url"] == settings.goal and &1["type"] == "exact")
               )
             end) do
          nil -> Api.create_goal(settings)
          goal -> {:ok, %{body: %{"goal" => goal}}}
        end
      end
    else
      {:error, :forbidden}
    end
  end

  @doc "Explicit administrator action to prepare the six existing browser funnel goals. Never runs during collection or checkout."
  def ensure_funnel_goals(staff) do
    if Accounts.can?(staff, "admin") do
      settings = get_settings()

      with {:ok, %{body: %{"goals" => goals}}} <- Api.list_goals(settings) do
        Enum.reduce_while(
          funnel_goal_identifiers(),
          {:ok, %{created: [], existing: []}},
          fn identifier, {:ok, result} ->
            existing =
              Enum.any?(goals, fn goal ->
                goal["type"] == "action" and
                  Enum.any?(
                    goal["conditions"] || [],
                    &(&1["url"] == identifier and &1["type"] == "exact")
                  )
              end)

            cond do
              existing ->
                {:cont, {:ok, %{result | existing: result.existing ++ [identifier]}}}

              get_settings().generation != settings.generation ->
                {:halt,
                 {:error, Map.merge(result, %{reason: :connection_changed, goal: identifier})}}

              true ->
                case Api.create_goal(settings, identifier) do
                  {:ok, %{status: status, body: %{"goal" => %{"id" => id}}}}
                  when status in 200..299 and is_integer(id) ->
                    {:cont, {:ok, %{result | created: result.created ++ [identifier]}}}

                  _ ->
                    {:halt,
                     {:error, Map.merge(result, %{reason: :goal_setup_failed, goal: identifier})}}
                end
            end
          end
        )
      end
    else
      {:error, :forbidden}
    end
  end

  def funnel_goal_identifiers,
    do:
      Enum.map(
        ~w(visit menu_view product_view cart_add checkout_start fulfillment_selected),
        &("delivest_" <> &1)
      )

  def register_branch_feed(staff, branch_id) do
    if Accounts.can?(staff, "admin") and enabled?(:feed, branch_id) do
      branch = Repo.get!(Delivest.Identity.Branch, branch_id)

      case DelivestWeb.Seo.SeoSite.origin() do
        origin when is_binary(origin) ->
          Api.register_feed(
            get_settings(),
            "Delivest " <> branch.name,
            String.trim_trailing(origin, "/") <>
              "/catalog/" <> URI.encode(branch.slug, &URI.char_unreserved?/1) <> ".xml",
            branch_id
          )

        _ ->
          {:error, :invalid_public_origin}
      end
    else
      {:error, :forbidden_or_disabled}
    end
  end

  def report(staff, %Date{} = from, %Date{} = to) do
    staff = if staff, do: Repo.preload(staff, [:role, :branches])

    if account_report_authorized?(staff) and
         Date.diff(to, from) in 0..366 do
      settings = get_settings()
      account = account_key(settings)

      latest_costs =
        from(c in Cost,
          where: c.account == ^account and c.day >= ^from and c.day <= ^to,
          distinct: [c.day, c.campaign_id],
          order_by: [asc: c.day, asc: c.campaign_id, desc: c.updated_at]
        )

      cost_totals =
        Repo.one(
          from(c in subquery(latest_costs),
            select: %{rows: count(c.id), total: coalesce(sum(c.cost_micros), 0)}
          )
        )

      costs = Repo.all(from(c in latest_costs, limit: 250))

      {start_at, end_at} = report_bounds(from, to, settings.timezone)

      conversion_counts =
        Repo.all(
          from(c in Conversion,
            where: c.occurred_at >= ^start_at and c.occurred_at < ^end_at,
            group_by: [c.channel, c.status],
            select: %{channel: c.channel, status: c.status, count: count(c.id)}
          )
        )

      f04 =
        case Delivest.Analytics.Reports.read(staff, :franchise, {from, to}, "franchise") do
          {:ok, data} -> data
          _ -> %{state: :disabled, totals: %{}, covered_days: 0, expected_days: 0}
        end

      collected = f04.state not in [:disabled, :not_collected]
      completed = if collected, do: Map.get(f04.totals, "completed", 0)
      net = if collected, do: Map.get(f04.totals, "revenue", 0)

      %{rows: [[identified]]} =
        Repo.query!(
          """
            SELECT COUNT(*)::bigint
            FROM orders o JOIN yandex_ads_order_receipts r ON r.order_id=o.id
            LEFT JOIN branch_info bi ON bi.branch_id=o.branch_id
            WHERE o.status='completed' AND o.deleted_at IS NULL AND
              timezone(COALESCE(bi.timezone,$3), timezone('UTC',o.inserted_at))::date BETWEEN $1 AND $2
          """,
          [from, to, settings.timezone]
        )

      {:ok,
       %{
         costs: costs,
         cost_total_micros: integer_sum(cost_totals.total),
         costs_total_rows: cost_totals.rows,
         costs_truncated: cost_totals.rows > 250,
         conversions: conversion_counts,
         completed_orders: completed,
         identified_orders: identified,
         net_revenue: net,
         f04_state: f04.state,
         f04_coverage:
           Map.take(f04, [:covered_days, :expected_days, :partial_days, :last_success_at]),
         roas: nil,
         cpa: nil,
         attribution: "external_unverified",
         delivery_issues: list_delivery_issues(staff),
         last_cost_update:
           settings.costs_refreshed_at ||
             costs |> Enum.map(& &1.updated_at) |> Enum.max(DateTime, fn -> nil end)
       }}
    else
      {:error, :forbidden_or_invalid_period}
    end
  end

  def report(_, _, _), do: {:error, :invalid_period}

  def list_delivery_issues(staff) do
    if account_report_authorized?(staff) do
      Repo.all(
        from(c in Conversion,
          where: c.status in ["unknown", "failed", "reverted", "skipped", "stale"],
          order_by: [desc: c.updated_at],
          limit: 50,
          select: %{
            id: c.id,
            order_id: c.order_id,
            channel: c.channel,
            status: c.status,
            reason: c.reason,
            upload_id: c.upload_id,
            provider_status: c.provider_status,
            occurred_at: c.occurred_at
          }
        )
      )
    else
      []
    end
  end

  def reconcile_delivery(staff, id, upload_id) do
    with true <- Accounts.can?(staff, "admin"),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         true <- is_binary(upload_id) and Regex.match?(~r/^[0-9]{1,30}$/, upload_id) do
      Repo.transaction(fn ->
        row = Repo.one(from(c in Conversion, where: c.id == ^uuid, lock: "FOR UPDATE"))
        settings = get_settings()

        if is_nil(row) or row.channel != "offline" or row.status != "unknown" or
             row.generation != settings.generation or
             not enabled?(settings, :conversions, row.branch_id),
           do: Repo.rollback(:not_reconcilable)

        Repo.update!(
          Ecto.Changeset.change(row,
            status: "submitted",
            upload_id: upload_id,
            reason: "admin_supplied_upload_id_for_poll_only"
          )
        )

        Oban.insert!(ConversionWorker.new(%{conversion_id: row.id}))

        Delivest.Audit.record(staff, "integration.yandex_upload_reconciled", :franchise,
          metadata: %{conversion_id: row.id, upload_id: upload_id}
        )

        :ok
      end)
    else
      _ -> {:error, :forbidden_or_invalid}
    end
  end

  defp integer_sum(%Decimal{} = value), do: Decimal.to_integer(value)
  defp integer_sum(value), do: value

  defp report_bounds(from, to, timezone) do
    {DateTime.new!(from, ~T[00:00:00], timezone) |> DateTime.shift_zone!("Etc/UTC"),
     DateTime.new!(Date.add(to, 1), ~T[00:00:00], timezone) |> DateTime.shift_zone!("Etc/UTC")}
  end

  def valid_period?(%Date{} = from, %Date{} = to), do: Date.diff(to, from) in 0..31
  def valid_period?(_, _), do: false
  def now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  def lock_settings,
    do:
      Repo.query!(
        "SELECT pg_advisory_xact_lock_shared(hashtextextended('yandex-ads-settings',0))"
      )
end
