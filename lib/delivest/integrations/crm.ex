defmodule Delivest.Integrations.Crm do
  import Ecto.Query, only: [from: 2]

  alias Delivest.{Identity, Repo}
  alias Delivest.Identity.Branch

  alias Delivest.Integrations.Crm.{
    BranchSettings,
    CommandWorker,
    ConfirmWorker,
    Registry,
    SyncState,
    SyncWorker,
    Throttle
  }

  alias Delivest.Integrations.Journal
  alias Delivest.Oms.{Order, Orders}

  @permanent_errors [:branch_not_found, :unknown_provider, :missing_settings]
  @confirm_minutes 5

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
      {:ok, settings}
    else
      {:error, :info, changeset} -> {:error, Ecto.Changeset.get_change(changeset, :crm)}
      {:error, _step, changeset} -> {:error, changeset}
      error -> error
    end
  end

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

  def own_pos?(%Branch{} = branch) do
    case active_provider(branch) do
      nil -> false
      provider -> :own_pos in capabilities(provider)
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

  def enqueue_command(%Order{} = order, action, args \\ %{}) do
    args
    |> Map.merge(%{"order_id" => order.id, "branch_id" => order.branch_id, "action" => action})
    |> CommandWorker.new()
    |> Oban.insert()
  end

  defp call(%Order{crm: %{provider: provider}} = order, fun) do
    with {:ok, name, module} <- provider_module(provider),
         {:ok, settings} <- branch_settings(order.branch_id, name) do
      Journal.scope([branch_id: order.branch_id, order_id: order.id], fn ->
        Throttle.run(module.rate_limit(settings), fn -> fun.(module, settings) end)
      end)
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
