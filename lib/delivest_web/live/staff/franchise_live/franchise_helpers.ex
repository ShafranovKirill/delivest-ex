defmodule DelivestWeb.Staff.FranchiseLive.FranchiseHelpers do
  use Gettext, backend: DelivestWeb.Gettext

  def document_title(:privacy), do: gettext("Personal data policy")
  def document_title(:consent), do: gettext("Consent to personal data processing")
  def document_title(:offer), do: gettext("Public offer")
  def document_title(:terms), do: gettext("Terms of use")

  def readable_on_white?(hex) do
    case hex_to_rgb(hex) do
      {:ok, rgb} -> contrast(luminance(rgb), 1.0) >= 3.0
      :error -> true
    end
  end

  defp hex_to_rgb("#" <> hex) when byte_size(hex) == 6 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<r, g, b>>} -> {:ok, {r, g, b}}
      :error -> :error
    end
  end

  defp hex_to_rgb(_hex), do: :error

  defp luminance({r, g, b}),
    do: 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)

  defp channel(value) do
    c = value / 255
    if c <= 0.03928, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
  end

  defp contrast(a, b), do: (max(a, b) + 0.05) / (min(a, b) + 0.05)
end
