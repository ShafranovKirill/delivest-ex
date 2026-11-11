defmodule Delivest.Oms.Checkout do
  @moduledoc false

  require Logger

  alias Delivest.{Identity, Oms}
  alias Delivest.Oms.Order

  @public_fields ~w(cart_id branch_id customer_phone customer_name fulfillment_type
                    payment_method cook_by comment persons cash_given address expected_total spend_points cart_revision)

  def create(params, client, session_id, key, analytics_guest_id \\ nil) do
    request_attrs = Map.take(params, @public_fields)

    attrs =
      request_attrs
      |> Map.put("session_id", session_id)
      |> put_client(client)

    with {:ok, order, replay?} <-
           create_order(attrs, request_attrs, client, session_id, key, analytics_guest_id),
         {:ok, confirmation_url} <- begin_payment(order, not is_nil(key)) do
      unless replay?, do: remember_address(client, order)
      {:ok, order, confirmation_url}
    end
  end

  defp create_order(attrs, request_attrs, client, session_id, key, analytics_guest_id) do
    opts = [
      update_client: false,
      guest_session_access: is_nil(client),
      online: attrs["payment_method"] == "online",
      public_session_id: session_id,
      public_guest: is_nil(client),
      authenticated_client_id: client && client.id,
      analytics_guest_id: analytics_guest_id,
      cart_revision: attrs["cart_revision"]
    ]

    preflight = fn ->
      with {:ok, branch} <- fetch_public_branch(attrs["branch_id"]),
           :ok <- ensure_accepting(branch),
           :ok <- ensure_client_auth(client) do
        ensure_payment_method(branch, attrs["payment_method"])
      end
    end

    result =
      if key do
        with :ok <- ensure_keyed_session(client, session_id),
             {:ok, branch_id} <- cast_branch_id(attrs["branch_id"]) do
          owner = if client, do: "client:#{client.id}", else: "guest:#{digest(session_id)}"
          idempotency = %{owner: owner, key: key, fingerprint: fingerprint(request_attrs, client)}

          Oms.create_order(
            Map.put(attrs, "branch_id", branch_id),
            opts ++ [idempotency: idempotency, preflight: preflight]
          )
        end
      else
        with :ok <- preflight.(), do: Oms.create_order(attrs, opts)
      end

    case result do
      {:ok, order, :replay} -> {:ok, order, true}
      {:ok, order} -> {:ok, order, false}
      other -> other
    end
  end

  defp ensure_keyed_session(nil, nil), do: {:error, :cart_not_found}
  defp ensure_keyed_session(_client, _session_id), do: :ok

  defp cast_branch_id(nil), do: {:error, :branch_id_required}

  defp cast_branch_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :branch_not_found}
    end
  end

  defp fingerprint(attrs, client) do
    attrs
    |> then(&if(client, do: Map.delete(&1, "customer_phone"), else: &1))
    |> canonical()
    |> :erlang.term_to_binary()
    |> digest()
  end

  defp digest(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp canonical(map) when is_map(map),
    do: map |> Enum.map(fn {key, value} -> {to_string(key), canonical(value)} end) |> Enum.sort()

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(value), do: value

  defp put_client(attrs, nil), do: Map.delete(attrs, "spend_points")

  defp put_client(attrs, client),
    do: Map.merge(attrs, %{"client_id" => client.id, "customer_phone" => client.phone})

  defp remember_address(nil, _order), do: :ok

  defp remember_address(client, %{
         fulfillment_type: :delivery,
         address: %{street: street} = address
       })
       when is_binary(street) do
    Identity.remember_client_address(client.id, Map.from_struct(address))
  end

  defp remember_address(_client, _order), do: :ok

  defp ensure_accepting(branch) do
    case Delivest.Intake.status(branch.id) do
      %{mode: :paused} = status -> {:error, {:branch_paused, status}}
      _status -> :ok
    end
  end

  defp begin_payment(%Order{awaiting_payment: true} = order, keyed?) do
    case Delivest.Payments.Online.start(order) do
      {:ok, url} ->
        {:ok, url}

      {:error, reason} ->
        Logger.error(
          "online payment of order #{order.number} was not started: #{inspect(reason)}"
        )

        unless keyed?, do: Delivest.Payments.Online.abandon(order)
        {:error, :payment_unavailable}
    end
  end

  defp begin_payment(_order, _keyed?), do: {:ok, nil}

  defp ensure_client_auth(client) do
    if Delivest.Franchise.get_settings().client_auth_required == true and is_nil(client),
      do: {:error, :client_auth_required},
      else: :ok
  end

  defp ensure_payment_method(_branch, nil), do: :ok

  defp ensure_payment_method(branch, method) do
    if method in Enum.map(Delivest.Payments.enabled_methods(branch), &to_string/1),
      do: :ok,
      else: {:error, :payment_method_disabled}
  end

  defp fetch_public_branch(nil), do: {:error, :branch_id_required}

  defp fetch_public_branch(branch_id) do
    case Identity.get_branch(branch_id) do
      {:ok, %{is_active: true} = branch} -> {:ok, branch}
      _ -> {:error, :branch_not_found}
    end
  end
end
