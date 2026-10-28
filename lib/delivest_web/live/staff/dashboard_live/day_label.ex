defmodule DelivestWeb.Staff.DashboardLive.DayLabel do
  use Gettext, backend: DelivestWeb.Gettext

  def format(%Date{day: day, month: month}),
    do: gettext("%{month} %{day}", month: month_name(month), day: day)

  defp month_name(1), do: pgettext("day of", "January")
  defp month_name(2), do: pgettext("day of", "February")
  defp month_name(3), do: pgettext("day of", "March")
  defp month_name(4), do: pgettext("day of", "April")
  defp month_name(5), do: pgettext("day of", "May")
  defp month_name(6), do: pgettext("day of", "June")
  defp month_name(7), do: pgettext("day of", "July")
  defp month_name(8), do: pgettext("day of", "August")
  defp month_name(9), do: pgettext("day of", "September")
  defp month_name(10), do: pgettext("day of", "October")
  defp month_name(11), do: pgettext("day of", "November")
  defp month_name(12), do: pgettext("day of", "December")
end
