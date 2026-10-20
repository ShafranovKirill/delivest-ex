defmodule DelivestWeb.Staff.PromotionLive.PromotionHelpers do
  use Gettext, backend: DelivestWeb.Gettext

  alias Delivest.LocalTime
  alias Delivest.Promo.Promotion

  @window_fields ["starts_at", "ends_at"]

  def kind_label(:automatic), do: gettext("Automatic")
  def kind_label(:public_code), do: gettext("Public code")
  def kind_label(:personal_code), do: gettext("Personal codes")

  def kind_options, do: Enum.map(Promotion.kinds(), &{kind_label(&1), &1})

  def kind_icon(:automatic), do: "hero-bolt"
  def kind_icon(:public_code), do: "hero-ticket"
  def kind_icon(:personal_code), do: "hero-user"

  def state(%Promotion{enabled: false}, _now), do: :disabled

  def state(%Promotion{starts_at: starts_at, ends_at: ends_at}, now) do
    cond do
      starts_at && DateTime.compare(now, starts_at) == :lt -> :scheduled
      ends_at && DateTime.compare(now, ends_at) != :lt -> :ended
      true -> :active
    end
  end

  def state_label(:active), do: gettext("Active")
  def state_label(:scheduled), do: gettext("Scheduled")
  def state_label(:ended), do: gettext("Ended")
  def state_label(:disabled), do: gettext("Disabled")

  def state_class(:active), do: "badge-success"
  def state_class(:scheduled), do: "badge-info"
  def state_class(:ended), do: "badge-ghost"
  def state_class(:disabled), do: "badge-error text-error-content"

  def usage_label(count, nil), do: to_string(count)
  def usage_label(count, limit), do: "#{count} / #{limit}"

  def window_to_utc(params) when is_map(params) do
    Enum.reduce(@window_fields, params, fn field, acc ->
      Map.update(acc, field, nil, &local_to_utc/1)
    end)
  end

  def local_input(nil), do: nil

  def local_input(%DateTime{} = datetime),
    do: datetime |> LocalTime.utc_to_naive() |> NaiveDateTime.to_iso8601() |> String.slice(0, 16)

  def local_input(value), do: value

  defp local_to_utc(value) when is_binary(value) and value != "" do
    case NaiveDateTime.from_iso8601(normalize_seconds(value)) do
      {:ok, naive} -> naive |> LocalTime.naive_to_utc() |> DateTime.to_iso8601()
      _ -> value
    end
  end

  defp local_to_utc(value), do: value

  defp normalize_seconds(value) do
    if String.length(value) == 16, do: value <> ":00", else: value
  end
end
