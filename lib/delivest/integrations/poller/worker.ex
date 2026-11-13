defmodule Delivest.Integrations.Poller.Worker do
  use Oban.Worker,
    queue: :polling,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:poller, :target], states: [:available, :scheduled]]

  alias Delivest.Integrations.Poller

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"poller" => key, "target" => target} = args}) do
    with {:ok, module} <- Poller.fetch(key),
         :ok <- available?(module, target, key, args) do
      result =
        if key in ["crm_catalog", "crm_stops"],
          do: module.poll(target, args["generation"]),
          else: module.poll(target)

      case result do
        :done ->
          :ok

        {:ok, _result} ->
          :ok

        :more ->
          next(module, target, module.interval(), args)

        {:snooze, seconds} ->
          next(module, target, seconds, args)

        {:error, {:incomplete, reason}} when key == "yookassa_reconcile" ->
          {:cancel, "yookassa reconciliation incomplete: #{reason}"}

        {:error, :disabled} ->
          {:cancel, :disabled}

        {:error, :settings_changed} ->
          {:cancel, :disabled}

        {:error, _reason} = error ->
          error
      end
    else
      {:error, :disabled} -> {:cancel, :disabled}
      error -> error
    end
  end

  def perform(%Oban.Job{args: %{"poller" => key}}) do
    with {:ok, module} <- Poller.fetch(key), do: Poller.enqueue_all(module)
  end

  defp next(module, target, seconds, args) do
    if target not in module.targets() or
         (module.key() in [:crm_catalog, :crm_stops] and
            Delivest.Integrations.Crm.get_branch_settings(target).generation != args["generation"]) do
      {:cancel, :disabled}
    else
      {:ok, _job} = args |> new(schedule_in: seconds) |> Oban.insert()
      :ok
    end
  end

  defp available?(module, target, "crm_catalog", args) do
    generation = get_in(args, ["generation"])

    if is_integer(generation) and target in module.targets() and
         Delivest.Integrations.Availability.crm_allowed?(target, :frontpad, :catalog, generation),
       do: :ok,
       else: {:error, :disabled}
  end

  defp available?(module, target, "crm_stops", args) do
    current = Delivest.Integrations.Crm.get_branch_settings(target)

    if is_integer(args["generation"]) and args["generation"] == current.generation and
         target in module.targets(),
       do: :ok,
       else: {:error, :disabled}
  end

  defp available?(module, target, _key, _args) do
    if target in module.targets(), do: :ok, else: {:error, :disabled}
  end
end
