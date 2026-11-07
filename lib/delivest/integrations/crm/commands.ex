defmodule Delivest.Integrations.Crm.Commands do
  import Ecto.Query

  alias Delivest.{Audit, Repo}
  alias Delivest.Identity.Staff
  alias Delivest.Integrations.Crm.{Command, CommandWorker}
  alias Delivest.Oms.Order

  @terminal ["succeeded", "resolved"]

  def enqueue(%Order{crm: %{provider: provider}} = order, action, args, event_id) do
    Repo.transaction(fn ->
      Repo.query!(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        ["crm:#{order.id}:#{provider}"]
      )

      existing = event_id && Repo.get_by(Command, event_id: event_id, action: action)

      if existing do
        Repo.get(Oban.Job, existing.job_id) || existing
      else
        attrs = %{
          order_id: order.id,
          provider: to_string(provider),
          action: action,
          args: args,
          event_id: event_id
        }

        command = %Command{} |> Command.changeset(attrs) |> Repo.insert!()

        job =
          args
          |> Map.merge(%{
            "order_id" => order.id,
            "branch_id" => order.branch_id,
            "action" => action,
            "command_id" => command.id
          })
          |> CommandWorker.new()
          |> Oban.insert!()

        command |> Command.changeset(%{job_id: job.id}) |> Repo.update!()
        job
      end
    end)
  end

  def claim(%Oban.Job{args: %{"command_id" => id}, attempt: attempt, id: job_id}) do
    Repo.transaction(fn ->
      command = Repo.get!(Command, id)
      lock(command)
      command = Repo.get!(Command, id)

      cond do
        is_integer(job_id) and command.job_id != job_id ->
          {:blocked, "stale_job"}

        command.status in @terminal ->
          :done

        command.status in ["unknown", "failed"] ->
          {:blocked, command.status}

        command.status == "running" and command.claim_attempt == attempt ->
          :busy

        command.status == "running" ->
          update!(command, %{status: "unknown", last_error: "worker stopped after remote claim"})

          Audit.record(:system, "order.crm_command_unknown", Repo.get!(Order, command.order_id),
            metadata: %{command_id: command.id, reason: "worker_stopped_after_claim"}
          )

          {:blocked, "unknown"}

        predecessor?(command) ->
          :busy

        order_state(command) == :waiting ->
          :waiting

        order_state(command) == :invalid ->
          update!(command, %{status: "failed", last_error: "order deleted or provider changed"})
          {:blocked, "order_invalid"}

        true ->
          token = Ecto.UUID.generate()

          update!(command, %{
            status: "running",
            claim_token: token,
            claim_attempt: attempt,
            claimed_at: DateTime.utc_now()
          })

          {:claimed, command, token}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  def claim(%Oban.Job{} = job), do: bridge_legacy(job)

  def finish(%Command{id: id}, token, status, reason \\ nil) do
    {count, _} =
      Repo.update_all(
        from(c in Command,
          where: c.id == ^id and c.status == "running" and c.claim_token == ^token
        ),
        set: [
          status: status,
          claim_token: nil,
          last_error: reason,
          updated_at: DateTime.utc_now()
        ]
      )

    if count == 1, do: :ok, else: {:error, :claim_lost}
  end

  def list(limit \\ 100) when is_integer(limit) and limit in 1..500 do
    Repo.all(
      from(c in Command,
        left_join: o in Order,
        on: o.id == c.order_id,
        where: c.status in ["pending", "running", "unknown", "failed"],
        order_by: [asc: c.id],
        limit: ^limit,
        select: %{
          id: c.id,
          order_id: c.order_id,
          provider: c.provider,
          action: c.action,
          status: c.status,
          claimed_at: c.claimed_at,
          inserted_at: c.inserted_at,
          updated_at: c.updated_at,
          initial_crm_status: fragment("?->>'status'", o.crm)
        }
      )
    )
  end

  def resolve(id, actor_id, reason, decision, confirmed_absent \\ false)
      when decision in [:confirmed_effect, :skip, :retry] do
    with {:ok, actor} <- operator(actor_id, reason),
         %Command{} = command <- Repo.get(Command, id),
         :ok <- allowed_decision(command, decision, confirmed_absent) do
      Repo.transaction(fn ->
        lock(command)
        command = Repo.get!(Command, id)

        case allowed_decision(command, decision, confirmed_absent) do
          :ok -> :ok
          {:error, why} -> Repo.rollback(why)
        end

        if active_job?(command), do: Repo.rollback(:active_job)

        status = if decision == :retry, do: "pending", else: "resolved"

        update!(command, %{
          status: status,
          resolved_at: DateTime.utc_now(),
          last_error: "operator #{decision}"
        })

        Audit.record(actor, "order.crm_command_#{decision}", Repo.get!(Order, command.order_id),
          metadata: %{command_id: command.id, reason: reason}
        )

        if decision == :retry do
          job =
            command.args
            |> Map.merge(%{
              "order_id" => command.order_id,
              "action" => command.action,
              "command_id" => command.id
            })
            |> CommandWorker.new()
            |> Oban.insert!()

          command
          |> Command.changeset(%{
            job_id: job.id,
            claim_attempt: nil,
            claim_token: nil,
            claimed_at: nil
          })
          |> Repo.update!()
        end

        :ok
      end)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp allowed_decision(%Command{status: status}, :retry, true)
       when status in ["unknown", "failed"], do: :ok

  defp allowed_decision(%Command{status: status}, decision, _)
       when status in ["unknown", "failed"] and decision in [:confirmed_effect, :skip], do: :ok

  defp allowed_decision(%Command{status: "running"}, _, _), do: {:error, :active_claim}
  defp allowed_decision(_, :retry, _), do: {:error, :confirmed_absent_required}
  defp allowed_decision(_, _, _), do: {:error, :not_resolvable}

  defp operator(actor_id, reason) when is_binary(reason) do
    if String.trim(reason) == "",
      do: {:error, :actor_and_reason_required},
      else: fetch_operator(actor_id)
  end

  defp operator(_, _), do: {:error, :actor_and_reason_required}

  defp fetch_operator(actor_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(actor_id),
         %Staff{} = actor <- Repo.get(Staff, uuid) do
      actor = Repo.preload(actor, :role)

      if (is_nil(actor.deleted_at) and actor.role) && "admin" in actor.role.permissions,
        do: {:ok, actor},
        else: {:error, :forbidden}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp bridge_legacy(%Oban.Job{id: id, attempt: attempt}) when is_integer(id) do
    case Repo.get_by(Command, job_id: id) do
      %Command{} = command ->
        claim(%Oban.Job{id: id, args: %{"command_id" => command.id}, attempt: attempt})

      nil ->
        {:blocked, "legacy_untracked"}
    end
  end

  defp bridge_legacy(_), do: {:blocked, "legacy_untracked"}

  defp active_job?(command) do
    command_id_json = Jason.encode!(%{"command_id" => command.id})

    Repo.exists?(
      from(j in Oban.Job,
        where:
          j.worker == "Delivest.Integrations.Crm.CommandWorker" and
            (j.id == ^command.job_id or fragment("? @> ?::jsonb", j.args, ^command_id_json)) and
            j.state in ["available", "scheduled", "retryable", "executing"]
      )
    )
  end

  defp predecessor?(command) do
    Repo.exists?(
      from(c in Command,
        where:
          c.order_id == ^command.order_id and c.provider == ^command.provider and
            c.id < ^command.id and c.status not in ^@terminal
      )
    )
  end

  defp order_state(command) do
    case Repo.get(Order, command.order_id) do
      %Order{deleted_at: nil, crm: %{status: "sent", provider: provider}}
      when provider == command.provider ->
        :sent

      %Order{deleted_at: nil, crm: %{provider: provider}}
      when provider == command.provider ->
        :waiting

      _ ->
        :invalid
    end
  end

  defp lock(command) do
    %{rows: [[locked?]]} =
      Repo.query!(
        "SELECT pg_try_advisory_xact_lock(hashtextextended($1, 0))",
        ["crm:#{command.order_id}:#{command.provider}"]
      )

    if not locked?, do: Repo.rollback(:busy)
  end

  defp update!(command, attrs), do: command |> Command.changeset(attrs) |> Repo.update!()
end
