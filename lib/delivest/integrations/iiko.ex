defmodule Delivest.Integrations.Iiko do
  @behaviour Delivest.Integrations.Crm.Provider

  import Ecto.Query

  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Iiko.{Api, OrderPayload, Webhook}
  alias Delivest.Net.{Modifier, ModifierGroup, ProductCrmIds, ProductExternalId}
  alias Delivest.Repo

  @statuses %{
    "Unconfirmed" => :created,
    "WaitCooking" => :accepted,
    "ReadyForCooking" => :accepted,
    "CookingStarted" => :preparing,
    "CookingCompleted" => :ready,
    "Waiting" => :ready,
    "OnWay" => :delivering,
    "Delivered" => :completed,
    "Closed" => :completed,
    "Cancelled" => :cancelled
  }

  @impl true
  def key, do: :iiko

  @impl true
  def name, do: "iiko"

  @impl true
  def settings_schema, do: Delivest.Integrations.Iiko.Settings

  @impl true
  def configured?(%{api_key: key, organization_id: org, terminal_group_id: group}),
    do: Enum.all?([key, org, group], &(&1 not in [nil, ""]))

  def configured?(_settings), do: false

  @impl true
  def idempotent?, do: true

  @impl true
  def capabilities, do: [:cancel, :update_comment, :update_time, :own_pos]

  @impl true
  def status_map(_settings), do: @statuses

  def webhook_url(token), do: Crm.webhook_url(key(), token)

  @impl true
  def handle_webhook(token, params), do: Webhook.handle(token, params)

  @impl true
  def deliver_order(order, settings) do
    with {:ok, payload} <- OrderPayload.build(order, settings, articles(order)),
         {:ok, %{"correlationId" => ref}} <- Api.create_delivery(settings, payload) do
      {:pending, ref}
    else
      {:ok, body} -> {:error, {:iiko, inspect(body)}}
      error -> error
    end
  end

  @impl true
  def cancel_order(order, _reason, settings) do
    with {:ok, _body} <- Api.cancel(settings, order.id), do: :ok
  end

  @impl true
  def update_order(order, changes, settings) do
    changes
    |> Enum.reduce_while(:ok, fn change, :ok ->
      case apply_change(order, change, settings) do
        {:ok, _body} -> {:cont, :ok}
        :skip -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp apply_change(order, {"comment", _change}, settings),
    do: Api.change_comment(settings, order.id, order.comment || "")

  defp apply_change(order, {"cook_by", _value}, settings),
    do: Api.change_complete_before(settings, order.id, OrderPayload.complete_before(order))

  defp apply_change(_order, _change, _settings), do: :skip

  @impl true
  def dictionaries(settings) do
    with {:ok, %{"paymentTypes" => types}} <- Api.payment_types(settings) do
      {:ok,
       %{
         payment_types:
           types
           |> Enum.reject(&Map.get(&1, "isDeleted", false))
           |> Enum.map(&%{id: &1["id"], name: &1["name"]})
       }}
    end
  end

  def organizations(settings) do
    with {:ok, %{"organizations" => list}} <- Api.organizations(settings),
         do: {:ok, Enum.map(list, &%{id: &1["id"], name: &1["name"]})}
  end

  def terminal_groups(settings) do
    with {:ok, %{"terminalGroups" => groups}} <- Api.terminal_groups(settings) do
      {:ok,
       groups
       |> Enum.flat_map(&Map.get(&1, "items", []))
       |> Enum.map(&%{id: &1["id"], name: &1["name"]})}
    end
  end

  def register_webhooks(settings),
    do: Api.update_webhooks(settings, webhook_url(settings.webhook_token))

  @impl true
  def catalog_source(%{api_key: key, organization_id: org}), do: {:iiko, key, org}

  @impl true
  def fetch_catalog(settings) do
    with {:ok, %{"products" => products}} <- Api.nomenclature(settings) do
      {:ok,
       products
       |> Enum.reject(&(Map.get(&1, "isDeleted", false) or &1["type"] == "Modifier"))
       |> Enum.map(fn product ->
         %{external_id: product["id"], name: product["name"], price: price(product)}
       end)}
    end
  end

  defp price(%{"sizePrices" => [%{"price" => %{"currentPrice" => price}} | _]})
       when is_number(price),
       do: round(price * 100)

  defp price(_product), do: 0

  @impl true
  def stops_enabled?(%{sync_stops: true} = settings), do: configured?(settings)
  def stops_enabled?(_settings), do: false

  @impl true
  def fetch_stops(settings) do
    with {:ok, %{"terminalGroupStopLists" => lists}} <- Api.stop_lists(settings) do
      stops =
        for org <- lists,
            group <- Map.get(org, "items", []),
            group["terminalGroupId"] == settings.terminal_group_id,
            item <- Map.get(group, "items", []),
            (item["balance"] || 0) <= 0,
            uniq: true,
            do: item["productId"]

      {:ok, stops}
    end
  end

  @impl true
  def rate_limit(_settings), do: nil

  @impl true
  def classify_error({:missing_external_id, _id}), do: :permanent
  def classify_error({:missing_payment_type, _method}), do: :permanent
  def classify_error({:iiko, status, _text}) when status in [400, 404, 409], do: :permanent
  def classify_error({:iiko, 500, _text}), do: :retry
  def classify_error({:iiko, _text}), do: :auth
  def classify_error(reason), do: Delivest.Integrations.Error.classify(reason)

  @impl true
  def health_check(settings) do
    if configured?(settings) do
      case Api.alive(settings) do
        {:ok, %{"isAliveStatus" => statuses}} ->
          if Enum.any?(statuses, & &1["isAlive"]), do: :ok, else: {:error, :terminal_offline}

        {:ok, _body} ->
          :ok

        error ->
          error
      end
    else
      {:error, :not_configured}
    end
  end

  defp articles(order) do
    modifier_ids =
      order.items
      |> Enum.flat_map(&if(is_list(&1.modifiers), do: &1.modifiers, else: []))
      |> Enum.map(& &1.modifier_id)
      |> Enum.reject(&is_nil/1)

    %{
      products: order.items |> Enum.map(& &1.product_id) |> ProductCrmIds.by_product(key()),
      modifiers: modifier_articles(modifier_ids)
    }
  end

  defp modifier_articles([]), do: %{}

  defp modifier_articles(ids) do
    from(m in Modifier,
      join: g in ModifierGroup,
      on: g.id == m.group_id,
      join: e in ProductExternalId,
      on: e.entity_type == "modifier" and e.entity_id == m.id and e.provider == "iiko",
      left_join: ge in ProductExternalId,
      on: ge.entity_type == "modifier_group" and ge.entity_id == g.id and ge.provider == "iiko",
      where: m.id in ^ids,
      select: {m.id, %{external_id: e.external_id, group_id: ge.external_id, size: g.is_size}}
    )
    |> Repo.all()
    |> Map.new()
  end
end
