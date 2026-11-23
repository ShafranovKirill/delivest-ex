defmodule Delivest.Printing do
  @moduledoc "On-demand documents generated from the current order and branch preset."

  alias Delivest.{Franchise, Identity, Media, Oms, Repo}
  alias Delivest.Printing.{Preset, Settings}
  require Logger

  @type pdf_result ::
          {:ok, binary(), :a4 | :a5 | :roll58 | :roll80} | {:error, :renderer_unavailable}
  @type printing_settings :: %Settings{}

  def settings do
    normalize_legacy_qr(Franchise.get_settings().printing || %Settings{})
  end

  def global_active?, do: match?(%Settings{}, Franchise.get_settings().printing)

  def legacy_conflict? do
    not global_active?() and
      match?(
        {:ok, %{rows: [[count]]}} when count > 1,
        Ecto.Adapters.SQL.query(Repo, "SELECT COUNT(DISTINCT printing) FROM branch_info", [])
      )
  end

  def settings(branch_id) do
    global = Franchise.get_settings().printing

    if global do
      normalize_legacy_qr(global)
    else
      legacy_settings(branch_id)
    end
  end

  defp legacy_settings(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, %{info: %{printing: %Settings{} = settings}}} -> normalize_legacy_qr(settings)
      _ -> %Settings{}
    end
  end

  defp normalize_legacy_qr(%Settings{customer: %Preset{qr_kind: :feedback} = preset} = settings),
    do: %{settings | customer: %{preset | qr_kind: :review}}

  defp normalize_legacy_qr(
         %Settings{customer: %Preset{qr_kind: :menu, qr_url: url} = preset} = settings
       )
       when is_binary(url) and url != "",
       do: %{settings | customer: %{preset | qr_kind: :custom}}

  defp normalize_legacy_qr(settings), do: settings

  def update_settings(staff, attrs) do
    case Franchise.update_settings(Identity.fresh_staff(staff), %{"printing" => attrs}) do
      {:ok, franchise} ->
        {:ok, franchise.printing}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Ecto.Changeset.get_change(changeset, :printing) || changeset}

      error ->
        error
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
    with {:ok, order} <- authorized_order(staff, branch_id, order_id, type) do
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

  def render_order_html(staff, branch_id, order_id, type) when type in [:kitchen, :customer] do
    with {:ok, order} <- authorized_order(staff, branch_id, order_id, type) do
      preset = Map.get(settings(branch_id), type) || Preset.default(type)
      {:ok, html(order, type, preset, branch_id)}
    end
  end

  def render_order_html(_, _, _, _), do: {:error, :not_found}

  defp authorized_order(staff, branch_id, order_id, type) do
    with true <- allowed?(staff, branch_id, type) || {:error, :forbidden},
         {:ok, uuid} <- Ecto.UUID.cast(order_id),
         %{} = order <- Oms.Orders.get_order(uuid),
         true <- order.branch_id == branch_id || {:error, :not_found} do
      {:ok, order}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  @spec render(Delivest.Oms.Order.t(), :kitchen | :customer, printing_settings()) :: pdf_result()
  def render(order, type, settings) when type in [:kitchen, :customer] do
    preset = Map.get(settings, type) || Preset.default(type)
    html = html(order, type, preset, order.branch_id)
    paper = preset.paper || :a4

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
  catch
    :exit, reason ->
      Logger.error("PDF renderer exited: #{inspect(reason)}")
      {:error, :renderer_unavailable}
  end

  def html(order, type, preset), do: html(order, type, preset, Map.get(order, :branch_id))

  def html(order, type, preset, branch_id) do
    size = paper_size(preset.paper)

    body =
      if preset.layout,
        do: render_layout(type, preset.layout, order, preset, branch_id),
        else:
          Enum.map_join(
            preset.blocks || [],
            "",
            &render_block(type, &1, order, preset, branch_id)
          )

    """
    <!doctype html><html lang="ru"><head><meta charset="utf-8">
    <style>@page{size:#{size};margin:#{paper_margin(preset.paper)}}body{font:14px 'DejaVu Sans',sans-serif;color:#111}
    h1{font-size:1.55em}.print-row{display:flex;align-items:flex-start}.print-row.single{display:block}.print-column{min-width:0;flex:none}.print-block{box-sizing:border-box;overflow-wrap:anywhere;white-space:pre-wrap}.print-block section{margin:0 0 5mm}.print-block table{width:100%;border-collapse:collapse}.print-block thead{display:table-header-group}.print-block tr{break-inside:avoid}section{margin:0 0 12mm;overflow-wrap:anywhere;white-space:pre-wrap}li{margin:3mm 0;overflow-wrap:anywhere;break-inside:avoid}
    small{color:#555}img.logo{max-width:55mm;max-height:25mm}@media screen{body{max-width:#{screen_width(preset.paper)};margin:16px auto;padding:12px;box-shadow:0 0 8px #ccc}}</style>
    </head><body data-paper="#{preset.paper || :a4}">#{body}</body></html>
    """
  end

  defp paper_size(:a5), do: "A5"
  defp paper_size(:roll58), do: "58mm 200mm"
  defp paper_size(:roll80), do: "80mm 200mm"
  defp paper_size(_), do: "A4"
  defp paper_margin(paper) when paper in [:roll58, :roll80], do: "3mm"
  defp paper_margin(_), do: "15mm"
  defp screen_width(:a5), do: "148mm"
  defp screen_width(:roll58), do: "58mm"
  defp screen_width(:roll80), do: "80mm"
  defp screen_width(_), do: "210mm"

  defp render_layout(type, %{"rows" => rows}, order, preset, branch_id) do
    Enum.map_join(rows, "", fn %{"columns" => columns} ->
      single? = length(columns) == 1

      columns_html =
        Enum.map_join(columns, "", fn column ->
          width = column["width"] || 12

          blocks =
            Enum.map_join(column["blocks"] || [], "", fn block ->
              render_layout_block(type, block, order, preset, branch_id)
            end)

          if single? and width == 12,
            do: blocks,
            else: "<div class=print-column style=\"width:#{width * 100 / 12}%\">#{blocks}</div>"
        end)

      "<div class=\"print-row #{if single?, do: "single", else: ""}\">#{columns_html}</div>"
    end)
  end

  defp render_layout(_, _, _, _, _), do: ""

  defp render_layout_block(type, block, order, preset, branch_id) do
    kind = block["type"]

    content =
      if kind == "text",
        do: "<section>#{escape(block["text"] || preset.free_text)}</section>",
        else: render_block(type, kind, order, preset, branch_id)

    align = block["align"] || "left"
    font_size = block["font_size"] || 14
    width = block["width"] || 12
    content = if kind == "qr", do: resize_qr(content, block["qr_size"] || 35), else: content

    content =
      if kind == "logo", do: resize_logo(content, block["logo_width"] || 55), else: content

    "<div class=print-block style=\"text-align:#{align};font-size:#{font_size}px;width:#{width * 100 / 12}%\">#{content}</div>"
  end

  defp resize_qr(content, size),
    do:
      String.replace(
        content,
        "width=130 height=130",
        "style=\"width:#{size}mm;height:auto;max-width:100%;aspect-ratio:1/1\""
      )

  defp resize_logo(content, size),
    do: String.replace(content, "class=logo", "class=logo style=\"max-width:#{size}mm\"")

  def sample_html(type, %Settings{} = settings, branch_id \\ nil)
      when type in [:kitchen, :customer] do
    html(
      sample_order(branch_id),
      type,
      Map.get(settings, type) || Preset.default(type),
      branch_id
    )
  end

  def sample_blocks(type, %Settings{} = settings, branch_id \\ nil)
      when type in [:kitchen, :customer] do
    preset = Map.get(settings, type) || Preset.default(type)
    order = sample_order(branch_id)

    Enum.map(preset.blocks || [], fn block ->
      {block, render_block(type, block, order, preset, branch_id)}
    end)
  end

  def render_sample(type, %Settings{} = settings, branch_id \\ nil)
      when type in [:kitchen, :customer] do
    render(sample_order(branch_id), type, settings)
  end

  defp sample_order(branch_id) do
    %Oms.Order{
      number: "123",
      branch_id: branch_id,
      cook_by: ~U[2026-11-23 11:30:00Z],
      comment: "Без лука. Пожалуйста, упакуйте отдельно.",
      total_amount: 74_500,
      items: [
        %Oms.OrderItem{
          title: "Пицца Маргарита",
          quantity: 2,
          price: 34_000,
          modifiers: [%Oms.OrderItemModifier{name: "Дополнительная моцарелла", quantity: 1}]
        },
        %Oms.OrderItem{title: "Чай облепиховый", quantity: 1, price: 6500, modifiers: []}
      ]
    }
  end

  defp render_block(_type, "number", order, _, _),
    do: "<section><h1>Заказ № #{escape(order.number)}</h1></section>"

  defp render_block(:kitchen, "readiness", order, _, _),
    do: "<section>Готовность: #{escape(readiness(order))}</section>"

  defp render_block(type, "items", order, preset, _) do
    items =
      Enum.map_join(order.items || [], "", fn item ->
        modifiers =
          Enum.map_join(item.modifiers || [], ", ", fn modifier ->
            "#{modifier.quantity} × #{escape(modifier.name)}"
          end)

        price =
          if type == :customer and preset_has_block?(preset, "prices"),
            do: " — #{money(item.price * item.quantity)}",
            else: ""

        "<tr><td>#{item.quantity} × #{escape(item.title)}#{price}" <>
          if(modifiers == "", do: "</td></tr>", else: "<br><small>#{modifiers}</small></td></tr>")
      end)

    title = if type == :kitchen, do: "На кухню", else: "Состав заказа"

    "<section><table><thead><tr><th style=\"text-align:left\">#{title}</th></tr></thead><tbody>#{items}</tbody></table></section>"
  end

  defp render_block(:customer, "customer_name", order, _, _),
    do: labeled("Клиент", order.customer_name)

  defp render_block(type, "staff_name", order, _, _) when type in [:customer, :kitchen] do
    name =
      with id when is_binary(id) <- order.staff_id,
           {:ok, %{name: name}} <- Identity.get_staff(id),
           do: name,
           else: (_ -> nil)

    labeled("Сотрудник", name)
  end

  defp render_block(_type, "date", order, _, _) do
    value =
      if order.inserted_at,
        do:
          order.inserted_at
          |> Delivest.LocalTime.local(order.branch_id)
          |> Calendar.strftime("%d.%m.%Y %H:%M"),
        else: nil

    labeled("Дата", value)
  end

  defp render_block(_type, "reference", order, _, _),
    do: labeled("Номер", order.number)

  defp render_block(:customer, "address", order, _, _) do
    address = order.address

    value =
      if address,
        do:
          address.formatted ||
            Enum.filter([address.city, address.street, address.house], &(&1 && &1 != ""))
            |> Enum.join(", "),
        else: nil

    labeled("Адрес", value)
  end

  defp render_block(:customer, "note", order, _, _), do: labeled("Примечание", order.comment)

  defp render_block(:customer, "fulfillment", order, _, _),
    do: labeled("Тип получения", fulfillment_label(order.fulfillment_type))

  defp render_block(:customer, "persons", order, _, _), do: labeled("Персон", order.persons)

  defp render_block(_type, "text", _order, preset, _),
    do: "<section>#{escape(preset.free_text)}</section>"

  defp render_block(:kitchen, "kitchen_comments", order, _, _),
    do: "<section>Комментарий для кухни: #{escape(order.comment)}</section>"

  defp render_block(:customer, "prices", order, _, _) do
    "<section><b>Итого: #{money(order.total_amount)}</b></section>"
  end

  defp render_block(:customer, "contacts", _order, _, branch_id) do
    franchise = Franchise.get_settings()
    branch = branch_context(branch_id)
    name = if branch, do: branch.name, else: franchise.name
    phone = if branch, do: branch.info && branch.info.phone_number, else: nil
    address = if branch, do: branch.info && branch.info.address, else: nil

    [name, address, phone || franchise.phone, franchise.email]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("<br>", &escape/1)
    |> then(&"<section>#{&1}</section>")
  end

  defp render_block(:customer, "free_text", _order, preset, _),
    do: "<section>#{escape(preset.free_text)}</section>"

  defp render_block(:customer, "qr", _order, preset, branch_id) do
    url = qr_url(preset, branch_id)

    if is_binary(url) and url != "" do
      svg = url |> EQRCode.encode() |> EQRCode.svg(width: 180, viewbox: true)
      label = if preset.qr_kind in [:review, :feedback], do: "Оставить отзыв", else: "Меню"

      "<section>#{label}<br><img width=130 height=130 src=\"data:image/svg+xml;base64,#{Base.encode64(svg)}\"></section>"
    else
      ""
    end
  end

  defp render_block(:customer, "logo", _order, _, _) do
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

  defp render_block(_, _, _, _, _), do: ""

  defp labeled(_, nil), do: ""
  defp labeled(_, ""), do: ""
  defp labeled(label, value), do: "<section>#{label}: #{escape(value)}</section>"

  defp fulfillment_label(:delivery), do: "Доставка"
  defp fulfillment_label(:pickup), do: "Самовывоз"
  defp fulfillment_label(:dine_in), do: "В зале"
  defp fulfillment_label(_), do: nil

  defp preset_has_block?(%Preset{layout: %{"rows" => rows}}, kind) do
    Enum.any?(rows, fn row ->
      Enum.any?(row["columns"] || [], fn column ->
        Enum.any?(column["blocks"] || [], &(&1["type"] == kind))
      end)
    end)
  end

  defp preset_has_block?(preset, kind), do: kind in (preset.blocks || [])

  defp qr_url(%{qr_kind: :menu}, branch_id) do
    with %{slug: slug} when is_binary(slug) <- branch_context(branch_id),
         origin when is_binary(origin) <- Application.get_env(:delivest, :client_origin),
         %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) <-
           URI.parse(origin) do
      String.trim_trailing(origin, "/") <> "/" <> URI.encode(slug)
    else
      _ -> nil
    end
  end

  defp qr_url(%{qr_url: url}, _) when is_binary(url) and url != "", do: url
  defp qr_url(_, _), do: nil

  defp branch_context(nil), do: nil

  defp branch_context(branch_id) do
    case Identity.get_branch(branch_id, preload: :info) do
      {:ok, branch} -> branch
      _ -> nil
    end
  end

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
