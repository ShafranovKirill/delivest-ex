defmodule Delivest.Integrations.YandexEda.OrderAddress do
  alias Delivest.Integrations.Dadata

  @located [:city, :street, :house, :fias_id, :postal_code, :district, :geo_precision]
  @geolocation_budget_ms 300

  def build(nil), do: nil

  def build(%{full: full, latitude: latitude, longitude: longitude}) do
    %{"formatted" => String.slice(full, 0, 255), "latitude" => latitude, "longitude" => longitude}
    |> Map.merge(locate(latitude, longitude))
  end

  defp locate(latitude, longitude) do
    task =
      Task.Supervisor.async_nolink(Delivest.TaskSupervisor, fn ->
        Dadata.geolocate(latitude, longitude)
      end)

    case Task.yield(task, @geolocation_budget_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, [address | _]}} ->
        for field <- @located,
            value = Map.get(address, field),
            into: %{},
            do: {to_string(field), value}

      _ ->
        %{}
    end
  end
end
