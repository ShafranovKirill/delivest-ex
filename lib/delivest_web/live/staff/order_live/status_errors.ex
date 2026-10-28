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

  def message(reason) when reason in [:finished, :backward, :skipped_step, :unreachable],
    do: gettext("The order status has already changed, refresh the page")

  def message(%Ecto.Changeset{} = changeset) do
    if Keyword.has_key?(changeset.errors, :revert_reason),
      do: gettext("Enter the reason for reverting"),
      else: gettext("Failed to update order")
  end

  def message(_reason), do: gettext("Failed to update order")
end
