defmodule Delivest.Integrations.Health do
  import Ecto.Query

  require Logger

  alias Delivest.Integrations.{Crm, Dadata, Error, Journal, YandexDelivery, YandexEda, Zvonok}
  alias Delivest.Integrations.Health.Status
  alias Delivest.Repo

  def check(provider, branch_id) do
    with {:ok, module, settings, scope} <- source(to_string(provider), branch_id) do
      result = Journal.scope([branch_id: scope], fn -> module.health_check(settings) end)
      report(provider, scope, module, result)
    end
  end

  def report(provider, branch_id, _module, :ok) do
    case get(provider, branch_id) do
      %Status{status: :warning} = status -> {:ok, status}
      _status -> save(provider, branch_id, :ok, nil)
    end
  end

  def report(provider, branch_id, module, {:error, reason}) do
    status = if kind(module, reason) == :auth, do: :auth, else: :failed
    save(provider, branch_id, status, inspect(reason))
  end

  def auth_failed(provider, branch_id, reason) do
    Logger.error("#{provider} rejected the credentials, reconnect it: #{inspect(reason)}")
    save(provider, branch_id, :auth, inspect(reason))
  end

  def warn(provider, branch_id, message), do: save(provider, branch_id, :warning, message)

  def clear_warning(provider, branch_id) do
    Status
    |> where([s], s.provider == ^to_string(provider) and s.status == :warning)
    |> by_branch(branch_id)
    |> Repo.update_all(set: [status: :ok, message: nil, checked_at: DateTime.utc_now()])

    :ok
  end

  def recovered(provider, branch_id) do
    Status
    |> where([s], s.provider == ^to_string(provider) and s.status in [:failed, :auth])
    |> by_branch(branch_id)
    |> Repo.update_all(set: [status: :ok, message: nil, checked_at: DateTime.utc_now()])

    :ok
  end

  def get(provider, branch_id) do
    Status
    |> where([s], s.provider == ^to_string(provider))
    |> by_branch(branch_id)
    |> Repo.one()
  end

  def for_branch(branch_id) do
    Status
    |> where([s], s.branch_id == ^branch_id or is_nil(s.branch_id))
    |> Repo.all()
    |> Map.new(&{&1.provider, &1})
  end

  defp save(provider, branch_id, status, message) do
    %Status{
      provider: to_string(provider),
      branch_id: branch_id,
      status: status,
      message: message,
      checked_at: DateTime.utc_now()
    }
    |> Repo.insert(
      on_conflict: {:replace, [:status, :message, :checked_at]},
      conflict_target: [:provider, :branch_id],
      returning: true
    )
  end

  defp kind(module, reason) do
    if function_exported?(module, :classify_error, 1),
      do: module.classify_error(reason),
      else: Error.classify(reason)
  end

  defp source("zvonok", _branch_id), do: {:ok, Zvonok, Zvonok.get_settings(), nil}
  defp source("dadata", _branch_id), do: {:ok, Dadata, Dadata.get_settings(), nil}
  defp source("yandex_eda", _branch_id), do: {:ok, YandexEda, YandexEda.get_settings(), nil}

  defp source("yandex_delivery", branch_id),
    do: {:ok, YandexDelivery, YandexDelivery.settings(branch_id), branch_id}

  defp source(provider, branch_id) do
    with {:ok, _key, module} <- Crm.provider_module(provider) do
      {:ok, module, Map.get(Crm.get_branch_settings(branch_id), module.key()), branch_id}
    end
  end

  defp by_branch(query, nil), do: where(query, [s], is_nil(s.branch_id))
  defp by_branch(query, branch_id), do: where(query, [s], s.branch_id == ^branch_id)
end
