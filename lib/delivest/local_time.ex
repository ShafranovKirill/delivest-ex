defmodule Delivest.LocalTime do
  import Ecto.Query, only: [from: 2]

  alias Delivest.Franchise.SettingsStore
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Repo

  @default_timezone "Europe/Moscow"
  @day_starts_at ~T[05:00:00]
  @russia [
    "Europe/Kaliningrad",
    "Europe/Moscow",
    "Europe/Samara",
    "Asia/Yekaterinburg",
    "Asia/Omsk",
    "Asia/Novosibirsk",
    "Asia/Krasnoyarsk",
    "Asia/Irkutsk",
    "Asia/Yakutsk",
    "Asia/Vladivostok",
    "Asia/Magadan",
    "Asia/Kamchatka"
  ]

  @spec zones() :: [String.t()]
  def zones, do: @russia

  @spec timezone() :: String.t()
  def timezone, do: SettingsStore.get().timezone || @default_timezone

  @spec timezone(Branch.t() | BranchInfo.t() | String.t() | nil) :: String.t()
  def timezone(nil), do: timezone()
  def timezone(%Branch{info: %BranchInfo{} = info}), do: timezone(info)
  def timezone(%Branch{id: id}), do: timezone(id)
  def timezone(%BranchInfo{timezone: zone}) when is_binary(zone), do: zone
  def timezone(%BranchInfo{}), do: timezone()

  def timezone(branch_id) when is_binary(branch_id) do
    key = {:timezone, branch_id}

    zone =
      case Cachex.get(:branch_cache, key) do
        {:ok, {:zone, zone}} ->
          zone

        _miss ->
          zone = own_zone(branch_id)
          Cachex.put(:branch_cache, key, {:zone, zone}, ttl: :timer.hours(1))
          zone
      end

    zone || timezone()
  end

  @spec local(DateTime.t(), term()) :: DateTime.t()
  def local(%DateTime{} = datetime, branch), do: DateTime.shift_zone!(datetime, timezone(branch))

  @spec input(DateTime.t() | nil, term()) :: String.t() | nil
  def input(nil, _branch), do: nil

  def input(%DateTime{} = datetime, branch),
    do: datetime |> local(branch) |> Calendar.strftime("%Y-%m-%dT%H:%M")

  @spec parse(term(), term()) :: DateTime.t() | term()
  def parse(%NaiveDateTime{} = naive, branch), do: naive_to_utc(naive, timezone(branch))

  def parse(value, branch) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      {:error, _reason} ->
        case NaiveDateTime.from_iso8601(seconds(value)) do
          {:ok, naive} -> parse(naive, branch)
          {:error, _reason} -> value
        end
    end
  end

  def parse(value, _branch), do: value

  defp seconds(<<_date::binary-size(10), "T", _hm::binary-size(5)>> = value), do: value <> ":00"
  defp seconds(<<_date::binary-size(10), " ", _hm::binary-size(5)>> = value), do: value <> ":00"
  defp seconds(value), do: value

  def validate_timezone(changeset, field) do
    Ecto.Changeset.validate_change(changeset, field, fn ^field, zone ->
      if match?({:ok, _now}, DateTime.now(zone)),
        do: [],
        else: [{field, "is not a known time zone"}]
    end)
  end

  defp own_zone(branch_id) do
    Repo.one(from(i in BranchInfo, where: i.branch_id == ^branch_id, select: i.timezone))
  end

  @spec today(String.t()) :: Date.t()
  def today(zone \\ timezone()) do
    DateTime.utc_now() |> DateTime.shift_zone!(zone) |> DateTime.to_date()
  end

  @spec day_starts_at() :: Time.t()
  def day_starts_at, do: @day_starts_at

  @spec business_date(DateTime.t(), String.t()) :: Date.t()
  def business_date(%DateTime{} = datetime, zone \\ timezone()) do
    local = DateTime.shift_zone!(datetime, zone)
    date = DateTime.to_date(local)

    if Time.before?(DateTime.to_time(local), @day_starts_at),
      do: Date.add(date, -1),
      else: date
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
