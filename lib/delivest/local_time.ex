defmodule Delivest.LocalTime do
  @moduledoc """
  Calendar helpers bound to the business time zone (`config :delivest, :timezone`).

  Timestamps are stored in UTC, but "today" for staff means the local day.
  """

  @default_timezone "Europe/Moscow"

  @spec timezone() :: String.t()
  def timezone, do: Application.get_env(:delivest, :timezone, @default_timezone)

  @spec today(String.t()) :: Date.t()
  def today(zone \\ timezone()) do
    DateTime.utc_now() |> DateTime.shift_zone!(zone) |> DateTime.to_date()
  end

  @doc "UTC instant at which the given local date starts."
  @spec start_of_day_utc(Date.t(), String.t()) :: DateTime.t()
  def start_of_day_utc(%Date{} = date, zone \\ timezone()), do: to_utc(date, ~T[00:00:00], zone)

  @doc "UTC instant at which the given local date ends (inclusive, second precision)."
  @spec end_of_day_utc(Date.t(), String.t()) :: DateTime.t()
  def end_of_day_utc(%Date{} = date, zone \\ timezone()), do: to_utc(date, ~T[23:59:59], zone)

  defp to_utc(date, time, zone) do
    local =
      case DateTime.new(date, time, zone) do
        {:ok, dt} -> dt
        {:ambiguous, first, _second} -> first
        {:gap, _before, just_after} -> just_after
      end

    DateTime.shift_zone!(local, "Etc/UTC")
  end
end
