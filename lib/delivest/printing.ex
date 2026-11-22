defmodule Delivest.Printing do
  @moduledoc "On-demand documents generated from the current order and branch preset."

  alias Delivest.{Identity, Media, Oms}
  alias Delivest.Printing.{Preset, Settings}
  require Logger

  @type pdf_result :: {:ok, binary(), :a4 | :a5} | {:error, :renderer_unavailable}
  @type printing_settings :: %Settings{}

  def settings(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %{info: %{printing: %Settings{} = settings}}} -> settings
      _ -> %Settings{}
    end
  end

  def update_settings(staff, branch_id, attrs) do
    with staff <- Identity.fresh_staff(staff),
         {:ok, branch} <- Identity.get_branch(branch_id, preload: :info),
         {:ok, branch} <- Identity.update_integrations(staff, branch, %{"printing" => attrs}) do
      {:ok, branch.info.printing}
    else
      {:error, :info, changeset} -> {:error, Ecto.Changeset.get_change(changeset, :printing)}
      error -> error
    end
  end

  def allowed?(staff, branch_id, type) when type in [:kitchen, :customer] do
    settings = settings(branch_id)

    Identity.authorize(staff, "orders.read", branch_id) == :ok and
      enabled?(settings, type)
  end

  def allowed?(_, _, _), do: false

  def enabled?(%Settings{} = settings, :kitchen), do: settings.kitchen_enabled
  def enabled?(%Settings{} = settings, :customer), do: settings.customer_enabled

  @spec render_order(term(), binary(), term(), term()) ::
          pdf_result() | {:error, :forbidden | :not_found}
  def render_order(staff, branch_id, order_id, type) when type in [:kitchen, :customer] do
    with true <- allowed?(staff, branch_id, type) || {:error, :forbidden},
         {:ok, uuid} <- Ecto.UUID.cast(order_id),
         %{} = order <- Oms.Orders.get_order(uuid),
         true <- order.branch_id == branch_id || {:error, :not_found} do
      render(order, type, settings(branch_id))
    else
      nil ->
        {:error, :not_found}

      :error ->
        {:error, :not_found}

      {:error, reason} when reason in [:forbidden, :not_found] ->
        {:error, reason}

      error ->
        Logger.error("PDF render failed: #{inspect(error)}")
        {:error, :renderer_unavailable}
    end
  rescue
    error ->
      Logger.error("PDF render failed: #{Exception.message(error)}")
      {:error, :renderer_unavailable}
  end

  def render_order(_, _, _, _), do: {:error, :not_found}

  @spec render(Delivest.Oms.Order.t(), :kitchen | :customer, printing_settings()) :: pdf_result()
  def render(order, type, settings) when type in [:kitchen, :customer] do
    preset = Map.get(settings, type) || Preset.default(type)
    html = html(order, type, preset)
    paper = if type == :customer and preset.paper == :a5, do: :a5, else: :a4

    case ChromicPDF.print_to_pdf({:html, html},
           print_to_pdf: %{preferCSSPageSize: true, printBackground: true}
         ) do
      {:ok, encoded} ->
        {:ok, Base.decode64!(encoded), paper}

      error ->
        Logger.error("PDF render failed: #{inspect(error)}")
        {:error, :renderer_unavailable}
    end
  rescue
    error ->
      Logger.error("PDF render failed: #{Exception.message(error)}")
      {:error, :renderer_unavailable}
  end

  def html(order, type, preset) do
    blocks = preset.blocks || []
    size = if type == :customer and preset.paper == :a5, do: "A5", else: "A4"

    body =
      Enum.map_join(blocks, "", fn block ->
        render_block(type, block, order, preset)
      end)

    """
    <!doctype html><html lang="ru"><head><meta charset="utf-8">
    <style>@page{size:#{size};margin:15mm}body{font:14px 'DejaVu Sans',sans-serif;color:#111}
    h1{font-size:22px}section{margin:0 0 12mm;overflow-wrap:anywhere;white-space:pre-wrap}li{margin:3mm 0;overflow-wrap:anywhere;break-inside:avoid}
    small{color:#555}img.logo{max-width:55mm;max-height:25mm}</style>
    </head><body>#{body}</body></html>
    """
  end

  defp render_block(_type, "number", order, _),
    do: "<section><h1>Заказ № #{escape(order.number)}</h1></section>"

  defp render_block(:kitchen, "readiness", order, _),
    do: "<section>Готовность: #{escape(readiness(order))}</section>"

  defp render_block(type, "items", order, preset) do
    items =
      Enum.map_join(order.items || [], "", fn item ->
        modifiers =
          Enum.map_join(item.modifiers || [], ", ", fn modifier ->
            "#{modifier.quantity} × #{escape(modifier.name)}"
          end)

        price =
          if type == :customer and "prices" in (preset.blocks || []),
            do: " — #{money(item.price * item.quantity)}",
            else: ""

        "<li>#{item.quantity} × #{escape(item.title)}#{price}" <>
          if(modifiers == "", do: "</li>", else: "<br><small>#{modifiers}</small></li>")
      end)

    "<section><h2>#{if type == :kitchen, do: "На кухню", else: "Состав заказа"}</h2><ul>#{items}</ul></section>"
  end

  defp render_block(:kitchen, "kitchen_comments", order, _),
    do: "<section>Комментарий для кухни: #{escape(order.comment)}</section>"

  defp render_block(:customer, "prices", order, _) do
    "<section><b>Итого: #{money(order.total_amount)}</b></section>"
  end

  defp render_block(:customer, "contacts", _order, _) do
    settings = Delivest.Franchise.get_settings()

    "<section>#{escape(settings.name)}<br>#{escape(settings.phone)}<br>#{escape(settings.email)}</section>"
  end

  defp render_block(:customer, "free_text", _order, preset),
    do: "<section>#{escape(preset.free_text)}</section>"

  defp render_block(:customer, "qr", _order, %{qr_url: url, qr_kind: kind})
       when is_binary(url) and url != "" do
    svg = url |> EQRCode.encode() |> EQRCode.svg(width: 180, viewbox: true)
    label = if kind == :feedback, do: "Оставить отзыв", else: "Меню"

    "<section>#{label}<br><img width=130 height=130 src=\"data:image/svg+xml;base64,#{Base.encode64(svg)}\"></section>"
  end

  defp render_block(:customer, "logo", _order, _) do
    case Delivest.Franchise.get_settings().logo_key do
      key when is_binary(key) ->
        case ExAws.S3.get_object(Media.public_bucket(), key) |> ExAws.request() do
          {:ok, %{body: body}} when byte_size(body) <= 500_000 ->
            "<section><img class=logo src=\"data:image/png;base64,#{Base.encode64(body)}\"></section>"

          _ ->
            ""
        end

      _ ->
        ""
    end
  end

  defp render_block(_, _, _, _), do: ""

  defp escape(nil), do: ""

  defp escape(value),
    do: value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp readiness(%{cook_by: nil}), do: "—"

  defp readiness(order),
    do:
      order.cook_by
      |> Delivest.LocalTime.local(order.branch_id)
      |> Calendar.strftime("%d.%m.%Y %H:%M")

  defp money(nil), do: "—"
  defp money(value), do: escape(Delivest.Money.format(value))
end
