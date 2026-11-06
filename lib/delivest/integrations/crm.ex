defmodule Delivest.Integrations.Crm do
  import Ecto.Query

  alias Delivest.{Identity, Repo}
  alias Delivest.Identity.Branch

  alias Delivest.Integrations.Crm.{
    BranchSettings,
    CommandDelivery,
    CommandWorker,
    ConfirmWorker,
    Registry,
    SyncState,
    SyncWorker,
    Throttle
  }

  alias Delivest.Integrations.Journal
  alias Delivest.Integrations.Health
  alias Delivest.Oms.{Order, Orders}

  @permanent_errors [:branch_not_found, :unknown_provider, :missing_settings]
  @confirm_minutes 5
  @credential_fields %{
    frontpad: [:api_key, :affiliate],
    iiko: [:api_key, :organization_id, :terminal_group_id],
    rkeeper: [:object_id]
  }

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
         {:ok, uuid} <- Ecto.UUID.cast(order_id) do
      Repo.transaction(fn ->
        order =
          Repo.one(
            from(o in Order,
              where: o.id == ^uuid and o.branch_id == ^branch_id,
              lock: "FOR UPDATE"
            )
          )

        case order do
          %Order{crm: %{}} ->
            case resolve(order, action, number) do
              {:ok, updated} -> updated
              {:error, reason} -> Repo.rollback(reason)
            end

          _ ->
            Repo.rollback(:order_not_found)
        end
      end)
    else
      {:error, :forbidden} -> {:error, :forbidden}
      _ -> {:error, :order_not_found}
    end
  end

  defp resolve(order, "acknowledge", _number), do: SyncState.acknowledge_alert(order)

  defp resolve(
         %Order{crm: %{status: "sending", sending_started_at: started}} = order,
         action,
         number
       )
       when action in ["exists", "resend"] and not is_nil(started) do
    if DateTime.diff(DateTime.utc_now(), started, :second) < 600 do
      {:error, :request_in_progress}
    else
      with {:ok, updated} <-
             SyncState.unknown(
               order,
               "CRM request may have completed before worker stopped",
               order.crm.attempts
             ) do
        resolve(updated, action, number)
      end
    end
  end

  defp resolve(%Order{crm: %{status: status}} = order, "exists", number)
       when status in ["failed", "unknown"] and is_binary(number) and number != "" do
    number = String.trim(number)

    SyncState.sent(
      order,
      %{external_id: number, external_number: number},
      order.crm.attempts
    )
  end

  defp resolve(%Order{crm: %{status: status}}, "exists", _number)
       when status in ["failed", "unknown"],
       do: {:error, :number_required}

  defp resolve(%Order{crm: %{status: status}} = order, "resend", _number)
       when status in ["failed", "unknown"] do
    with {:ok, order} <-
           Orders.update_order_crm(order, %{status: "pending", alert: nil, last_error: nil}),
         {:ok, _job} <- enqueue_sync(order),
         do: {:ok, order}
  end

  defp resolve(_order, _action, _number), do: {:error, :unknown_action}

  def get_branch_settings(branch_id) do
    case Identity.get_branch(branch_id, preload: [:info]) do
      {:ok, %Branch{info: %{crm: %BranchSettings{} = settings}}} -> settings
      _ -> %BranchSettings{}
    end
  end

  def change_branch_settings(%BranchSettings{} = settings, attrs \\ %{}),
    do: BranchSettings.changeset(settings, attrs)

  def update_branch_settings(staff, branch_id, attrs) do
    with {:ok, branch} <- Identity.get_branch(branch_id, preload: [:info]),
         {:ok, %Branch{info: %{crm: settings}}} <-
           Identity.update_integrations(staff, branch, %{"crm" => attrs}) do
      invalidate_changed_credentials(branch, settings, branch_id)
      {:ok, settings}
    else
      {:error, :info, changeset} -> {:error, Ecto.Changeset.get_change(changeset, :crm)}
      {:error, _step, changeset} -> {:error, changeset}
      error -> error
    end
  end

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

  def deliver(%Order{} = order), do: call(order, & &1.deliver_order(order, &2))

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

  def enqueue_command(%Order{} = order, action, args \\ %{}, event_id \\ nil) do
    Repo.transaction(fn ->
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        ["crm_command:#{order.id}"]
      )

      existing = event_id && Repo.get_by(CommandDelivery, event_id: event_id)

      if existing do
        existing
      else
        job_args =
          args
          |> Map.merge(%{
            "order_id" => order.id,
            "branch_id" => order.branch_id,
            "action" => action
          })
          |> then(&if(is_binary(event_id), do: Map.put(&1, "event_id", event_id), else: &1))

        with {:ok, job} <- job_args |> CommandWorker.new() |> Oban.insert(),
             {:ok, _delivery} <-
               Repo.insert(%CommandDelivery{
                 job_id: job.id,
                 order_id: order.id,
                 branch_id: order.branch_id,
                 event_id: event_id,
                 args: job.args,
                 execution_job_id: job.id
               }) do
          job
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end
    end)
  end

  def list_unknown_commands(staff, branch_id) do
    with :ok <- Identity.authorize(staff, "orders.update", branch_id) do
      stale = DateTime.add(DateTime.utc_now(), -600, :second)

      CommandDelivery
      |> where([d], d.branch_id == ^branch_id and d.phase == "calling")
      |> where([d], d.updated_at < ^stale)
      |> Repo.update_all(set: [phase: "unknown", last_error: "Worker stopped during CRM request"])

      Ecto.Adapters.SQL.query!(
        Repo,
        """
        WITH candidates AS (
          SELECT d.job_id
          FROM crm_command_deliveries d
          LEFT JOIN oban_jobs j ON j.id = COALESCE(d.execution_job_id, d.job_id)
          WHERE d.branch_id = $1 AND d.phase = 'pending'
            AND (j.id IS NULL OR j.state IN ('discarded', 'cancelled'))
          ORDER BY d.job_id
          LIMIT 100
        )
        UPDATE crm_command_deliveries d
        SET phase = 'unknown', last_error = 'Command job stopped or was pruned', updated_at = now()
        FROM candidates c WHERE d.job_id = c.job_id AND d.phase = 'pending'
        """,
        [Ecto.UUID.dump!(branch_id)]
      )

      {:ok,
       Repo.all(
         from(d in CommandDelivery,
           where: d.branch_id == ^branch_id and d.phase in ["unknown", "failed"],
           order_by: [asc: d.job_id],
           limit: 100
         )
       )}
    end
  end

  def list_unknown_syncs(staff, branch_id) do
    with :ok <- Identity.authorize(staff, "orders.update", branch_id) do
      stale = DateTime.add(DateTime.utc_now(), -600, :second)

      Repo.all(
        from(o in Order,
          where: o.branch_id == ^branch_id,
          where: fragment("?->>'status' = 'sending'", o.crm),
          where:
            fragment(
              "(?->>'sending_started_at') IS NULL OR (?->>'sending_started_at')::timestamptz < ?",
              o.crm,
              o.crm,
              ^stale
            ),
          order_by: [asc: o.updated_at],
          limit: 100,
          select: o.id
        )
      )
      |> Enum.each(fn order_id -> reconcile_stale_sync(order_id, stale) end)

      {:ok,
       Repo.all(
         from(o in Order,
           where: o.branch_id == ^branch_id,
           where: fragment("?->>'status' IN ('unknown', 'failed')", o.crm),
           where: fragment("COALESCE(?->>'alert', '') <> ''", o.crm),
           order_by: [asc: o.updated_at],
           limit: 100
         )
       )}
    end
  end

  defp reconcile_stale_sync(order_id, stale) do
    Repo.transaction(fn ->
      order = Repo.one(from(o in Order, where: o.id == ^order_id, lock: "FOR UPDATE"))

      case order do
        %Order{crm: %{status: "sending", sending_started_at: started}} = current
        when is_nil(started) ->
          reconcile_unknown(current)

        %Order{crm: %{status: "sending", sending_started_at: started}} = current ->
          if DateTime.compare(started, stale) == :lt, do: reconcile_unknown(current)

        _ ->
          :ok
      end
    end)
  end

  defp reconcile_unknown(order) do
    case SyncState.unknown(
           order,
           "CRM request may have completed before worker stopped",
           order.crm.attempts
         ) do
      {:ok, _updated} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def resolve_command(staff, branch_id, job_id, action) when action in ["done", "retry"] do
    with :ok <- Identity.authorize(staff, "orders.update", branch_id) do
      Repo.transaction(fn ->
        order_id =
          Repo.one(
            from(d in CommandDelivery,
              where: d.job_id == ^job_id and d.branch_id == ^branch_id,
              select: d.order_id
            )
          ) || Repo.rollback(:command_not_resolvable)

        Ecto.Adapters.SQL.query!(
          Repo,
          "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
          ["crm_command:#{order_id}"]
        )

        delivery =
          Repo.one(
            from(d in CommandDelivery,
              where: d.job_id == ^job_id and d.branch_id == ^branch_id,
              lock: "FOR UPDATE"
            )
          )

        if is_nil(delivery) or delivery.phase not in ["unknown", "failed"],
          do: Repo.rollback(:command_not_resolvable)

        execution_job_id =
          if action == "retry", do: retry_command(delivery), else: delivery.execution_job_id

        resolved =
          delivery
          |> Ecto.Changeset.change(
            phase: if(action == "done", do: "done", else: "pending"),
            last_error: nil,
            execution_job_id: execution_job_id
          )
          |> Repo.update!()

        if order = Repo.get(Order, order_id),
          do:
            Delivest.Audit.record(staff, "order.crm_command_resolved", order,
              metadata: %{job_id: job_id, action: action}
            )

        resolved
      end)
    end
  end

  def resolve_command(_staff, _branch_id, _job_id, _action), do: {:error, :invalid_action}

  defp retry_command(%CommandDelivery{} = delivery) do
    args = delivery.args

    unless is_map(args) and args["order_id"] == delivery.order_id and
             args["action"] in ["update", "cancel"] do
      Repo.rollback(:command_args_not_found)
    end

    case Repo.get(Oban.Job, delivery.execution_job_id || delivery.job_id) do
      %Oban.Job{id: id, state: state} when state not in ["executing"] ->
        :ok = Oban.retry_job(id)
        id

      %Oban.Job{state: "executing"} ->
        Repo.rollback(:job_active)

      nil ->
        args
        |> Map.put("command_delivery_id", delivery.job_id)
        |> CommandWorker.new()
        |> Oban.insert()
        |> case do
          {:ok, job} -> job.id
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp call(%Order{crm: %{provider: provider}} = order, fun) do
    with {:ok, name, module} <- provider_module(provider),
         {:ok, settings} <- branch_settings(order.branch_id, name) do
      if Health.down?(name, order.branch_id) do
        {:error, :provider_down}
      else
        Journal.scope([branch_id: order.branch_id, order_id: order.id], fn ->
          Throttle.run(module.rate_limit(settings), fn -> fun.(module, settings) end)
        end)
      end
    end
  end

  defp call(_order, _fun), do: {:error, :unknown_provider}

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

  def classify_error(_order, reason) when reason in @permanent_errors, do: :permanent

  def classify_error(%Order{crm: %{provider: provider}}, reason) do
    case provider_module(provider) do
      {:ok, _name, module} -> module.classify_error(reason)
      _ -> :permanent
    end
  end

  def enqueue_sync(%Order{} = order) do
    %{"order_id" => order.id, "branch_id" => order.branch_id}
    |> SyncWorker.new()
    |> Oban.insert()
  end

  def provider_module(provider) do
    with {:ok, module} <- Registry.fetch(provider), do: {:ok, module.key(), module}
  end

  defp branch_settings(branch_id, name) do
    case Identity.get_branch(branch_id, preload: [:info]) do
      {:ok, %Branch{info: %{crm: %BranchSettings{} = crm}}} -> settings(crm, name)
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
