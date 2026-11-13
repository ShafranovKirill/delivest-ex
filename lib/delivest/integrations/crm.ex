defmodule Delivest.Integrations.Crm do
  import Ecto.Query, only: [from: 2]

  alias Delivest.{Identity, Repo}
  alias Delivest.Identity.Branch

  alias Delivest.Integrations.Crm.{
    BranchSettings,
    Commands,
    ConfirmWorker,
    Registry,
    StopSync,
    SyncState,
    SyncWorker,
    Throttle
  }

  alias Delivest.Integrations.Journal
  alias Delivest.Integrations.Availability
  alias Delivest.Integrations.Health
  alias Delivest.Oms.{Order, Orders}

  @permanent_errors [:branch_not_found, :unknown_provider, :missing_settings]
  @confirm_minutes 5
  @credential_fields %{
    frontpad: [:api_key, :affiliate],
    iiko: [:api_key, :organization_id, :terminal_group_id],
    rkeeper: [:object_id]
  }

  def topic(branch_id), do: "crm_settings:#{branch_id}"

  def providers, do: Enum.map(Registry.modules(), &{&1.key(), &1.name()})

  def default_provider(branch_id) do
    branch_id |> get_branch_settings() |> BranchSettings.active_provider() ||
      hd(Registry.keys())
  end

  def provider_name(provider) do
    case Registry.fetch(provider) do
      {:ok, module} -> module.name()
      error -> error
    end
  end

  def configured?(%BranchSettings{} = crm, provider) do
    case Registry.fetch(provider) do
      {:ok, module} -> module.configured?(Map.get(crm, module.key()))
      _ -> false
    end
  end

  def webhook_url(provider, token),
    do: DelivestWeb.Endpoint.url() <> "/integrations/crm/#{provider}/" <> token

  def handle_webhook(provider, token, params) do
    with {:ok, module} <- Registry.fetch(provider),
         true <- function_exported?(module, :handle_webhook, 2) || {:error, :unknown_provider} do
      module.handle_webhook(token, params)
    end
  end

  def active_provider(%Branch{info: %{crm: %BranchSettings{} = settings}}),
    do: BranchSettings.active_provider(settings)

  def active_provider(_branch), do: nil

  def provider_for(%Branch{info: %{crm: %BranchSettings{} = settings}}, source),
    do: BranchSettings.provider_for(settings, source)

  def provider_for(_branch, _source), do: nil

  def manual_cancel_required?(
        %Order{
          channel: %{remote_status: "cancelled"},
          crm: %{status: "sent", remote_status: remote}
        } = order
      ),
      do: remote != "cancelled" and not can?(order, :cancel)

  def manual_cancel_required?(_order), do: false

  def alert?(%Order{crm: %{alert: alert}}), do: is_binary(alert) and alert != ""
  def alert?(_order), do: false

  def resolve_alert(staff, branch_id, order_id, action, number \\ nil) do
    with :ok <- Identity.authorize(staff, "orders.update", branch_id),
         {:ok, uuid} <- Ecto.UUID.cast(order_id),
         %Order{crm: %{}} = order <- Repo.get_by(Order, id: uuid, branch_id: branch_id) do
      resolve(order, action, number)
    else
      {:error, :forbidden} -> {:error, :forbidden}
      _ -> {:error, :order_not_found}
    end
  end

  defp resolve(order, "acknowledge", _number), do: SyncState.acknowledge_alert(order)

  defp resolve(order, "exists", number) when is_binary(number) and number != "" do
    number = String.trim(number)

    SyncState.sent(
      order,
      %{external_id: number, external_number: number},
      order.crm.attempts
    )
  end

  defp resolve(_order, "exists", _number), do: {:error, :number_required}

  defp resolve(order, "resend", _number) do
    retry_order(order, ["unknown"], "order.crm_resend")
  end

  defp resolve(%Order{crm: %{status: status}} = order, "retry_unsent", _number)
       when status in ["pending", "failed"] do
    retry_order(order, ["pending", "failed"], "order.crm_retry_unsent")
  end

  defp resolve(_order, _action, _number), do: {:error, :unknown_action}

  defp retry_order(order, allowed_statuses, audit_event) do
    case Repo.transaction(fn ->
           Repo.one!(
             from(i in Delivest.Identity.Branch.BranchInfo,
               where: i.branch_id == ^order.branch_id,
               lock: "FOR SHARE"
             )
           )

           current = Repo.one!(from(o in Order, where: o.id == ^order.id, lock: "FOR UPDATE"))

           if current.crm.status not in allowed_statuses or
                not Availability.crm_allowed?(current.branch_id, current.crm.provider, :orders) or
                current.source not in (get_branch_settings(current.branch_id).sources || []),
              do: Repo.rollback(:disabled)

           if active_sync_job?(current.id), do: Repo.rollback(:already_queued)

           case Orders.update_order_crm(current, %{status: "pending", alert: nil, last_error: nil}) do
             {:ok, updated} ->
               case enqueue_sync(updated) do
                 {:ok, %Oban.Job{}} ->
                   Delivest.Audit.record(:system, audit_event, updated)
                   updated

                 _ ->
                   Repo.rollback(:disabled)
               end

             error ->
               Repo.rollback(error)
           end
         end) do
      {:ok, updated} -> {:ok, updated}
      {:error, reason} -> {:error, reason}
    end
  end

  defp active_sync_job?(order_id) do
    Repo.exists?(
      from(j in Oban.Job,
        where: j.worker == ^Oban.Worker.to_string(SyncWorker),
        where: j.state in ["available", "scheduled", "retryable", "executing"],
        where: fragment("?->>'order_id' = ?", j.args, ^order_id)
      )
    )
  end

  def get_branch_settings(branch_id) do
    case Repo.get_by(Delivest.Identity.Branch.BranchInfo, branch_id: branch_id) do
      %{crm: %BranchSettings{} = settings} -> settings
      _ -> %BranchSettings{}
    end
  end

  def work_summary(branch_id) do
    from(o in Order,
      where: o.branch_id == ^branch_id and is_nil(o.deleted_at),
      where: fragment("?->>'provider' IS NOT NULL", o.crm),
      select: {fragment("?->>'provider'", o.crm), fragment("?->>'status'", o.crm), o.status}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {provider, crm_status, order_status}, acc ->
      kind =
        cond do
          crm_status in ["pending", "failed"] and order_status not in [:completed, :cancelled] ->
            :unsent

          crm_status in ["sending", "confirming", "unknown"] ->
            :uncertain

          crm_status == "sent" and order_status not in [:completed, :cancelled] ->
            :accepted

          true ->
            nil
        end

      if kind do
        update_in(
          acc,
          [Access.key(provider, %{unsent: 0, uncertain: 0, accepted: 0}), kind],
          &(&1 + 1)
        )
      else
        acc
      end
    end)
  end

  def change_branch_settings(%BranchSettings{} = settings, attrs \\ %{}),
    do: BranchSettings.changeset(settings, attrs)

  def update_branch_settings(staff, branch_id, attrs) do
    result =
      Repo.transaction(fn ->
        branch =
          Repo.one(
            from(b in Branch,
              where: b.id == ^branch_id and is_nil(b.deleted_at),
              lock: "FOR UPDATE"
            )
          )
          |> then(&if(&1, do: Repo.preload(&1, :info), else: nil))

        if is_nil(branch), do: Repo.rollback({:error, :not_found})

        case Identity.update_integrations(staff, branch, %{"crm" => attrs}) do
          {:ok, %Branch{info: %{crm: settings}}} ->
            current = Repo.get_by!(Delivest.Identity.Branch.BranchInfo, branch_id: branch_id)

            if current.crm.generation != settings.generation,
              do: Repo.rollback({:error, :settings_changed})

            invalidate_changed_credentials(branch, settings, branch_id)
            clear_disabled_stops(branch.info && branch.info.crm, settings, branch_id)
            cancel_stale_jobs(branch.info && branch.info.crm, settings, branch_id)
            settings

          error ->
            Repo.rollback(error)
        end
      end)

    case result do
      {:ok, settings} ->
        Phoenix.PubSub.broadcast(
          Delivest.PubSub,
          topic(branch_id),
          {:crm_settings_changed, branch_id}
        )

        {:ok, settings}

      {:error, {:error, :info, changeset}} ->
        {:error, Ecto.Changeset.get_change(changeset, :crm)}

      {:error, {:error, _step, changeset}} ->
        {:error, changeset}

      {:error, error} ->
        error
    end
  end

  defp clear_disabled_stops(%BranchSettings{} = previous, settings, branch_id) do
    provider = BranchSettings.active_provider(previous)

    if provider && not Availability.crm(settings, provider).capabilities.stops do
      if provider == :frontpad do
        StopSync.clear_frontpad(branch_id)
      else
        Delivest.Net.Stops.replace_external(branch_id, provider, [])
      end
    end
  end

  defp clear_disabled_stops(_previous, _settings, _branch_id), do: :ok

  defp cancel_stale_jobs(
         %BranchSettings{generation: previous},
         %BranchSettings{generation: current},
         branch_id
       )
       when previous != current do
    stale_order_ids =
      Repo.all(
        from(j in Oban.Job,
          where: j.worker == ^Oban.Worker.to_string(SyncWorker),
          where: j.state in ["available", "scheduled", "retryable"],
          where: fragment("?->>'branch_id' = ?", j.args, ^branch_id),
          where:
            fragment(
              "(?->>'generation') IS NULL OR (?->>'generation')::integer <> ?",
              j.args,
              j.args,
              ^current
            ),
          select: fragment("?->>'order_id'", j.args)
        )
      )
      |> Enum.uniq()

    for {worker, field, poller} <- [
          {SyncWorker, "branch_id", nil},
          {Delivest.Integrations.Poller.Worker, "target", "crm_catalog"},
          {Delivest.Integrations.Poller.Worker, "target", "crm_stops"},
          {Delivest.Integrations.Crm.FrontpadStopRefresh.RefreshJob, "branch_id", nil}
        ] do
      query =
        from(j in Oban.Job,
          where:
            j.worker == ^Oban.Worker.to_string(worker) and
              j.state in ["available", "scheduled", "retryable"],
          where: fragment("?->>? = ?", j.args, ^field, ^branch_id),
          where:
            fragment(
              "(?->>'generation') IS NULL OR (?->>'generation')::integer <> ?",
              j.args,
              j.args,
              ^current
            )
        )

      query =
        if poller,
          do: from(j in query, where: fragment("?->>'poller' = ?", j.args, ^poller)),
          else: query

      query
      |> Oban.cancel_all_jobs()
    end

    %{rows: rows} =
      Repo.query!(
        """
        UPDATE orders
        SET crm = jsonb_set(jsonb_set(crm, '{alert}', to_jsonb($2::text), true),
                              '{last_error}', to_jsonb($2::text), true)
        WHERE branch_id = $1 AND crm->>'status' = 'pending'
          AND id::text = ANY($3::text[])
          AND NOT EXISTS (
            SELECT 1 FROM oban_jobs j
            WHERE j.worker = 'Delivest.Integrations.Crm.SyncWorker'
              AND j.args->>'order_id' = orders.id::text
              AND j.state IN ('available', 'scheduled', 'retryable', 'executing')
          )
        RETURNING id
        """,
        [
          Ecto.UUID.dump!(branch_id),
          "CRM settings changed. This order was not sent; send it explicitly after checking the route.",
          stale_order_ids
        ]
      )

    Enum.each(rows, fn [id] ->
      if order = Repo.get(Order, Ecto.UUID.load!(id)),
        do: Delivest.Audit.record(:system, "order.crm_queued_cancelled", order)
    end)

    unless Availability.crm_allowed?(branch_id, :frontpad, :stops) do
      case Repo.get(Delivest.Integrations.Crm.FrontpadStopRefresh.State, branch_id) do
        %{status: status} when status in ["queued", "running", "retrying"] ->
          Delivest.Integrations.Crm.FrontpadStopRefresh.put_state(branch_id, %{
            status: "disabled",
            last_error: nil
          })

          Delivest.Integrations.Crm.FrontpadStopRefresh.broadcast(branch_id)

        _ ->
          :ok
      end
    end
  end

  defp cancel_stale_jobs(_previous, _current, _branch_id), do: :ok

  defp invalidate_changed_credentials(%Branch{info: %{crm: previous}}, settings, branch_id)
       when is_map(previous) do
    Enum.each(@credential_fields, fn {provider, fields} ->
      Health.invalidate_on_change(
        provider,
        branch_id,
        Map.get(previous, provider),
        Map.get(settings, provider),
        fields
      )
    end)
  end

  defp invalidate_changed_credentials(_branch, _settings, _branch_id), do: :ok

  def create_order(attrs, provider, opts \\ []) do
    opts = Keyword.put(opts, :crm, %{provider: to_string(provider), status: "pending"})

    attrs
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Orders.create_order(opts)
  end

  def capabilities(provider) do
    case Registry.fetch(provider) do
      {:ok, module} -> optional(module, :capabilities, [], [])
      _ -> []
    end
  end

  def can?(%Order{crm: %{provider: provider}}, capability),
    do: capability in capabilities(provider)

  def can?(_order, _capability), do: false

  def idempotent?(provider) do
    case Registry.fetch(provider) do
      {:ok, module} -> optional(module, :idempotent?, [], false)
      _ -> false
    end
  end

  def status_for(provider, settings, code) do
    with {:ok, module} <- Registry.fetch(provider),
         true <- exported?(module, :status_map, 1) do
      Map.get(module.status_map(settings), to_string(code))
    else
      _ -> nil
    end
  end

  def dictionaries(branch_id) do
    with {:ok, name, module} <- branch_provider(branch_id),
         true <- exported?(module, :dictionaries, 1) || {:ok, %{}},
         {:ok, settings} <- branch_settings(branch_id, name) do
      module.dictionaries(settings)
    end
  end

  def menu_source?(provider) do
    case Registry.fetch(provider) do
      {:ok, module} -> exported?(module, :fetch_menu, 1)
      _ -> false
    end
  end

  def menu_owner(branch_id, product_id) when is_binary(product_id) do
    with %BranchSettings{menu_source: :crm} = crm <- get_branch_settings(branch_id),
         provider when not is_nil(provider) <- BranchSettings.active_provider(crm),
         true <- menu_source?(provider),
         true <-
           Repo.exists?(
             from(e in Delivest.Net.ProductExternalId,
               where: e.entity_type == "product" and e.entity_id == ^product_id,
               where: e.branch_id == ^branch_id and e.provider == ^to_string(provider)
             )
           ) do
      provider_name(provider)
    else
      _ -> nil
    end
  end

  def menu_owner(_branch_id, _product_id), do: nil

  def stops_source?(provider) do
    case Registry.fetch(provider) do
      {:ok, module} -> exported?(module, :fetch_stops, 1)
      _ -> false
    end
  end

  def fetch_menu(branch_id) do
    with {:ok, name, module} <- branch_provider(branch_id),
         true <- exported?(module, :fetch_menu, 1) || {:error, :no_menu_source},
         {:ok, settings} <- branch_settings(branch_id, name),
         {:ok, menu} <- module.fetch_menu(settings) do
      {:ok, name, menu}
    end
  end

  def deliver(%Order{} = order, generation \\ nil) do
    if order.source in (get_branch_settings(order.branch_id).sources || []) and
         Availability.crm_allowed?(order.branch_id, order.crm.provider, :orders, generation),
       do: call(order, & &1.deliver_order(order, &2), generation),
       else: {:error, :disabled}
  end

  def cancel(%Order{} = order, reason),
    do: call(order, & &1.cancel_order(order, reason, &2))

  def update(%Order{} = order, changes),
    do: call(order, & &1.update_order(order, changes, &2))

  def confirm_order(%Order{crm: %{status: "confirming"}} = order, delivery),
    do: SyncState.sent(order, delivery, order.crm.attempts)

  def confirm_order(%Order{}, _delivery), do: {:error, :not_confirming}

  def reject_order(%Order{crm: %{status: "confirming"}} = order, error),
    do: SyncState.failed(order, error, order.crm.attempts)

  def reject_order(%Order{}, _error), do: {:error, :not_confirming}

  def schedule_confirm_check(%Order{} = order) do
    %{"order_id" => order.id, "ref" => order.crm && order.crm.ref}
    |> ConfirmWorker.new(schedule_in: {@confirm_minutes, :minutes})
    |> Oban.insert()
  end

  def enqueue_command(%Order{} = order, action, args \\ %{}, event_id \\ nil),
    do: Commands.enqueue(order, action, args, event_id)

  defp call(order, fun, generation \\ :completion)

  defp call(%Order{crm: %{provider: provider}} = order, fun, generation) do
    with {:ok, name, module} <- provider_module(provider),
         {:ok, settings} <- branch_settings(order.branch_id, name) do
      if generation != :completion and
           not Availability.crm_allowed?(order.branch_id, provider, :orders, generation) do
        {:error, :disabled}
      else
        call_ready(order, name, module, settings, fun, generation)
      end
    end
  end

  defp call(_order, _fun, _generation), do: {:error, :unknown_provider}

  defp call_ready(order, name, module, settings, fun, generation) do
    if Health.down?(name, order.branch_id) do
      {:error, :provider_down}
    else
      Journal.scope([branch_id: order.branch_id, order_id: order.id], fn ->
        Throttle.run(module.rate_limit(settings), fn ->
          if generation == :completion or
               Availability.crm_allowed?(order.branch_id, order.crm.provider, :orders, generation),
             do: fun.(module, settings),
             else: {:error, :disabled}
        end)
      end)
    end
  end

  defp optional(module, function, args, default) do
    if exported?(module, function, length(args)),
      do: apply(module, function, args),
      else: default
  end

  defp exported?(module, function, arity),
    do: Code.ensure_loaded?(module) and function_exported?(module, function, arity)

  defp branch_provider(branch_id) do
    case branch_id |> get_branch_settings() |> BranchSettings.active_provider() do
      nil -> {:error, :missing_settings}
      provider -> provider_module(provider)
    end
  end

  def classify_error(_order, {:throttled, ms}), do: {:snooze, max(div(ms + 999, 1000), 1)}

  def classify_error(_order, :provider_down), do: {:snooze, 60}

  def classify_error(_order, reason) when reason in [:disabled | @permanent_errors],
    do: :permanent

  def classify_error(%Order{crm: %{provider: provider}}, reason) do
    case provider_module(provider) do
      {:ok, _name, module} -> module.classify_error(reason)
      _ -> :permanent
    end
  end

  def enqueue_sync(%Order{} = order) do
    case Repo.transaction(fn ->
           Repo.one(
             from(i in Delivest.Identity.Branch.BranchInfo,
               where: i.branch_id == ^order.branch_id,
               lock: "FOR SHARE"
             )
           )

           state = Availability.crm(order.branch_id, order.crm.provider)

           if state.capabilities.orders and
                order.source in (get_branch_settings(order.branch_id).sources || []) do
             args = %{
               "order_id" => order.id,
               "branch_id" => order.branch_id,
               "generation" => state.generation
             }

             case args |> SyncWorker.new() |> Oban.insert() do
               {:ok, job} -> job
               {:error, reason} -> Repo.rollback(reason)
             end
           else
             :disabled
           end
         end) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  def provider_module(provider) do
    with {:ok, module} <- Registry.fetch(provider), do: {:ok, module.key(), module}
  end

  defp branch_settings(branch_id, name) do
    case Repo.get_by(Delivest.Identity.Branch.BranchInfo, branch_id: branch_id) do
      %{crm: %BranchSettings{} = crm} -> settings(crm, name)
      _ -> {:error, :branch_not_found}
    end
  end

  defp settings(crm, name) do
    case Map.get(crm, name) do
      nil -> {:error, :missing_settings}
      settings -> {:ok, settings}
    end
  end
end
