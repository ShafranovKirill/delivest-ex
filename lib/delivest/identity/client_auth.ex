defmodule Delivest.Identity.ClientAuth do
  alias Delivest.Integrations.Zvonok
  alias Delivest.Identity.{Client, Clients, Phone, PhoneConfirmation, PhoneConfirmations}

  @auto_confirm Application.compile_env(:delivest, :auto_confirm_phone, false)

  @spec start(term(), String.t() | nil) ::
          {:ok, PhoneConfirmation.t(), String.t() | nil} | {:error, term()}
  def start(phone, session_id) do
    with :ok <- ensure_enabled(),
         {:ok, phone} <- validate_phone(phone),
         {:ok, confirmation} <- confirmation(phone, session_id) do
      {:ok, confirmation, confirmation.call_number}
    end
  end

  defp confirmation(phone, session_id) do
    case PhoneConfirmations.reusable(phone, session_id) do
      %PhoneConfirmation{} = confirmation -> {:ok, confirmation}
      nil -> request_new(phone, session_id)
    end
  end

  defp request_new(phone, session_id) do
    with :ok <- PhoneConfirmations.throttle(phone, session_id),
         {:ok, call} <- request_call(phone, Zvonok.login_call_mode()),
         {:ok, confirmation} <-
           PhoneConfirmations.create(Map.merge(call, %{phone: phone, session_id: session_id})),
         :ok <- auto_confirm(confirmation) do
      {:ok, confirmation}
    end
  end

  @spec confirm_code(String.t(), String.t() | nil, term()) ::
          :ok | {:error, :not_found | :attempts_exhausted | {:invalid_code, non_neg_integer()}}
  def confirm_code(confirmation_id, session_id, code) do
    with :ok <- ensure_enabled(),
         {:ok, id} <- PhoneConfirmations.verify_code(confirmation_id, session_id, code) do
      notify_confirmed(id)
      :ok
    end
  end

  @spec confirm_call(term(), term()) :: :ok | {:error, :not_found}
  def confirm_call(call_id, phone) when is_binary(call_id) do
    with phone when is_binary(phone) <- Phone.normalize(phone),
         {:ok, ids} <- PhoneConfirmations.confirm(call_id, phone) do
      Enum.each(ids, &notify_confirmed/1)
    else
      _ -> {:error, :not_found}
    end
  end

  def confirm_call(_call_id, _phone), do: {:error, :not_found}

  @spec complete(String.t(), String.t() | nil) ::
          {:ok, Client.t()}
          | {:error, :pending | :not_found | :client_blocked | Ecto.Changeset.t()}
  def complete(confirmation_id, session_id) do
    with :ok <- ensure_enabled(),
         {:ok, phone} <- PhoneConfirmations.consume(confirmation_id, session_id),
         {:ok, client} <- Clients.fetch_or_create_by_phone(phone) do
      ensure_active(client)
    end
  end

  @spec fetch_client(String.t()) :: {:ok, Client.t()} | {:error, :not_found | :client_blocked}
  def fetch_client(client_id) do
    with :ok <- ensure_enabled() do
      case Clients.get_active_client(client_id) do
        nil -> {:error, :not_found}
        client -> ensure_active(client)
      end
    end
  end

  def enabled?, do: Delivest.Integrations.Zvonok.enabled?()

  defp ensure_enabled, do: if(enabled?(), do: :ok, else: {:error, :auth_disabled})

  def subscribe(confirmation_id),
    do: Phoenix.PubSub.subscribe(Delivest.PubSub, PhoneConfirmations.topic(confirmation_id))

  defp notify_confirmed(id),
    do: Phoenix.PubSub.broadcast(Delivest.PubSub, PhoneConfirmations.topic(id), :phone_confirmed)

  defp request_call(phone, :flash) do
    with {:ok, %{call_id: call_id, code: code}} <- Zvonok.request_flash(phone),
         do: {:ok, %{mode: :flash, call_id: call_id, code: code}}
  end

  defp request_call(phone, _inbound) do
    with {:ok, %{call_id: call_id, call_number: call_number}} <- inbound_call(phone),
         do: {:ok, %{mode: :inbound, call_id: call_id, call_number: call_number}}
  end

  defp auto_confirm(%PhoneConfirmation{mode: :flash}), do: :ok
  defp auto_confirm(%PhoneConfirmation{} = confirmation), do: auto_confirm_call(confirmation)

  if @auto_confirm do
    defp inbound_call(_phone),
      do: {:ok, %{call_id: Ecto.UUID.generate(), call_number: "70000000000"}}

    defp auto_confirm_call(%PhoneConfirmation{call_id: call_id, phone: phone}),
      do: confirm_call(call_id, phone)
  else
    defp inbound_call(phone), do: Zvonok.request_call(phone)

    defp auto_confirm_call(_confirmation), do: :ok
  end

  defp validate_phone(phone) do
    case Phone.normalize(phone) do
      nil -> {:error, :invalid_phone}
      phone -> {:ok, phone}
    end
  end

  defp ensure_active(%Client{status: :blocked}), do: {:error, :client_blocked}
  defp ensure_active(%Client{} = client), do: {:ok, client}
end
