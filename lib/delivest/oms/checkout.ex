defmodule Delivest.Oms.Checkout do
  @moduledoc false

  require Logger

  alias Delivest.{Delivery, Identity, Oms}
  alias Delivest.Payments.SavedMethods
  alias Delivest.Integrations.Yookassa
  alias Delivest.Oms.Order
  alias Delivest.Repo

  @public_fields ~w(cart_id branch_id customer_phone customer_name fulfillment_type
                    payment_method cook_by comment persons cash_given address expected_total spend_points cart_revision
                    address_by_operator save_payment_method saved_payment_method_id confirmed_payment_total)

  def create(params, client, session_id, key, analytics_guest_id \\ nil) do
    request_attrs = Map.take(params, @public_fields)

    order_attrs =
      if Delivest.Franchise.SettingsStore.get().cutlery_enabled,
        do: request_attrs,
        else: Map.delete(request_attrs, "persons")

    attrs =
      order_attrs
      |> Map.put("session_id", session_id)
      |> put_client(client)

    with {:ok, payment_context} <- payment_context(request_attrs, client, key),
         {:ok, order, replay?} <-
           create_order(
             attrs,
             request_attrs,
             client,
             session_id,
             key,
             analytics_guest_id,
             payment_context
           ),
         {:ok, confirmation_url} <- begin_payment(order, not is_nil(key), payment_context) do
      unless replay?, do: remember_address(client, order)
      {:ok, order, confirmation_url}
    end
  end

  defp create_order(
         attrs,
         request_attrs,
         client,
         session_id,
         key,
         analytics_guest_id,
         payment_context
       ) do
    opts = [
      update_client: false,
      guest_session_access: is_nil(client),
      online: attrs["payment_method"] == "online",
      public_session_id: session_id,
      public_guest: is_nil(client),
      authenticated_client_id: client && client.id,
      analytics_guest_id: analytics_guest_id,
      cart_revision: attrs["cart_revision"],
      public_checkout: true,
      payment_context: payment_context,
      confirmed_payment_total:
        if(payment_context && payment_context["saved_payment_method_id"],
          do: attrs["confirmed_payment_total"]
        )
    ]

    preflight = fn ->
      with {:ok, branch} <- fetch_public_branch(attrs["branch_id"]),
           :ok <- ensure_accepting(branch),
           :ok <- ensure_client_auth(client),
           :ok <- ensure_delivery_address_settings(attrs) do
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

  defp payment_context(params, client, key) do
    save? = params["save_payment_method"] == true
    method_id = params["saved_payment_method_id"]

    cond do
      params["save_payment_method"] not in [nil, false, true] ->
        {:error, :saved_payment_method_conflict}

      not save? and is_nil(method_id) ->
        {:ok, nil}

      save? and not is_nil(method_id) ->
        {:error, :saved_payment_method_conflict}

      is_nil(client) ->
        {:error, :client_auth_required}

      params["payment_method"] != "online" ->
        {:error, :saved_payment_method_conflict}

      existing_replay?(params, client, key) ->
        {:ok, nil}

      not SavedMethods.enabled?() ->
        {:error, :saved_payment_methods_disabled}

      save? ->
        {:ok,
         %{
           "save_payment_method" => true,
           "shop_id" => Yookassa.get_settings().shop_id,
           "client_id" => client.id,
           "consent_version" => 1,
           "consented_at" => DateTime.utc_now(:microsecond) |> DateTime.to_iso8601()
         }}

      is_nil(params["expected_total"]) or is_nil(params["confirmed_payment_total"]) ->
        {:error, :expected_total_required}

      true ->
        shop_id = Yookassa.get_settings().shop_id

        case SavedMethods.active(client.id, shop_id, method_id) do
          nil ->
            if existing_replay?(params, client, key),
              do: {:ok, nil},
              else: {:error, :saved_payment_method_not_found}

          _ ->
            {:ok,
             %{
               "saved_payment_method_id" => method_id,
               "shop_id" => shop_id,
               "client_id" => client.id
             }}
        end
    end
  end

  defp existing_replay?(_params, _client, nil), do: false

  defp existing_replay?(params, client, key) do
    with {:ok, branch_id} <- cast_branch_id(params["branch_id"]),
         %Order{} = order <-
           Repo.get_by(Order,
             branch_id: branch_id,
             idempotency_key: key,
             idempotency_owner: "client:#{client.id}"
           ) do
      order.idempotency_fingerprint == fingerprint(params, client)
    else
      _ -> false
    end
  end

  defp ensure_delivery_address_settings(%{"fulfillment_type" => "delivery"} = attrs) do
    settings = Delivery.get_settings(attrs["branch_id"])
    operator? = attrs["address_by_operator"] in [true, "true", "1", 1]
    address = attrs["address"] || %{}

    cond do
      operator? and (settings.map_address != false or settings.operator_address != true) ->
        {:error, :address_by_operator_unavailable}

      settings.address_mode_set and settings.map_address != false and
          not coordinates?(address) ->
        {:error, :no_coordinates}

      settings.address_mode_set and not operator? and
          not complete_address?(address, settings.map_address == false) ->
        {:error, :incomplete_delivery_address}

      true ->
        :ok
    end
  end

  defp ensure_delivery_address_settings(_attrs), do: :ok

  defp coordinates?(address) when is_map(address) do
    latitude = Map.get(address, "latitude") || Map.get(address, :latitude)
    longitude = Map.get(address, "longitude") || Map.get(address, :longitude)

    is_number(latitude) and latitude >= -90 and latitude <= 90 and
      is_number(longitude) and longitude >= -180 and longitude <= 180
  end

  defp coordinates?(_address), do: false

  defp complete_address?(address, manual?) when is_map(address) do
    fields =
      if manual?, do: [{"street", :street}], else: [{"street", :street}, {"house", :house}]

    Enum.all?(fields, fn {field, atom} ->
      value = Map.get(address, field) || Map.get(address, atom)
      is_binary(value) and String.trim(value) != ""
    end)
  end

  defp complete_address?(_address, _manual?), do: false

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
    address = address |> Map.from_struct() |> Map.put(:house, Delivest.Geo.House.line(address))
    Identity.remember_client_address(client.id, address)
  end

  defp remember_address(_client, _order), do: :ok

  defp ensure_accepting(branch) do
    case Delivest.Intake.status(branch.id) do
      %{mode: :paused} = status -> {:error, {:branch_paused, status}}
      _status -> :ok
    end
  end

  defp begin_payment(%Order{awaiting_payment: true} = order, keyed?, context) do
    case Delivest.Payments.Online.start(order) do
      {:ok, url} ->
        {:ok, url}

      {:error, reason} ->
        Logger.error(
          "online payment of order #{order.number} was not started: #{inspect(reason)}"
        )

        unless keyed? or not is_nil(context), do: Delivest.Payments.Online.abandon(order)
        {:error, :payment_unavailable}
    end
  end

  defp begin_payment(_order, _keyed?, _context), do: {:ok, nil}

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
