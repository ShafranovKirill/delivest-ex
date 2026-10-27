defmodule Delivest.Oms.OrderStatus do
  alias Delivest.Oms.Order

  @final [:completed, :cancelled]

  def current(%Order{status: :crm, crm: %{remote_status: status}}) when is_binary(status),
    do: String.to_existing_atom(status)

  def current(%Order{status: :crm, crm: %{status: "sent"}}), do: :accepted
  def current(%Order{status: :crm}), do: :created
  def current(%Order{status: status}), do: status

  def active?(order), do: current(order) not in @final

  def final, do: @final
end
