defmodule Delivest.Integrations.Crm do
  alias Delivest.Identity
  alias Delivest.Identity.Branch
  alias Delivest.Integrations.Crm.{BranchSettings, SyncWorker, Throttle}
  alias Delivest.Integrations.Frontpad
  alias Delivest.Oms.{Order, Orders}

  @providers %{frontpad: Frontpad}
  @permanent_errors [:branch_not_found, :unknown_provider, :missing_settings]

  def providers,
    do: Enum.map(BranchSettings.providers(), &{&1, Map.fetch!(@providers, &1).name()})

  def active_provider(%Branch{info: %{crm: %BranchSettings{} = settings}}),
    do: BranchSettings.active_provider(settings)

  def active_provider(_branch), do: nil

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

  defp provider_module(provider) do
    case Enum.find(@providers, fn {name, _module} -> to_string(name) == provider end) do
      {name, module} -> {:ok, name, module}
      nil -> {:error, :unknown_provider}
    end
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
