defmodule Delivest.Identity.ClientAuth do
  alias Delivest.Identity.{Client, Clients, Phone, PhoneConfirmation, PhoneConfirmations}

  @auto_confirm Application.compile_env(:delivest, :auto_confirm_phone, false)

  @spec start(term(), String.t() | nil) ::
          {:ok, PhoneConfirmation.t(), String.t()} | {:error, term()}
  def start(phone, session_id) do
    with {:ok, phone} <- validate_phone(phone),
         {:ok, %{call_id: call_id, call_number: call_number}} <- request_call(phone),
         {:ok, confirmation} <-
           PhoneConfirmations.create(%{phone: phone, session_id: session_id, call_id: call_id}),
         :ok <- auto_confirm(call_id, phone) do
      {:ok, confirmation, call_number}
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
    with {:ok, phone} <- PhoneConfirmations.consume(confirmation_id, session_id),
         {:ok, client} <- Clients.fetch_or_create_by_phone(phone) do
      ensure_active(client)
    end
  end

  @spec fetch_client(String.t()) :: {:ok, Client.t()} | {:error, :not_found | :client_blocked}
  def fetch_client(client_id) do
    case Clients.get_active_client(client_id) do
      nil -> {:error, :not_found}
      client -> ensure_active(client)
    end
  end

  def subscribe(confirmation_id),
    do: Phoenix.PubSub.subscribe(Delivest.PubSub, PhoneConfirmations.topic(confirmation_id))

  defp notify_confirmed(id),
    do: Phoenix.PubSub.broadcast(Delivest.PubSub, PhoneConfirmations.topic(id), :phone_confirmed)

  if @auto_confirm do
    defp request_call(_phone),
      do: {:ok, %{call_id: Ecto.UUID.generate(), call_number: "70000000000"}}

    defp auto_confirm(call_id, phone), do: confirm_call(call_id, phone)
  else
    defp request_call(phone), do: Delivest.Integrations.Zvonok.request_call(phone)

    defp auto_confirm(_call_id, _phone), do: :ok
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
