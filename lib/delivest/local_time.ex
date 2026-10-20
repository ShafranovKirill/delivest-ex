defmodule Delivest.LocalTime do
  @default_timezone "Europe/Moscow"

  @spec timezone() :: String.t()
  def timezone, do: Application.get_env(:delivest, :timezone, @default_timezone)

  @spec today(String.t()) :: Date.t()
  def today(zone \\ timezone()) do
    DateTime.utc_now() |> DateTime.shift_zone!(zone) |> DateTime.to_date()
  end

  @spec start_of_day_utc(Date.t(), String.t()) :: DateTime.t()
  def start_of_day_utc(%Date{} = date, zone \\ timezone()), do: to_utc(date, ~T[00:00:00], zone)

  @spec end_of_day_utc(Date.t(), String.t()) :: DateTime.t()
  def end_of_day_utc(%Date{} = date, zone \\ timezone()), do: to_utc(date, ~T[23:59:59], zone)

  @spec naive_to_utc(NaiveDateTime.t(), String.t()) :: DateTime.t()
  def naive_to_utc(%NaiveDateTime{} = naive, zone \\ timezone()),
    do: to_utc(NaiveDateTime.to_date(naive), NaiveDateTime.to_time(naive), zone)

  @spec utc_to_naive(DateTime.t(), String.t()) :: NaiveDateTime.t()
  def utc_to_naive(%DateTime{} = datetime, zone \\ timezone()),
    do: datetime |> DateTime.shift_zone!(zone) |> DateTime.to_naive()

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
