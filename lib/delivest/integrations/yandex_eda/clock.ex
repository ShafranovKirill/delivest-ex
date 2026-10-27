defmodule Delivest.Integrations.YandexEda.Clock do
  alias Delivest.LocalTime

  def format(%NaiveDateTime{} = naive), do: naive |> DateTime.from_naive!("Etc/UTC") |> format()

  def format(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!(LocalTime.timezone())
    |> Map.update!(:microsecond, fn {value, _precision} -> {value, 6} end)
    |> DateTime.to_iso8601()
  end

  def parse(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.truncate(datetime, :second)}
      {:error, _reason} -> :error
    end
  end

  def parse(_value), do: :error

  def local(%DateTime{} = datetime), do: LocalTime.utc_to_naive(datetime)
end
