defmodule Delivest.Integrations.Frontpad.Warnings do
  use Gettext, backend: DelivestWeb.Gettext

  @critical ~w(invalid_product_keys invalid_hook_status invalid_datetime invalid_certificate)

  def apply(delivery, payload, order) do
    warnings = if is_map(delivery[:warnings]), do: delivery.warnings, else: %{}

    case local_alert(payload) ++ alerts(warnings, payload, order) do
      [] -> delivery
      alerts -> Map.put(delivery, :alert, Enum.join(alerts, ". "))
    end
  end

  defp local_alert(%{certificate_alert: {:unsupported_certificate, code}}),
    do: [
      gettext("Сертификат Frontpad %{code} не применён: отправлена рассчитанная сайтом скидка",
        code: code
      )
    ]

  defp local_alert(%{certificate_alert: {:unmatched_certificate, code}}),
    do: [
      gettext("Сертификат Frontpad %{code} не соответствует заказу: отправлена скидка сайта",
        code: code
      )
    ]

  defp local_alert(%{certificate_alert: {:changed_certificate, code}}),
    do: [gettext("Сертификат Frontpad %{code} изменился: отправлена скидка сайта", code: code)]

  defp local_alert(%{certificate_alert: {:verification_failed, code}}),
    do: [
      gettext("Сертификат Frontpad %{code} не удалось перепроверить: отправлена скидка сайта",
        code: code
      )
    ]

  defp local_alert(_payload), do: []

  defp alerts(warnings, payload, order) do
    warnings
    |> Map.take(@critical)
    |> Enum.map(fn {kind, value} -> text(kind, value, payload, order) end)
  end

  defp text("invalid_product_keys", value, payload, _order) do
    articles =
      value
      |> indexes()
      |> Enum.map(&Enum.at(payload.products, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join(", ", &"#{&1.external_id} ×#{&1.quantity}")

    gettext("Frontpad did not accept the items: %{articles}. Check the articles",
      articles: articles
    )
  end

  defp text("invalid_hook_status", _value, _payload, _order),
    do:
      gettext("Frontpad did not accept the webhook statuses, the order statuses will not arrive")

  defp text("invalid_datetime", _value, _payload, order),
    do:
      gettext(
        "Frontpad did not accept the time of the preorder, order %{number} is cooked at once",
        number: order.number
      )

  defp text("invalid_certificate", _value, %{certificate: code}, _order),
    do:
      gettext("Frontpad не применил сертификат %{code}; проверьте сумму заказа",
        code: code || "?"
      )

  defp indexes(value) when is_list(value), do: Enum.flat_map(value, &index/1)
  defp indexes(value) when is_map(value), do: value |> Map.keys() |> Enum.flat_map(&index/1)
  defp indexes(value), do: index(value)

  defp index(value) when is_integer(value), do: [value]

  defp index(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> [int]
      _ -> []
    end
  end

  defp index(_value), do: []
end
