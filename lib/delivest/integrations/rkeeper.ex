defmodule Delivest.Integrations.Rkeeper do
  @behaviour Delivest.Integrations.Crm.Provider

  import Ecto.Query

  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.SyncState
  alias Delivest.Integrations.Rkeeper.{Api, OrderPayload}
  alias Delivest.Net.{Modifiers, ProductCrmIds}
  alias Delivest.Oms.Order
  alias Delivest.Repo

  @statuses %{
    "new" => :created,
    "created" => :created,
    "accepted" => :accepted,
    "confirmed" => :accepted,
    "cooking" => :preparing,
    "inprogress" => :preparing,
    "ready" => :ready,
    "cooked" => :ready,
    "ondelivery" => :delivering,
    "onway" => :delivering,
    "delivering" => :delivering,
    "delivered" => :completed,
    "completed" => :completed,
    "closed" => :completed,
    "cancelled" => :cancelled,
    "canceled" => :cancelled,
    "voided" => :cancelled
  }

  @impl true
  def key, do: :rkeeper

  @impl true
  def name, do: "r_keeper"

  @impl true
  def settings_schema, do: Delivest.Integrations.Rkeeper.Settings

  @impl true
  def configured?(%{object_id: id}) when is_binary(id) and id != "", do: Api.configured?()
  def configured?(_settings), do: false

  @impl true
  def idempotent?, do: false

  @impl true
  def capabilities, do: [:cancel, :update_comment, :own_pos, :delivery]

  @impl true
  def status_map(_settings), do: @statuses

  def status_for(code) when is_binary(code),
    do: Map.get(@statuses, code |> String.downcase() |> String.replace(~r/[\s_-]/, ""))

  def status_for(_code), do: nil

  @impl true
  def deliver_order(order, settings) do
    with :ok <- available(settings),
         {:ok, payload} <- OrderPayload.build(order, settings, articles(order)) do
      case Api.task(settings, "CreateOrder", %{order: payload}) do
        {:ok, response} -> delivery(response)
        {:pending, task_guid} -> {:pending, task_guid}
        error -> error
      end
    end
  end

  def delivery(%{"order" => %{"orderGuid" => guid}}), do: {:ok, %{external_id: guid}}
  def delivery(%{"orderGuid" => guid}) when is_binary(guid), do: {:ok, %{external_id: guid}}
  def delivery(response), do: {:error, {:rkeeper, "no orderGuid: #{inspect(response)}"}}

  @impl true
  def cancel_order(order, _reason, settings) do
    params = %{orderGuid: order.crm.external_id, voidReasonCode: void_reason(settings)}

    with {:ok, _response} <- Api.task(settings, "CancelOrder", params), do: :ok
  end

  @impl true
  def update_order(order, changes, settings) do
    fields =
      if Map.has_key?(changes, "comment"),
        do: [%{name: "Comment", value: order.comment || ""}],
        else: []

    case fields do
      [] ->
        :ok

      fields ->
        with {:ok, _response} <-
               Api.task(settings, "PatchOrder", %{
                 orderGuid: order.crm.external_id,
                 fields: fields
               }),
             do: :ok
    end
  end

  @impl true
  def dictionaries(settings) do
    with {:ok, response} <- Api.task(settings, "GetVoidReasons") do
      {:ok, %{void_reasons: list(response, ["voidReasons", "reasons", "items"])}}
    end
  end

  @impl true
  def catalog_source(%{object_id: id, sandbox: sandbox}), do: {:rkeeper, id, sandbox}

  @impl true
  def fetch_catalog(settings) do
    with {:ok, response} <- Api.task(settings, "GetMenu") do
      {:ok,
       response
       |> list(["dishes", "products", "items"])
       |> Enum.map(fn dish ->
         %{
           external_id: to_string(dish["id"] || dish["code"]),
           name: dish["name"],
           price: round((dish["price"] || 0) * 100)
         }
       end)}
    end
  end

  @impl true
  def fetch_menu(settings) do
    with {:ok, response} <- Api.task(settings, "GetMenu") do
      {:ok,
       %{
         categories:
           response
           |> list(["categories", "dishCategories"])
           |> Enum.map(&%{external_id: to_string(&1["id"] || &1["code"]), name: &1["name"]}),
         products:
           response
           |> list(["dishes", "products", "items"])
           |> Enum.map(&menu_dish/1)
       }}
    end
  end

  defp menu_dish(dish) do
    %{
      external_id: to_string(dish["id"] || dish["code"]),
      name: dish["name"],
      category:
        (dish["categoryId"] || dish["category"]) &&
          to_string(dish["categoryId"] || dish["category"]),
      price: round((dish["price"] || 0) * 100),
      groups:
        dish
        |> Map.get("modifierGroups", [])
        |> Enum.map(fn group ->
          %{
            external_id: to_string(group["id"] || group["code"]),
            name: group["name"] || "Модификаторы",
            min: group["minAmount"] || group["min"] || 0,
            max: group["maxAmount"] || group["max"] || 1,
            modifiers:
              group
              |> Map.get("modifiers", [])
              |> Enum.map(
                &%{
                  external_id: to_string(&1["id"] || &1["code"]),
                  name: &1["name"],
                  price: round((&1["price"] || 0) * 100)
                }
              )
          }
        end)
    }
  end

  @impl true
  def stops_enabled?(%{sync_stops: true} = settings), do: configured?(settings)
  def stops_enabled?(_settings), do: false

  @impl true
  def fetch_stops(settings) do
    with {:ok, response} <- Api.task(settings, "GetStopList") do
      {:ok,
       response
       |> list(["stopList", "dishes", "items"])
       |> Enum.map(&to_string(&1["id"] || &1["code"]))}
    end
  end

  @impl true
  def rate_limit(_settings), do: nil

  @impl true
  def classify_error(:pos_offline), do: {:snooze, 120}
  def classify_error(:unsupported_payment), do: :permanent
  def classify_error({:missing_external_id, _id}), do: :permanent
  def classify_error({:rkeeper, _text}), do: :permanent
  def classify_error(reason), do: Delivest.Integrations.Error.classify(reason)

  @impl true
  def health_check(settings) do
    cond do
      not Api.configured?() -> {:error, :not_configured}
      not configured?(settings) -> {:error, :not_configured}
      true -> available(settings)
    end
  end

  def available(settings) do
    case Api.task(settings, "IsMainSystemAvailable", %{systemType: "RKRef"}, wait: 15) do
      {:ok, %{"isAvailable" => false}} -> {:error, :pos_offline}
      {:ok, %{"available" => false}} -> {:error, :pos_offline}
      {:ok, _response} -> :ok
      {:pending, _guid} -> {:error, :pos_offline}
      error -> error
    end
  end

  def active_branches do
    from(o in Order,
      where: is_nil(o.deleted_at) and o.status not in [:completed, :cancelled],
      where: fragment("?->>'provider' = 'rkeeper'", o.crm),
      where: fragment("?->>'status' IN ('confirming', 'sent')", o.crm),
      distinct: true,
      select: o.branch_id
    )
    |> Repo.all()
  end

  def poll(branch_id) do
    orders =
      Repo.all(
        from(o in Order,
          where: o.branch_id == ^branch_id and is_nil(o.deleted_at),
          where: o.status not in [:completed, :cancelled],
          where: fragment("?->>'provider' = 'rkeeper'", o.crm),
          where: fragment("?->>'status' IN ('confirming', 'sent')", o.crm)
        )
      )

    with [_ | _] <- orders,
         {:ok, settings} <- settings(branch_id) do
      Enum.each(orders, &poll_order(&1, settings))
      :more
    else
      [] -> :done
      error -> error
    end
  end

  defp poll_order(%Order{crm: %{status: "confirming", ref: ref}} = order, settings) do
    case Api.task_response(settings, ref) do
      {:ok, response} ->
        case delivery(response) do
          {:ok, delivery} -> Crm.confirm_order(order, delivery)
          _waiting -> :ok
        end

      {:error, {:rkeeper, text}} ->
        Crm.reject_order(order, text)

      _pending ->
        :ok
    end
  end

  defp poll_order(%Order{crm: %{status: "sent", external_id: guid}} = order, settings) do
    with {:ok, response} <- Api.task(settings, "GetOrderState", %{orderGuid: guid}),
         code when is_binary(code) <- state(response),
         false <- code == order.crm.remote_status_code do
      SyncState.remote_status(order, status_for(code), code, DateTime.utc_now(:second))
    end
  end

  defp poll_order(_order, _settings), do: :ok

  defp state(%{"order" => %{} = order}), do: state(order)
  defp state(%{"status" => status}) when is_binary(status), do: status
  defp state(%{"state" => state}) when is_binary(state), do: state
  defp state(_response), do: nil

  defp settings(branch_id) do
    case Crm.get_branch_settings(branch_id) do
      %{rkeeper: %{} = settings} -> {:ok, settings}
      _none -> {:error, :missing_settings}
    end
  end

  defp void_reason(%{void_reason_code: code}) when is_binary(code) and code != "" do
    case Integer.parse(code) do
      {number, ""} -> number
      _other -> code
    end
  end

  defp void_reason(_settings), do: 1

  defp list(response, keys) do
    Enum.find_value(keys, [], fn key ->
      case response do
        %{^key => list} when is_list(list) -> list
        _other -> nil
      end
    end)
  end

  defp articles(order) do
    modifier_ids =
      order.items
      |> Enum.flat_map(&if(is_list(&1.modifiers), do: &1.modifiers, else: []))
      |> Enum.map(& &1.modifier_id)
      |> Enum.reject(&is_nil/1)

    %{
      products: order.items |> Enum.map(& &1.product_id) |> ProductCrmIds.by_product(key()),
      modifiers: Modifiers.crm_ids(modifier_ids, key())
    }
  end
end
