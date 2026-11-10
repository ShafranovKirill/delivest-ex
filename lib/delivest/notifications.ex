defmodule Delivest.Notifications do
  @moduledoc "Authenticated, branch-scoped customer notices and delivery intents."
  import Ecto.Query

  alias Delivest.{Features, Repo}
  alias Delivest.Notifications.{Intent, Notification, SourceRegistry}

  @channels [:in_app, :push, :sms]

  @doc "Shared customer push transport. Core transactional and account jobs retain their existing lifecycle."
  def deliver_push(subscription, payload, purpose, options \\ [])
      when purpose in [:transactional, :account, :marketing] do
    Delivest.Push.Sender.deliver(subscription, payload, options)
  end

  def publish(client_id, attrs, opts)
      when is_binary(client_id) and is_map(attrs) and is_list(opts) do
    branch_id = Keyword.get(opts, :branch_id)
    key = Keyword.get(opts, :idempotency_key)
    source_type = Keyword.get(opts, :source_type)
    source_id = Keyword.get(opts, :source_id)
    channels = Keyword.get(opts, :channels, []) |> Enum.uniq()
    cta = Map.get(attrs, :cta) || Map.get(attrs, "cta")

    with true <- valid_uuid?(client_id) and valid_uuid?(source_id),
         true <- is_binary(key) and byte_size(key) > 0,
         true <- channels != [] and Enum.all?(channels, &(&1 in @channels)),
         true <- valid_cta?(cta),
         {:ok, source} <- SourceRegistry.descriptor(source_type, source_id, client_id),
         true <- source.scope == {:branch, branch_id},
         {:ok, generation} <- Features.snapshot("notifications", {:branch, branch_id}) do
      values = %{
        idempotency_key: key,
        source_type: source_type,
        source_id: source_id,
        source_feature: source.feature,
        source_scope_key: source.scope_key,
        source_generation_franchise: source.generation.franchise,
        source_generation_branch: source.generation.branch,
        notification_generation_franchise: generation.franchise,
        notification_generation_branch: generation.branch,
        title: Map.get(attrs, :title) || Map.get(attrs, "title"),
        body: Map.get(attrs, :body) || Map.get(attrs, "body"),
        cta: cta,
        expires_at: Keyword.get(opts, :expires_at)
      }

      Features.with_enabled_many(
        [
          {source.feature, source.scope, source.generation},
          {"notifications", {:branch, branch_id}, generation}
        ],
        fn ->
          notice =
            case Repo.get_by(Notification, idempotency_key: key) do
              nil ->
                %Notification{client_id: client_id, branch_id: branch_id}
                |> Notification.changeset(values)
                |> Repo.insert!(on_conflict: :nothing, conflict_target: :idempotency_key)

                Repo.get_by!(Notification, idempotency_key: key)

              existing ->
                if existing.client_id == client_id and existing.branch_id == branch_id and
                     existing.source_type == source_type and existing.source_id == source_id and
                     existing.source_generation_franchise == source.generation.franchise and
                     existing.source_generation_branch == source.generation.branch,
                   do: existing,
                   else: Repo.rollback(:idempotency_conflict)
            end

          unless notice.client_id == client_id and notice.branch_id == branch_id and
                   notice.source_type == source_type and notice.source_id == source_id,
                 do: Repo.rollback(:idempotency_conflict)

          now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

          Enum.each(channels, fn channel ->
            {status, reason} = initial_status(channel, client_id)

            %Intent{notification_id: notice.id}
            |> Intent.changeset(%{
              channel: to_string(channel),
              status: status,
              due_at: now,
              last_error: reason
            })
            |> Repo.insert!(on_conflict: :nothing, conflict_target: [:notification_id, :channel])
          end)

          notice
        end
      )
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_notification}
    end
  end

  def publish(_, _, _), do: {:error, :invalid_notification}

  @doc "Immutable feature epochs that authorize a notice's optional send."
  def send_locks(%Notification{} = notice) do
    [
      {notice.source_feature, {:branch, notice.branch_id},
       %{franchise: notice.source_generation_franchise, branch: notice.source_generation_branch}},
      {"notifications", {:branch, notice.branch_id},
       %{
         franchise: notice.notification_generation_franchise,
         branch: notice.notification_generation_branch
       }}
    ]
  end

  def list(client_id, branch_id, device_id, cursor \\ nil) do
    with :ok <- validate_access(client_id, branch_id, device_id) do
      now = DateTime.utc_now()

      query =
        from n in Notification,
          join: intent in Intent,
          on:
            intent.notification_id == n.id and intent.channel == "in_app" and
              intent.status == "sent",
          left_join: d in "customer_notification_dismissals",
          on: d.notification_id == n.id and d.device_id == type(^device_id, Ecto.UUID),
          where:
            n.client_id == ^client_id and n.branch_id == ^branch_id and is_nil(d.notification_id),
          where: is_nil(n.expires_at) or n.expires_at > ^now,
          order_by: [desc: n.inserted_at, desc: n.id],
          limit: 31

      query =
        case decode_cursor(cursor) do
          {:ok, {at, id}} ->
            where(query, [n], n.inserted_at < ^at or (n.inserted_at == ^at and n.id < ^id))

          :none ->
            query

          :error ->
            nil
        end

      if query do
        raw = Repo.all(query)
        page = Enum.take(raw, 30)
        next = if length(raw) > 30, do: encode_cursor(List.last(page)), else: nil
        {:ok, %{items: SourceRegistry.filter_current(page, :show), next_cursor: next}}
      else
        {:error, :invalid_cursor}
      end
    end
  end

  def dismiss(client_id, branch_id, device_id, id) do
    with {:ok, notice} <- owned_notice(client_id, branch_id, device_id, id) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      Repo.insert_all(
        "customer_notification_dismissals",
        [
          %{
            notification_id: Ecto.UUID.dump!(notice.id),
            device_id: Ecto.UUID.dump!(device_id),
            inserted_at: now
          }
        ],
        on_conflict: :nothing
      )

      :ok
    end
  end

  def click(client_id, branch_id, device_id, id) do
    with {:ok, notice} <- owned_notice(client_id, branch_id, device_id, id),
         true <- current_source?(notice, :show) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      Repo.insert_all(
        "customer_notification_events",
        [
          %{
            id: Ecto.UUID.generate() |> Ecto.UUID.dump!(),
            notification_id: Ecto.UUID.dump!(notice.id),
            device_id: Ecto.UUID.dump!(device_id),
            kind: "click",
            inserted_at: now
          }
        ],
        on_conflict: :nothing
      )

      {:ok, notice.cta}
    else
      false -> {:error, :not_found}
      other -> other
    end
  end

  def consents(client_id, branch_id) do
    with :ok <- enabled_branch(branch_id), true <- valid_uuid?(client_id) do
      row =
        Repo.query!("SELECT sms, push FROM customer_notification_consents WHERE client_id=$1", [
          Ecto.UUID.dump!(client_id)
        ]).rows

      case row do
        [[sms, push]] -> {:ok, %{sms: sms, push: push}}
        _ -> {:ok, %{sms: false, push: false}}
      end
    else
      _ -> {:error, :disabled}
    end
  end

  def update_consents(client_id, branch_id, attrs) when is_map(attrs) do
    with {:ok, generation} <- Features.snapshot("notifications", {:branch, branch_id}),
         true <- valid_uuid?(client_id),
         true <- Enum.all?(Map.keys(attrs), &(&1 in ["sms", "push", :sms, :push])) do
      Features.with_enabled("notifications", {:branch, branch_id}, generation, fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [client_id])
        {:ok, current} = consents_without_gate(client_id)
        sms = Map.get(attrs, "sms", Map.get(attrs, :sms, current.sms))
        push = Map.get(attrs, "push", Map.get(attrs, :push, current.push))
        unless sms == false and is_boolean(push), do: Repo.rollback(:invalid_consents)
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        Repo.insert_all(
          "customer_notification_consents",
          [%{client_id: Ecto.UUID.dump!(client_id), sms: sms, push: push, updated_at: now}],
          on_conflict: {:replace, [:sms, :push, :updated_at]},
          conflict_target: [:client_id]
        )

        if current.push != push do
          Repo.insert_all("customer_notification_consent_events", [
            %{
              id: Ecto.UUID.generate() |> Ecto.UUID.dump!(),
              client_id: Ecto.UUID.dump!(client_id),
              channel: "push",
              old_value: current.push,
              new_value: push,
              inserted_at: now
            }
          ])
        end

        %{sms: sms, push: push}
      end)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_consents}
    end
  end

  def update_consents(_, _, _), do: {:error, :invalid_consents}

  def current_source?(%Notification{} = notice, phase) do
    SourceRegistry.current?(notice.source_type, notice.source_id, notice.client_id, phase)
  end

  def current_source?(_, _), do: false

  defp initial_status(:in_app, _), do: {"sent", nil}
  defp initial_status(:sms, _), do: {"skipped", "provider_unconfigured"}

  defp initial_status(:push, client_id) do
    if consent?(client_id, :push), do: {"pending", nil}, else: {"skipped", "no_consent"}
  end

  def consent?(client_id, kind) when kind in [:sms, :push] do
    {:ok, consents} = consents_without_gate(client_id)
    Map.fetch!(consents, kind)
  end

  defp consents_without_gate(client_id) do
    row =
      Repo.query!("SELECT sms, push FROM customer_notification_consents WHERE client_id=$1", [
        Ecto.UUID.dump!(client_id)
      ]).rows

    case row do
      [[sms, push]] -> {:ok, %{sms: sms, push: push}}
      _ -> {:ok, %{sms: false, push: false}}
    end
  end

  defp owned_notice(client_id, branch_id, device_id, id) do
    with :ok <- validate_access(client_id, branch_id, device_id),
         true <- valid_uuid?(id),
         %Notification{} = notice <-
           Repo.get_by(Notification, id: id, client_id: client_id, branch_id: branch_id) do
      {:ok, notice}
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_found}
      other -> other
    end
  end

  defp validate_access(client_id, branch_id, device_id) do
    if valid_uuid?(client_id) and valid_uuid?(device_id),
      do: enabled_branch(branch_id),
      else: {:error, :invalid_device}
  end

  defp enabled_branch(branch_id) do
    if Features.enabled?("notifications", {:branch, branch_id}),
      do: :ok,
      else: {:error, :disabled}
  end

  defp valid_uuid?(value), do: is_binary(value) and match?({:ok, _}, Ecto.UUID.cast(value))

  defp valid_cta?(nil), do: true

  defp valid_cta?(%{type: type, value: value}),
    do: valid_cta?(%{"type" => type, "value" => value})

  defp valid_cta?(%{"type" => type, "value" => value}),
    do: type in ~w(apply_promo show_bonus) and is_binary(value) and byte_size(value) <= 128

  defp valid_cta?(_), do: false

  defp encode_cursor(notice),
    do:
      Base.url_encode64(DateTime.to_iso8601(notice.inserted_at) <> "|" <> notice.id,
        padding: false
      )

  defp decode_cursor(nil), do: :none

  defp decode_cursor(value) when is_binary(value) do
    with {:ok, decoded} <- Base.url_decode64(value, padding: false),
         [at, id] <- String.split(decoded, "|", parts: 2),
         {:ok, date, _offset} <- DateTime.from_iso8601(at),
         true <- valid_uuid?(id) do
      {:ok, {date, id}}
    else
      _ -> :error
    end
  end

  defp decode_cursor(_), do: :error
end
