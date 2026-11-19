defmodule Delivest.Integrations.Frontpad.CertificateExport do
  @moduledoc false

  alias Delivest.Money

  def apply(order, settings, payload) do
    case linked_certificate(order) do
      nil ->
        payload

      {promotion, certificate} ->
        case export(order, settings, payload.products, promotion, certificate) do
          {:ok, products, sale_amount} ->
            %{
              payload
              | certificate: certificate["code"],
                certificate_snapshot: certificate,
                products: products,
                sale_amount: sale_amount
            }

          {:fallback, reason} ->
            fallback(payload, certificate["code"], reason)
        end
    end
  end

  def fallback(payload, raw_code, reason) do
    code = display_code(raw_code)

    %{
      payload
      | certificate_alert: {reason, code},
        descr: append_reference(payload.descr, code)
    }
  end

  def current?(
        %{certificate_snapshot: %{"type" => "amount", "amount" => amount}},
        %{type: :amount, amount: amount}
      ),
      do: true

  def current?(
        %{
          certificate_snapshot: %{"type" => "product", "product_id" => id, "price" => price}
        },
        %{type: :product, product_id: id, price: price}
      ),
      do: true

  def current?(_payload, _current), do: false

  defp linked_certificate(%{promotions: promotions}) when is_list(promotions) do
    Enum.find_value(promotions, fn promotion ->
      case Map.get(promotion, :crm_certificate) do
        %{"provider" => "frontpad"} = certificate -> {promotion, certificate}
        _ -> nil
      end
    end)
  end

  defp linked_certificate(_order), do: nil

  defp export(order, settings, products, promotion, certificate) do
    with true <- single_promotion?(order, promotion),
         true <- clean_order?(order),
         true <- valid_code?(certificate["code"]) do
      case {certificate, Map.get(promotion, :certificate_export_mode)} do
        {%{"type" => "amount", "amount" => amount}, "cart_amount"}
        when is_integer(amount) and amount > 0 ->
          amount(order, settings, products, promotion, amount)

        {%{"type" => "product", "product_id" => id, "price" => 0}, "single_gift"}
        when is_binary(id) and id != "" ->
          gift(order, products, promotion, id)

        _ ->
          {:fallback, :unsupported_certificate}
      end
    else
      _ -> {:fallback, :unmatched_certificate}
    end
  end

  defp single_promotion?(%{promotions: [only]}, promotion),
    do: only == promotion and not is_nil(Map.get(promotion, :promo_code_id))

  defp single_promotion?(_order, _promotion), do: false

  defp clean_order?(%{delivery_amount: delivery, points_spent: points, items: items} = order)
       when delivery in [nil, 0] and points in [nil, 0] and is_list(items) and items != [] do
    Enum.all?(items, fn item ->
      (Map.get(item, :modifiers) || []) == [] and is_integer(item.price) and
        is_integer(item.base_price) and is_integer(item.quantity) and item.quantity > 0 and
        Map.get(item, :stars_spent, 0) in [nil, 0]
    end) and total_consistent?(order)
  end

  defp clean_order?(_order), do: false

  defp total_consistent?(%{total_amount: total, items: items}) when is_integer(total) do
    total == Enum.sum(Enum.map(items, &(&1.price * &1.quantity)))
  end

  defp total_consistent?(_order), do: false

  defp valid_code?(code),
    do: is_binary(code) and String.length(code) in 4..20 and String.trim(code) == code

  defp display_code(code) when is_binary(code),
    do: code |> String.replace(~r/[\r\n\t]/u, " ") |> String.slice(0, 20)

  defp display_code(_code), do: "?"

  defp append_reference(description, code) do
    existing = description || ""
    reference = "Сертификат #{code}: расчёт сайта"
    combined = if existing == "", do: reference, else: existing <> ". " <> reference
    if String.length(combined) <= 100, do: combined, else: description
  end

  defp amount(order, settings, products, promotion, amount) do
    items = order.items

    with true <- Enum.all?(items, &(not &1.gift and &1.base_price >= &1.price)),
         ^amount <- Map.get(promotion, :discount),
         ^amount <- order.discount_amount,
         ^amount <- Enum.sum(Enum.map(items, &((&1.base_price - &1.price) * &1.quantity))),
         true <- length(items) == length(products) do
      products =
        if settings.price_override do
          Enum.zip_with(items, products, fn item, product ->
            %{product | price: item.base_price |> Money.to_rubles() |> to_string()}
          end)
        else
          products
        end

      {:ok, products, nil}
    else
      _ -> {:fallback, :unmatched_certificate}
    end
  end

  defp gift(order, products, promotion, certificate_product_id) do
    gift_items = Enum.filter(order.items, & &1.gift)
    paid_items = Enum.reject(order.items, & &1.gift)

    with [%{price: 0, quantity: 1} = gift_item] <- gift_items,
         0 <- Map.get(promotion, :discount),
         0 <- order.discount_amount,
         true <- paid_items != [] and Enum.all?(paid_items, &(&1.base_price == &1.price)),
         true <- length(order.items) == length(products),
         gift_index when is_integer(gift_index) <- Enum.find_index(order.items, & &1.gift),
         %{external_id: ^certificate_product_id} <- Enum.at(products, gift_index),
         true <- not is_nil(gift_item.product_id) do
      {:ok, List.delete_at(products, gift_index), nil}
    else
      _ -> {:fallback, :unmatched_certificate}
    end
  end
end
