defmodule Delivest.Integrations.YandexEda.Statuses do
  @ours %{
    created: "NEW",
    accepted: "ACCEPTED_BY_RESTAURANT",
    preparing: "COOKING",
    ready: "READY",
    delivering: "TAKEN_BY_COURIER",
    completed: "DELIVERED",
    cancelled: "CANCELLED"
  }

  @remote %{
    "TAKEN_BY_COURIER" => "delivering",
    "DELIVERED" => "completed",
    "CANCELLED" => "cancelled"
  }

  def to_yandex(status), do: Map.fetch!(@ours, status)

  def from_yandex(code) do
    case Map.fetch(@remote, code) do
      {:ok, status} -> {:ok, status}
      :error -> {:error, :invalid_status}
    end
  end
end
