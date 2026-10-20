defmodule DelivestWeb.Staff.LogLive.EventText do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Audit.Event
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  def describe(%Event{} = event) do
    text(event.action, %{
      subject: event.subject_label || "—",
      changes: changes(event.metadata),
      error: event.metadata["error"]
    })
  end

  def actor(%Event{actor_type: :staff, actor_name: name}),
    do: gettext("Staff %{name}", name: name)

  def actor(%Event{actor_type: :client, actor_name: name}),
    do: gettext("Client %{name}", name: name)

  def actor(%Event{actor_type: :guest}), do: gettext("Guest")
  def actor(%Event{actor_type: :system}), do: gettext("System")

  def subject_types do
    [
      {"order", gettext("Orders")},
      {"product", gettext("Products")},
      {"category", gettext("Categories")},
      {"stock", gettext("Promotions")},
      {"promotion", gettext("Discounts & promo codes")},
      {"client", gettext("Clients")},
      {"staff", gettext("Staff")},
      {"role", gettext("Roles")},
      {"branch", gettext("Branches")}
    ]
  end

  defp text("order.created", b), do: gettext("Order %{subject} created", b)
  defp text("order.updated", b), do: gettext("Order %{subject} edited", b)
  defp text("order.details_changed", b), do: gettext("Order %{subject} changed: %{changes}", b)
  defp text("order.deleted", b), do: gettext("Order %{subject} deleted", b)
  defp text("order.sent_to_crm", b), do: gettext("Order %{subject} sent to CRM", b)

  defp text("order.crm_status_changed", b),
    do: gettext("Order %{subject} status changed in CRM: %{changes}", b)

  defp text("order.crm_failed", b), do: gettext("Order %{subject} not sent to CRM: %{error}", b)

  defp text("product.created", b), do: gettext("Product «%{subject}» created", b)
  defp text("product.updated", b), do: gettext("Product «%{subject}» edited", b)
  defp text("product.deleted", b), do: gettext("Product «%{subject}» deleted", b)

  defp text("category.created", b), do: gettext("Category «%{subject}» created", b)
  defp text("category.updated", b), do: gettext("Category «%{subject}» edited", b)
  defp text("category.deleted", b), do: gettext("Category «%{subject}» deleted", b)

  defp text("stock.created", b), do: gettext("Promotion «%{subject}» created", b)
  defp text("stock.updated", b), do: gettext("Promotion «%{subject}» edited", b)
  defp text("stock.deleted", b), do: gettext("Promotion «%{subject}» deleted", b)

  defp text("promotion.created", b), do: gettext("Promotion «%{subject}» created", b)
  defp text("promotion.updated", b), do: gettext("Promotion «%{subject}» edited", b)
  defp text("promotion.deleted", b), do: gettext("Promotion «%{subject}» deleted", b)
  defp text("promo_code.issued", b), do: gettext("Promo code %{subject} issued", b)
  defp text("promo_code.revoked", b), do: gettext("Promo code %{subject} revoked", b)

  defp text("client.created", b), do: gettext("Client %{subject} added", b)
  defp text("client.updated", b), do: gettext("Client %{subject} edited", b)
  defp text("client.deleted", b), do: gettext("Client %{subject} deleted", b)

  defp text("staff.created", b), do: gettext("Employee %{subject} added", b)
  defp text("staff.updated", b), do: gettext("Employee %{subject} edited", b)
  defp text("staff.password_changed", b), do: gettext("Password of %{subject} changed", b)
  defp text("staff.deleted", b), do: gettext("Employee %{subject} deleted", b)
  defp text("staff.logged_in", _b), do: gettext("Signed in")
  defp text("staff.logged_out", _b), do: gettext("Signed out")

  defp text("role.created", b), do: gettext("Role «%{subject}» created", b)
  defp text("role.updated", b), do: gettext("Role «%{subject}» edited", b)
  defp text("role.deleted", b), do: gettext("Role «%{subject}» deleted", b)

  defp text("branch.created", b), do: gettext("Branch «%{subject}» created", b)
  defp text("branch.updated", b), do: gettext("Branch «%{subject}» edited", b)
  defp text("branch.deleted", b), do: gettext("Branch «%{subject}» deleted", b)

  defp text(action, b), do: gettext("%{action}: %{subject}", Map.put(b, :action, action))

  defp changes(metadata) do
    metadata
    |> Enum.map(fn
      {"status", value} ->
        gettext("status → %{value}", value: OrderHelpers.status_label(value))

      {"payment_method", value} ->
        gettext("payment → %{value}", value: OrderHelpers.payment_label(value))

      {key, value} ->
        "#{key} → #{value}"
    end)
    |> Enum.join(", ")
  end
end
