defmodule Delivest.Oms.OrderStatus do
  alias Delivest.Oms.Order

  @final [:completed, :cancelled]
  @rank %{
    created: 0,
    accepted: 1,
    preparing: 2,
    ready: 3,
    delivering: 4,
    completed: 5,
    cancelled: 6
  }

  def current(%Order{} = order), do: order |> kitchen() |> with_channel(order.channel)

  def active?(order), do: current(order) not in @final

  def final, do: @final

  def rank(status), do: Map.fetch!(@rank, status)

  def forward?(from, to), do: to == :cancelled or is_nil(from) or rank(to) > rank(from)

  defp kitchen(%Order{status: :crm, crm: %{remote_status: status}}) when is_binary(status),
    do: String.to_existing_atom(status)

  defp kitchen(%Order{status: :crm, crm: %{status: "sent"}}), do: :accepted
  defp kitchen(%Order{status: :crm}), do: :created
  defp kitchen(%Order{status: status}), do: status

  defp with_channel(status, %{remote_status: remote}) when is_binary(remote) do
    remote = String.to_existing_atom(remote)
    if forward?(status, remote), do: remote, else: status
  end

  defp with_channel(status, _channel), do: status
end
