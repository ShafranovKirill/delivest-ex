defmodule Delivest.Integrations.Crm do
  alias Delivest.Identity
  alias Delivest.Identity.Branch
  alias Delivest.Integrations.Crm.{BranchSettings, Registry, SyncWorker, Throttle}
  alias Delivest.Oms.{Order, Orders}

  @permanent_errors [:branch_not_found, :unknown_provider, :missing_settings]

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
           Identity.update_branch(staff, branch, %{}, %{"crm" => attrs}) do
      {:ok, settings}
    else
      {:error, :info, changeset} -> {:error, Ecto.Changeset.get_change(changeset, :crm)}
      {:error, _step, changeset} -> {:error, changeset}
      error -> error
    end
  end

  def create_order(attrs, provider, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:crm, %{provider: to_string(provider), status: "pending"})
      |> Keyword.put(:after_insert, &enqueue_sync/1)

    attrs
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.put("status", "crm")
    |> Orders.create_order(opts)
  end

  def deliver(%Order{crm: %{provider: provider}} = order) do
    with {:ok, name, module} <- provider_module(provider),
         {:ok, settings} <- branch_settings(order.branch_id, name) do
      Throttle.run(module.rate_limit(settings), fn -> module.deliver_order(order, settings) end)
    end
  end

  def deliver(_order), do: {:error, :unknown_provider}

  def classify_error(_order, reason) when reason in @permanent_errors, do: :permanent

  def classify_error(%Order{crm: %{provider: provider}}, reason) do
    case provider_module(provider) do
      {:ok, _name, module} -> module.classify_error(reason)
      _ -> :permanent
    end
  end

  defp enqueue_sync(multi) do
    Oban.insert(multi, :crm_job, fn %{order: order} ->
      SyncWorker.new(%{"order_id" => order.id, "branch_id" => order.branch_id})
    end)
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
