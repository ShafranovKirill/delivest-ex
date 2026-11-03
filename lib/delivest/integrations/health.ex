defmodule Delivest.Integrations.Health do
  import Ecto.Query

  require Logger

  alias Delivest.Integrations.{
    Crm,
    Dadata,
    Error,
    Journal,
    YandexDelivery,
    YandexEda,
    Yookassa,
    Zvonok
  }

  alias Delivest.{Fiscal, Identity}
  alias Delivest.Integrations.Health.Status
  alias Delivest.Repo

  @settings_only [:zvonok]
  @network_providers [:zvonok, :dadata, :yookassa, :yandex_eda]

  @doc """
  Whether the provider's settings are shared by every branch.

  Shared settings are managed with the `admin` permission, branch integrations
  need access to the branch and `integrations.update`.
  """
  def network?(provider), do: provider in @network_providers

  @doc """
  Whether the provider has a real API request behind its connection check.

  A check that only looks at the completeness of the saved fields is not a
  connection check: it must not be shown as a successful API call.
  """
  def checkable?(provider), do: to_string(provider) not in Enum.map(@settings_only, &to_string/1)

  @doc """
  Runs a manual connection check for a staff member.

  This is the only entry point for the button in the UI: permissions are
  checked before the external request, the health write and the journal entry.
  """
  def check_as(staff, provider, branch_id) do
    with :ok <- authorize_check(staff, provider, branch_id) do
      check(provider, branch_id)
    end
  end

  def checkable_for?(staff, provider, branch_id) do
    checkable?(provider) and authorize_check(staff, provider, branch_id) == :ok
  end

  def check(provider, branch_id) do
    if checkable?(provider) do
      with {:ok, module, settings, scope} <- source(to_string(provider), branch_id) do
        result = Journal.scope([branch_id: scope], fn -> module.health_check(settings) end)
        report(provider, scope, module, result)
      end
    else
      {:error, :not_checkable}
    end
  end

  def report(provider, branch_id, _module, :ok), do: save(provider, branch_id, :ok, nil)

  def report(provider, branch_id, module, {:error, reason}) do
    status = if kind(module, reason) == :auth, do: :auth, else: :failed
    save(provider, branch_id, status, inspect(reason))
  end

  def auth_failed(provider, branch_id, reason) do
    Logger.error("#{provider} rejected the credentials, reconnect it: #{inspect(reason)}")
    save(provider, branch_id, :auth, inspect(reason))
  end

  def warn(provider, branch_id, message) do
    now = DateTime.utc_now()

    %Status{
      provider: to_string(provider),
      branch_id: branch_id,
      status: nil,
      message: nil,
      checked_at: nil,
      warning: message,
      warning_at: now
    }
    |> Repo.insert(
      on_conflict: {:replace, [:warning, :warning_at]},
      conflict_target: [:provider, :branch_id],
      returning: true
    )
  end

  def clear_warning(provider, branch_id) do
    Status
    |> where([s], s.provider == ^to_string(provider) and not is_nil(s.warning))
    |> by_branch(branch_id)
    |> Repo.update_all(set: [warning: nil, warning_at: nil])

    :ok
  end

  def recovered(provider, branch_id) do
    Status
    |> where([s], s.provider == ^to_string(provider) and s.status in [:failed, :auth])
    |> by_branch(branch_id)
    |> Repo.update_all(set: [status: :ok, message: nil, checked_at: DateTime.utc_now()])

    :ok
  end

  @doc """
  Drops the previous connection result, keeping an independent warning.

  Called after credentials changed successfully: the old success or failure no
  longer proves anything about the new settings. A failed save must never call it.
  """
  def invalidate(provider, branch_id) do
    Status
    |> where([s], s.provider == ^to_string(provider))
    |> by_branch(branch_id)
    |> Repo.update_all(set: [status: nil, message: nil, checked_at: nil])

    :ok
  end

  def invalidate_on_change(provider, branch_id, old, new, fields) do
    if is_map(old) and is_map(new) and Map.take(old, fields) != Map.take(new, fields),
      do: invalidate(provider, branch_id),
      else: :ok
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

  @doc """
  Whether a recent failed check says the provider is down right now.

  Background workers wait instead of calling an API that has just failed, so a
  dead provider does not consume retries and queue slots. A successful call
  clears the status through `recovered/2`, and a manual check refreshes it.
  """
  def down?(provider, branch_id, max_age_seconds \\ 60) do
    case get(provider, branch_id) do
      %Status{status: :failed, checked_at: %DateTime{} = checked_at} ->
        DateTime.diff(DateTime.utc_now(), checked_at, :second) < max_age_seconds

      _ ->
        false
    end
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

  defp authorize_check(staff, provider, branch_id) do
    cond do
      not checkable?(provider) ->
        {:error, :not_checkable}

      network?(provider) ->
        if Identity.can?(staff, "admin"), do: :ok, else: {:error, :forbidden}

      true ->
        Identity.authorize(staff, "integrations.update", branch_id)
    end
  end

  defp kind(module, reason) do
    if function_exported?(module, :classify_error, 1),
      do: module.classify_error(reason),
      else: Error.classify(reason)
  end

  defp source("zvonok", _branch_id), do: {:ok, Zvonok, Zvonok.get_settings(), nil}
  defp source("yookassa", _branch_id), do: {:ok, Yookassa, Yookassa.get_settings(), nil}
  defp source("dadata", _branch_id), do: {:ok, Dadata, Dadata.get_settings(), nil}
  defp source("yandex_eda", _branch_id), do: {:ok, YandexEda, YandexEda.get_settings(), nil}

  defp source("yandex_delivery", branch_id),
    do: {:ok, YandexDelivery, YandexDelivery.settings(branch_id), branch_id}

  defp source("atol", branch_id) do
    settings = Fiscal.settings(branch_id)

    with {:ok, module} <- Fiscal.Registry.fetch(settings.provider) do
      {:ok, module, Map.get(settings, module.key()), branch_id}
    end
  end

  defp source(provider, branch_id) do
    with {:ok, _key, module} <- Crm.provider_module(provider) do
      {:ok, module, Map.get(Crm.get_branch_settings(branch_id), module.key()), branch_id}
    end
  end

  defp by_branch(query, nil), do: where(query, [s], is_nil(s.branch_id))
  defp by_branch(query, branch_id), do: where(query, [s], s.branch_id == ^branch_id)
end
