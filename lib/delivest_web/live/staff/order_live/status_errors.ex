defmodule DelivestWeb.Staff.OrderLive.StatusErrors do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.Oms.Order

  @statuses Map.new(Order.statuses(), &{to_string(&1), &1})

  def parse_status(value) do
    case Map.fetch(@statuses, value) do
      {:ok, status} -> {:ok, status}
      :error -> {:error, :invalid_status}
    end
  end

  def message({:error, reason}), do: message(reason)
  def message(:forbidden), do: gettext("Permission denied")
  def message(:not_found), do: gettext("Order not found")
  def message(:order_not_found), do: gettext("Order not found")
  def message(:order_locked), do: gettext("The order is managed by the CRM")
  def message(:nothing_to_revert), do: gettext("There is no step to revert")
  def message(:not_available), do: gettext("This order is not delivered by our couriers")
  def message(:already_searching), do: gettext("A courier is already being searched for")
  def message(:not_a_courier), do: gettext("This employee is not a courier of the branch")
  def message(:not_assigned), do: gettext("No courier is assigned")
  def message(:picked_up), do: gettext("The courier has already picked up the order")
  def message(:taken), do: gettext("Another courier has already taken this order")
  def message(:not_yours), do: gettext("This order is not yours")

  def message(:handed_to_courier),
    do: gettext("The courier has picked up the order, its status cannot be reverted")

  def message(:not_ready), do: gettext("The order is not ready yet")

  def message(reason) when reason in [:finished, :backward, :skipped_step, :unreachable],
    do: gettext("The order status has already changed, refresh the page")

  def message(%Ecto.Changeset{} = changeset) do
    if Keyword.has_key?(changeset.errors, :revert_reason),
      do: gettext("Enter the reason for reverting"),
      else: gettext("Failed to update order")
  end

  def message(_reason), do: gettext("Failed to update order")
end
