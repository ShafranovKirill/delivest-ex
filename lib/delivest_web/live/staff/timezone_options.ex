defmodule DelivestWeb.Staff.TimezoneOptions do
  use Gettext, backend: DelivestWeb.Gettext

  def options do
    Enum.map(Delivest.LocalTime.zones(), &{label(&1), &1})
  end

  def branch_options, do: [{gettext("As the franchise"), ""} | options()]

  defp label(zone), do: "#{city(zone)} (UTC#{offset(zone)})"

  defp offset(zone) do
    seconds = DateTime.now!(zone).utc_offset
    sign = if seconds < 0, do: "-", else: "+"
    "#{sign}#{div(abs(seconds), 3600)}"
  end

  defp city("Europe/Kaliningrad"), do: gettext("Kaliningrad")
  defp city("Europe/Moscow"), do: gettext("Moscow")
  defp city("Europe/Samara"), do: gettext("Samara")
  defp city("Asia/Yekaterinburg"), do: gettext("Yekaterinburg")
  defp city("Asia/Omsk"), do: gettext("Omsk")
  defp city("Asia/Novosibirsk"), do: gettext("Novosibirsk")
  defp city("Asia/Krasnoyarsk"), do: gettext("Krasnoyarsk")
  defp city("Asia/Irkutsk"), do: gettext("Irkutsk")
  defp city("Asia/Yakutsk"), do: gettext("Yakutsk")
  defp city("Asia/Vladivostok"), do: gettext("Vladivostok")
  defp city("Asia/Magadan"), do: gettext("Magadan")
  defp city("Asia/Kamchatka"), do: gettext("Kamchatka")
end
