defmodule Delivest.Fiscal.Builder do
  alias Delivest.Fiscal.BranchSettings
  alias Delivest.Money.Allocation
  alias Delivest.Oms.{Order, OrderItem}

  @name_limit 128
  @cashier_limit 64
  @payment_types %{cash: :cash, card: :card, online: :card, sbp: :card, certificate: :prepayment}

  def build(%Order{} = order, %BranchSettings{} = settings, opts) do
    payments = Keyword.fetch!(opts, :payments)
    total = Enum.sum(Enum.map(payments, & &1.sum))
    delivery = delivery(order, settings, total)
    goods_total = total - Enum.sum(Enum.map(delivery, & &1.sum))

    items =
      order.items
      |> Enum.map(&item(&1, settings, opts))
      |> Allocation.fit(goods_total)
      |> Enum.map(&with_sum/1)

    %{
      kind: Keyword.get(opts, :kind, :sell),
      stage: Keyword.get(opts, :stage, :full_payment),
      company: %{
        inn: settings.inn,
        sno: settings.sno,
        payment_address: settings.payment_address,
        email: settings.email
      },
      client: client(order, opts),
      cashier: cashier(opts[:cashier]),
      items: items ++ delivery,
      payments: payments,
      total: total
    }
  end

  def payments(payments, stage \\ :full_payment, kind \\ :sell) do
    payments
    |> Enum.group_by(&payment_type(&1.method, stage, kind), & &1.amount)
    |> Enum.map(fn {type, sums} -> %{type: type, sum: Enum.sum(sums)} end)
    |> Enum.sort_by(& &1.type)
  end

  defp payment_type(:online, :full_payment, :sell), do: :prepayment
  defp payment_type(method, _stage, _kind), do: Map.get(@payment_types, method, :card)

  defp item(%OrderItem{} = item, settings, opts) do
    product = Map.get(Keyword.get(opts, :products, %{}), item.product_id, %{})

    %{
      name: String.slice(OrderItem.full_title(item), 0, @name_limit),
      price: item.price,
      quantity: item.quantity,
      vat: Map.get(product, :vat) || settings.vat,
      object: if(Map.get(product, :excise), do: :excise, else: :product)
    }
  end

  defp delivery(%Order{delivery_amount: amount}, settings, total)
       when is_integer(amount) and amount > 0 and total >= amount,
       do: [
         %{
           name: "Доставка",
           price: amount,
           quantity: 1,
           sum: amount,
           vat: settings.delivery_vat,
           object: :service
         }
       ]

  defp delivery(_order, _settings, _total), do: []

  defp with_sum(line), do: Map.put(line, :sum, line.price * line.quantity)

  defp client(order, opts) do
    %{phone: order.customer_phone, email: opts[:email] || order.customer_email}
    |> Map.reject(fn {_key, value} -> value in [nil, ""] end)
  end

  defp cashier(name) when is_binary(name) and name != "",
    do: String.slice(name, 0, @cashier_limit)

  defp cashier(_name), do: nil
end
