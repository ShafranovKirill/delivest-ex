defmodule Delivest.Audit.Subject do
  alias Delivest.Identity.{Branch, Client, Role, Staff}
  alias Delivest.Net.{Category, Product, ProductTag, Stock}
  alias Delivest.Oms.Order
  alias Delivest.Promo.{PromoCode, Promotion}

  @label_length 120

  def describe(%Order{} = order),
    do: build("order", order.id, "#" <> to_string(order.number), order.branch_id)

  def describe(%Product{} = product), do: build("product", product.id, product.name)
  def describe(%Category{} = category), do: build("category", category.id, category.name)
  def describe(%ProductTag{} = tag), do: build("product_tag", tag.id, tag.name)
  def describe(%Stock{} = stock), do: build("stock", stock.id, stock.text)
  def describe(%Branch{} = branch), do: build("branch", branch.id, branch.name, branch.id)
  def describe(%Staff{} = staff), do: build("staff", staff.id, staff.name || staff.login)
  def describe(%Role{} = role), do: build("role", role.id, role.name)

  def describe(%Delivest.Loyalty.Entry{} = entry) do
    sign = if entry.amount > 0, do: "+", else: ""
    build("client", entry.client_id, "#{sign}#{entry.amount} ★", entry.branch_id)
  end

  def describe(%Client{} = client), do: build("client", client.id, client.name || client.phone)

  def describe(%Promotion{} = promotion),
    do: build("promotion", promotion.id, promotion.name, promotion.branch_id)

  def describe(%PromoCode{} = code),
    do: build("promotion", code.promotion_id, code.code, code.branch_id)

  defp build(type, id, label, branch_id \\ nil) do
    %{
      subject_type: type,
      subject_id: to_string(id),
      subject_label: label && String.slice(label, 0, @label_length),
      branch_id: branch_id
    }
  end
end
