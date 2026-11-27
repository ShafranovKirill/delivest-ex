defmodule DelivestWeb.Staff.ReceiptLive.Printing do
  use DelivestWeb, :live_view

  alias Delivest.{Fiscal, Franchise, Identity, Printing}
  alias Delivest.Printing.Preset

  on_mount {DelivestWeb.Hooks.Permission, "franchise.update"}

  @impl true
  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Чеки и печать",
       can_edit: Identity.can?(socket.assigns.current_staff, "franchise.update"),
       fiscal_enabled: Fiscal.globally_enabled?(),
       legacy_conflict: Printing.legacy_conflict?(),
       sample_branch_id: Map.get(List.first(socket.assigns.staff_branches) || %{}, :id),
       selected: nil,
       dirty: false
     )
     |> assign_settings(Printing.settings())}
  end

  @impl true
  def handle_params(%{"type" => type}, _, socket) when type in ["kitchen", "customer"] do
    kind = String.to_existing_atom(type)
    {:noreply, assign(socket, page: kind, page_title: title(kind), selected: nil)}
  end

  def handle_params(%{"type" => "fiscal"}, _, socket),
    do: {:noreply, assign(socket, page: :fiscal, page_title: "Фискальные чеки")}

  def handle_params(_, _, socket),
    do: {:noreply, assign(socket, page: :index, page_title: "Чеки и печать")}

  @impl true
  def handle_event("fiscal_toggle", _, socket) do
    if socket.assigns.can_edit do
      case Franchise.update_settings(Identity.fresh_staff(socket.assigns.current_staff), %{
             "fiscal_enabled" => !socket.assigns.fiscal_enabled
           }) do
        {:ok, settings} ->
          {:noreply,
           socket
           |> assign(fiscal_enabled: settings.fiscal_enabled)
           |> put_flash(:info, "Настройки сохранены")}

        _ ->
          {:noreply, put_flash(socket, :error, "Не удалось сохранить настройки")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_enabled", %{"type" => type}, socket)
      when type in ["kitchen", "customer"] do
    if socket.assigns.can_edit and not socket.assigns.legacy_conflict do
      key = if type == "kitchen", do: :kitchen_enabled, else: :customer_enabled
      enabled = !Map.fetch!(socket.assigns.settings, key)
      attrs = settings_attrs(%{socket.assigns.settings | key => enabled})

      case Printing.update_settings(socket.assigns.current_staff, attrs) do
        {:ok, saved} ->
          {:noreply,
           socket
           |> assign_settings(saved)
           |> put_flash(:info, "Настройки сохранены")}

        _ ->
          {:noreply, put_flash(socket, :error, "Не удалось сохранить настройки")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("load_branch_template", %{"branch_id" => branch_id}, socket) do
    branch = Enum.find(socket.assigns.staff_branches, &(to_string(&1.id) == branch_id))

    if socket.assigns.can_edit and socket.assigns.legacy_conflict and branch do
      {:noreply,
       socket
       |> assign(sample_branch_id: branch.id, dirty: true)
       |> assign_settings(Printing.settings(branch.id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_block", %{"row" => r, "column" => c, "block" => b}, socket) do
    kind = socket.assigns.page
    indexes = Enum.map([r, c, b], &parse_int(&1, -1))

    with true <- kind in [:kitchen, :customer],
         [r, c, b] when r >= 0 and c >= 0 and b >= 0 <- indexes,
         %{} <-
           get_in(layout(socket.assigns.settings, kind), [
             "rows",
             Access.at(r),
             "columns",
             Access.at(c),
             "blocks",
             Access.at(b)
           ]) do
      {:noreply, assign(socket, selected: {r, c, b})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("layout_action", %{"action" => action} = params, socket) do
    kind = socket.assigns.page

    if socket.assigns.can_edit and kind in [:kitchen, :customer] do
      layout = layout(socket.assigns.settings, kind)
      {updated, selected} = change_layout(layout, action, params, socket.assigns.selected, kind)
      {:noreply, put_layout(socket, kind, updated, selected)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("layout_reorder", %{"rows" => rows}, socket) when is_list(rows) do
    kind = socket.assigns.page

    if socket.assigns.can_edit and kind in [:kitchen, :customer] do
      old = layout(socket.assigns.settings, kind)

      old_blocks =
        for row <- old["rows"], col <- row["columns"], block <- col["blocks"], do: block

      if valid_reorder?(rows, old["rows"], old_blocks) do
        blocks = Map.new(old_blocks, &{&1["id"], &1})

        updated_rows =
          old["rows"]
          |> Enum.with_index()
          |> Enum.map(fn {row, r} ->
            columns =
              row["columns"]
              |> Enum.with_index()
              |> Enum.map(fn {col, c} ->
                put_in(
                  col["blocks"],
                  Enum.map(Enum.at(Enum.at(rows, r, []), c, []), &Map.fetch!(blocks, &1))
                )
              end)

            %{row | "columns" => columns}
          end)

        {:noreply, put_layout(socket, kind, %{old | "rows" => updated_rows}, nil)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("layout_reorder_rows", %{"rows" => order}, socket) when is_list(order) do
    kind = socket.assigns.page

    if socket.assigns.can_edit and kind in [:kitchen, :customer] do
      layout = layout(socket.assigns.settings, kind)
      rows = layout["rows"]
      indexes = Enum.map(order, &parse_int(&1, -1))

      if Enum.sort(indexes) == Enum.to_list(0..(length(rows) - 1)) do
        {:noreply,
         put_layout(
           socket,
           kind,
           %{layout | "rows" => Enum.map(indexes, &Enum.at(rows, &1))},
           nil
         )}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("editor_change", %{"editor" => attrs}, socket) when is_map(attrs) do
    kind = socket.assigns.page

    if socket.assigns.can_edit and kind in [:kitchen, :customer] do
      settings = socket.assigns.settings
      preset = Map.fetch!(settings, kind)
      fields = Map.take(attrs, ["paper", "free_text", "qr_kind", "qr_url"])
      fields = if fields["qr_kind"] == "menu", do: Map.put(fields, "qr_url", nil), else: fields
      changeset = preset_changeset(kind, preset, fields)
      updated = Ecto.Changeset.apply_changes(changeset)
      layout = layout(settings, kind)

      layout =
        case socket.assigns.selected do
          {r, c, b} ->
            block =
              get_in(layout, [
                "rows",
                Access.at(r),
                "columns",
                Access.at(c),
                "blocks",
                Access.at(b)
              ])

            block_attrs =
              Map.take(attrs, ["align", "font_size", "width", "qr_size", "logo_width", "text"])

            block =
              Enum.reduce(block_attrs, block, fn {key, value}, acc ->
                update_block_attr(acc, key, value)
              end)

            put_in(
              layout,
              ["rows", Access.at(r), "columns", Access.at(c), "blocks", Access.at(b)],
              block
            )

          _ ->
            layout
        end

      updated = %{updated | layout: layout}
      {:noreply, assign_settings(socket, Map.put(settings, kind, updated)) |> assign(dirty: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save", _, socket) do
    if socket.assigns.can_edit do
      case Printing.update_settings(
             socket.assigns.current_staff,
             settings_attrs(socket.assigns.settings)
           ) do
        {:ok, saved} ->
          {:noreply,
           socket
           |> assign_settings(saved)
           |> assign(legacy_conflict: false, dirty: false)
           |> put_flash(:info, "Настройки сохранены")}

        {:error, %Ecto.Changeset{}} ->
          {:noreply, put_flash(socket, :error, "Проверьте параметры макета")}

        _ ->
          {:noreply, put_flash(socket, :error, "Не удалось сохранить настройки")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("preview_pdf", _, socket) do
    kind = socket.assigns.page

    case Printing.render_sample(kind, socket.assigns.settings, socket.assigns.sample_branch_id) do
      {:ok, pdf, _paper} ->
        {:noreply,
         push_event(socket, "printing_pdf", %{
           base64: Base.encode64(pdf),
           filename: "#{kind}-sample.pdf"
         })}

      _ ->
        {:noreply, put_flash(socket, :error, "Не удалось подготовить PDF")}
    end
  end

  defp put_layout(socket, kind, layout, selected) do
    settings = socket.assigns.settings
    preset = Map.fetch!(settings, kind)
    preset = %{preset | layout: layout, blocks: Enum.uniq(block_types(layout))}

    socket
    |> assign_settings(Map.put(settings, kind, preset))
    |> assign(selected: selected, dirty: true)
  end

  defp change_layout(layout, "add_row", _, _, _) do
    rows = layout["rows"] ++ [%{"columns" => [%{"width" => 12, "blocks" => []}]}]
    {%{layout | "rows" => rows}, nil}
  end

  defp change_layout(layout, "add_column", %{"row" => r}, _, _) do
    r = parse_int(r, length(layout["rows"]))
    columns = get_in(layout, ["rows", Access.at(r), "columns"])

    if r >= 0 and is_list(columns) and length(columns) < 3 do
      count = length(columns) + 1
      width = div(12, count)

      columns =
        Enum.map(columns, &Map.put(&1, "width", width)) ++
          [%{"width" => 12 - width * (count - 1), "blocks" => []}]

      {put_in(layout, ["rows", Access.at(r), "columns"], columns), nil}
    else
      {layout, nil}
    end
  end

  defp change_layout(layout, "remove_column", %{"row" => r, "column" => c}, _, _) do
    r = parse_int(r, length(layout["rows"]))
    c = parse_int(c, -1)
    columns = get_in(layout, ["rows", Access.at(r), "columns"])

    if r >= 0 and c >= 0 and is_list(columns) and length(columns) > 1 and
         match?(%{"blocks" => []}, Enum.at(columns, c)) do
      columns = List.delete_at(columns, c)
      width = div(12, length(columns))

      columns =
        Enum.with_index(columns)
        |> Enum.map(fn {col, i} ->
          Map.put(col, "width", if(i == length(columns) - 1, do: 12 - width * i, else: width))
        end)

      {put_in(layout, ["rows", Access.at(r), "columns"], columns), nil}
    else
      {layout, nil}
    end
  end

  defp change_layout(layout, "add_block", %{"block" => type}, _, kind) do
    if type in available_blocks(layout, kind) do
      {layout, _} =
        if layout["rows"] == [],
          do: change_layout(layout, "add_row", %{}, nil, kind),
          else: {layout, nil}

      path = ["rows", Access.at(0), "columns", Access.at(0), "blocks"]
      blocks = get_in(layout, path)
      id = if type == "text", do: Ecto.UUID.generate(), else: type
      block = %{"id" => id, "type" => type, "align" => "left", "font_size" => 14, "width" => 12}
      {put_in(layout, path, blocks ++ [block]), {0, 0, length(blocks)}}
    else
      {layout, nil}
    end
  end

  defp change_layout(layout, "remove_block", _, {r, c, b}, _) do
    path = ["rows", Access.at(r), "columns", Access.at(c), "blocks"]
    {put_in(layout, path, List.delete_at(get_in(layout, path), b)), nil}
  end

  defp change_layout(layout, _, _, selected, _), do: {layout, selected}

  defp block_types(layout),
    do:
      for(row <- layout["rows"], col <- row["columns"], block <- col["blocks"], do: block["type"])

  defp available_blocks(layout, kind),
    do: allowed(kind) -- Enum.reject(block_types(layout), &(&1 == "text"))

  defp parse_int(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {i, ""} -> i
      _ -> fallback
    end
  end

  defp parse_int(_, fallback), do: fallback

  defp valid_reorder?(rows, old_rows, old_blocks) do
    length(rows) == length(old_rows) and
      Enum.zip(rows, old_rows)
      |> Enum.all?(fn {columns, old_row} ->
        is_list(columns) and length(columns) == length(old_row["columns"]) and
          Enum.all?(columns, &(is_list(&1) and Enum.all?(&1, fn id -> is_binary(id) end)))
      end) and Enum.sort(List.flatten(rows)) == Enum.sort(Enum.map(old_blocks, & &1["id"]))
  end

  defp update_block_attr(block, "align", value) when value in ["left", "center", "right"],
    do: Map.put(block, "align", value)

  defp update_block_attr(block, "text", value) when is_binary(value),
    do: Map.put(block, "text", String.slice(value, 0, 1000))

  defp update_block_attr(block, key, value)
       when key in ["width", "font_size", "qr_size", "logo_width"] do
    limits = %{
      "width" => 1..12,
      "font_size" => 8..40,
      "qr_size" => 10..100,
      "logo_width" => 10..150
    }

    case parse_int(value, nil) do
      number when is_integer(number) ->
        if number in limits[key], do: Map.put(block, key, number), else: block

      _ ->
        block
    end
  end

  defp update_block_attr(block, _key, _value), do: block

  defp layout(settings, kind) do
    preset = Map.fetch!(settings, kind)

    (Map.get(preset, :layout) || Preset.layout_for(preset.blocks || []))
    |> then(fn layout ->
      update_in(layout["rows"], fn rows ->
        Enum.map(rows, fn row ->
          update_in(row["columns"], fn columns ->
            Enum.map(columns, fn column ->
              update_in(column["blocks"], fn blocks ->
                Enum.map(blocks, &Map.put_new(&1, "id", &1["type"]))
              end)
            end)
          end)
        end)
      end)
    end)
  end

  defp preset_changeset(:kitchen, preset, attrs), do: Preset.kitchen_changeset(preset, attrs)
  defp preset_changeset(:customer, preset, attrs), do: Preset.customer_changeset(preset, attrs)

  defp settings_attrs(settings) do
    %{
      "kitchen_enabled" => settings.kitchen_enabled,
      "customer_enabled" => settings.customer_enabled,
      "kitchen" => preset_attrs(settings.kitchen),
      "customer" => preset_attrs(settings.customer)
    }
  end

  defp preset_attrs(preset) do
    %{
      "blocks" => preset.blocks,
      "layout" => preset.layout,
      "paper" => preset.paper,
      "free_text" => preset.free_text,
      "qr_kind" => preset.qr_kind,
      "qr_url" => preset.qr_url
    }
  end

  defp assign_settings(socket, settings) do
    settings = %{
      settings
      | kitchen: settings.kitchen || Preset.default(:kitchen),
        customer: settings.customer || Preset.default(:customer)
    }

    assign(socket, settings: settings)
  end

  defp allowed(:kitchen), do: Preset.kitchen_blocks()
  defp allowed(:customer), do: Preset.customer_blocks()
  defp label("number"), do: "Номер заказа"
  defp label("readiness"), do: "Время готовности"
  defp label("items"), do: "Позиции и модификаторы"
  defp label("kitchen_comments"), do: "Комментарий для кухни"
  defp label("logo"), do: "Логотип"
  defp label("prices"), do: "Цены"
  defp label("contacts"), do: "Контакты"
  defp label("free_text"), do: "Свободный текст"
  defp label("qr"), do: "QR-код"
  defp label("date"), do: "Дата и время"
  defp label("reference"), do: "Номер и источник"
  defp label("customer_name"), do: "Имя клиента"
  defp label("staff_name"), do: "Сотрудник"
  defp label("address"), do: "Адрес"
  defp label("note"), do: "Примечание"
  defp label("fulfillment"), do: "Тип получения"
  defp label("persons"), do: "Число персон"
  defp label("text"), do: "Текст"
  defp label(_), do: "Блок"

  defp paper_label(:roll58), do: "58 мм"
  defp paper_label(:roll80), do: "80 мм"
  defp paper_label(:a5), do: "A5"
  defp paper_label(_), do: "A4"

  defp sample_preview(_html, %{"type" => "text", "text" => text}) when is_binary(text),
    do: "<section>#{Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(text))}</section>"

  defp sample_preview(html, %{"type" => "qr"} = block) do
    size = round(Map.get(block, "qr_size", 35) * 3.78)
    String.replace(html, "width=130 height=130", "width=#{size} height=#{size}")
  end

  defp sample_preview(html, %{"type" => "logo"} = block) do
    width = Map.get(block, "logo_width", 55)
    String.replace(html, "class=logo", "class=logo style=\"max-width:#{width}mm\"")
  end

  defp sample_preview(html, _), do: html

  defp title(:kitchen), do: "Кухонный талон"
  defp title(:customer), do: "Лист заказа"

  defp kind_enabled?(settings, kind),
    do: Map.fetch!(settings, if(kind == :kitchen, do: :kitchen_enabled, else: :customer_enabled))

  defp fiscal_status(branch) do
    case Fiscal.settings(branch.id) do
      %{mode: :own, enabled: true} -> "АТОЛ включён"
      %{mode: :own} -> "АТОЛ выключен"
      %{mode: :external} -> "Внешняя система"
      _ -> "Не настроен"
    end
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title={@page_title}
      back={if @page == :index, do: ~p"/staff/franchise", else: ~p"/staff/franchise/printing"}
    >
      <:actions :if={@page in [:kitchen, :customer]}>
        <button type="button" phx-click="preview_pdf" class="btn btn-outline btn-sm">Пробный PDF</button>
        <button
          :if={@can_edit}
          id="save-printing"
          type="button"
          phx-click="save"
          phx-disable-with={gettext("Saving...")}
          class="btn btn-primary btn-sm"
        >Сохранить</button>
      </:actions>
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    assigns =
      if assigns[:page] in [:kitchen, :customer] do
        kind = assigns.page
        preset = Map.fetch!(assigns.settings, kind)
        layout = layout(assigns.settings, kind)

        samples =
          Printing.sample_blocks(kind, assigns.settings, assigns.sample_branch_id) |> Map.new()

        selected =
          case assigns.selected do
            {r, c, b} ->
              get_in(layout, [
                "rows",
                Access.at(r),
                "columns",
                Access.at(c),
                "blocks",
                Access.at(b)
              ])

            _ ->
              nil
          end

        assign(assigns,
          kind: kind,
          preset: preset,
          layout: layout,
          samples: samples,
          selected_block: selected
        )
      else
        assigns
      end

    ~H"""
    <div id="printing-settings-page" phx-hook="PrintingPdf" class="space-y-6">
      <div :if={@legacy_conflict} role="alert" class="alert alert-warning">
        <div>
          В филиалах разные шаблоны. Выберите основу: после сохранения шаблон станет общим для всей франшизы.
          <div class="mt-3 flex flex-wrap gap-2">
            <button
              :for={branch <- @staff_branches}
              type="button"
              phx-click="load_branch_template"
              phx-value-branch_id={branch.id}
              class="btn btn-sm btn-outline"
            >{branch.name}</button>
          </div>
        </div>
      </div>
      <%= if @page == :index do %>
        <div class="grid gap-5 lg:grid-cols-3">
          <section id="preset-fiscal" class="card border border-base-300 bg-base-100 shadow-sm">
            <div class="card-body">
              <div class="text-3xl">◉</div>
              <h2 class="card-title">Фискальные чеки</h2>
              <p class="text-sm text-base-content/60">Выпуск чеков и подключение АТОЛ по филиалам</p>
              <div class="mt-3 flex items-center gap-2">
                <span class="badge badge-outline">{if @fiscal_enabled,
                  do: "Включены",
                  else: "Выключены"}</span>
              </div>
              <div class="card-actions mt-auto pt-6">
                <input
                  :if={@can_edit}
                  id="fiscal-toggle"
                  type="checkbox"
                  role="switch"
                  aria-label="Выпуск фискальных чеков"
                  checked={@fiscal_enabled}
                  phx-click="fiscal_toggle"
                  class="toggle toggle-sm toggle-primary self-center"
                />
                <.link navigate={~p"/staff/franchise/printing/fiscal"} class="btn btn-primary btn-sm">Настроить</.link>
              </div>
            </div>
          </section>
          <section
            :for={kind <- [:kitchen, :customer]}
            id={"preset-#{kind}"}
            class="card border border-base-300 bg-base-100 shadow-sm"
          >
            <div class="card-body">
              <div class="text-3xl">{if kind == :kitchen, do: "▤", else: "▧"}</div>
              <h2 class="card-title">{title(kind)}</h2>
              <p class="text-sm text-base-content/60">
                {if kind == :kitchen,
                  do: "Состав и порядок печати для кухни",
                  else: "Макет документа для клиента"}
              </p>
              <div class="mt-3">
                <span class="badge badge-outline">{if kind_enabled?(@settings, kind),
                  do: "Включён",
                  else: "Выключен"}</span>
              </div>
              <div class="card-actions mt-auto pt-6">
                <input
                  :if={@can_edit}
                  type="checkbox"
                  role="switch"
                  aria-label={title(kind)}
                  checked={kind_enabled?(@settings, kind)}
                  phx-click="toggle_enabled"
                  phx-value-type={kind}
                  disabled={@legacy_conflict}
                  class="toggle toggle-sm toggle-primary self-center"
                />
                <.link navigate={~p"/staff/franchise/printing/#{kind}"} class="btn btn-primary btn-sm">Настроить</.link>
              </div>
            </div>
          </section>
        </div>
      <% else %>
        <%= if @page == :fiscal do %>
          <div class="grid gap-3 md:grid-cols-2">
            <.link
              :for={branch <- @staff_branches}
              navigate={~p"/staff/b/#{branch}/integrations/fiscal"}
              class="card border border-base-300 bg-base-100 hover:border-primary"
            ><div class="card-body">
              <h3 class="font-semibold">{branch.name}</h3><span class="badge badge-sm">{fiscal_status(
                branch
              )}</span><span class="link text-sm">Настроить АТОЛ →</span>
            </div></.link>
          </div>
        <% else %>
          <div
            id="printing-editor-workspace"
            class="grid gap-5 lg:min-h-0 lg:flex-1 lg:grid-cols-[175px_minmax(0,1fr)_220px] lg:grid-rows-[minmax(0,1fr)] xl:grid-cols-[220px_minmax(0,1fr)_280px]"
          >
            <aside class="card h-fit border border-base-300 bg-base-100 lg:h-auto lg:overflow-y-auto lg:overscroll-contain">
              <div class="card-body p-4">
                <h2 class="font-semibold">Блоки</h2>
                <button
                  :for={block <- available_blocks(@layout, @kind)}
                  type="button"
                  phx-click="layout_action"
                  phx-value-action="add_block"
                  phx-value-block={block}
                  disabled={not @can_edit}
                  class="btn btn-outline btn-sm justify-start"
                >+ {label(block)}</button>
              </div>
            </aside>
            <div
              class="min-w-0 rounded-2xl bg-base-200/60 p-4 lg:overflow-auto lg:overscroll-contain xl:p-8"
              role="region"
              aria-label="Предпросмотр документа"
              tabindex="0"
            >
              <div
                id={"preview-#{@kind}"}
                class={[
                  "mx-auto min-h-[550px] bg-white text-black shadow-xl ring-1 ring-black/10 transition-all",
                  if(@preset.paper in [:roll58, :roll80],
                    do: "max-w-[330px] p-4",
                    else: "max-w-[620px] p-8"
                  )
                ]}
              >
                <div class="mb-5 flex justify-between border-b pb-3 text-xs text-gray-400">
                  <span>ОБРАЗЕЦ</span><span>{paper_label(@preset.paper)}</span>
                </div>
                <div
                  id="print-layout"
                  phx-hook="SortablePrintLayout"
                  data-type={@kind}
                  class="space-y-3"
                >
                  <div
                    :for={{row, r} <- Enum.with_index(@layout["rows"])}
                    class="print-row space-y-2"
                    data-row={r}
                  >
                    <button
                      :if={@can_edit}
                      type="button"
                      class="row-handle cursor-grab text-xs text-gray-400"
                    >☰ Строка {r + 1}</button>
                    <div class="grid grid-cols-12 gap-2">
                      <div
                        :for={{column, c} <- Enum.with_index(row["columns"])}
                        class="min-w-0"
                        style={"grid-column: span #{column["width"]} / span #{column["width"]}"}
                      >
                        <div
                          class="print-column min-h-20 space-y-2 rounded border border-dashed border-gray-300 p-2"
                          data-column={c}
                          data-row={r}
                        >
                          <button
                            :for={{block, b} <- Enum.with_index(column["blocks"])}
                            type="button"
                            data-id={block["id"]}
                            phx-click="select_block"
                            phx-value-row={r}
                            phx-value-column={c}
                            phx-value-block={b}
                            class={[
                              "print-block group block w-full cursor-grab rounded border p-2 text-left hover:border-blue-500",
                              if(@selected == {r, c, b},
                                do: "border-blue-500 bg-blue-50",
                                else: "border-transparent"
                              )
                            ]}
                          >
                            <span class="mb-1 block text-[10px] font-semibold uppercase tracking-wide text-gray-400">☰ {label(
                              block["type"]
                            )}</span>
                            <span
                              class="block overflow-hidden"
                              style={"text-align: #{block["align"] || "left"}; font-size: #{block["font_size"] || 14}px; width: #{round((block["width"] || 12) * 100 / 12)}%"}
                            >{Phoenix.HTML.raw(
                              sample_preview(Map.get(@samples, block["type"], ""), block)
                            )}</span>
                          </button>
                          <span
                            :if={column["blocks"] == []}
                            class="block py-5 text-center text-xs text-gray-400"
                          >Перетащите блок сюда</span>
                        </div>
                        <button
                          :if={@can_edit and length(row["columns"]) > 1 and column["blocks"] == []}
                          type="button"
                          phx-click="layout_action"
                          phx-value-action="remove_column"
                          phx-value-row={r}
                          phx-value-column={c}
                          class="mt-1 text-xs text-gray-400 hover:text-red-600"
                        >Удалить колонку</button>
                      </div>
                    </div>
                    <button
                      :if={@can_edit and length(row["columns"]) < 3}
                      type="button"
                      phx-click="layout_action"
                      phx-value-action="add_column"
                      phx-value-row={r}
                      class="text-xs text-blue-600"
                    >+ Колонка</button>
                  </div>
                </div>
                <button
                  :if={@can_edit}
                  type="button"
                  phx-click="layout_action"
                  phx-value-action="add_row"
                  class="mt-5 w-full rounded border border-dashed border-gray-300 py-3 text-xs text-gray-500 hover:border-blue-500"
                >+ Строка</button>
              </div>
            </div>
            <aside class="card h-fit border border-base-300 bg-base-100 lg:h-auto lg:overflow-y-auto lg:overscroll-contain">
              <div class="card-body p-4">
                <h3 class="font-semibold">Настройки</h3>
                <form id="editor-settings" phx-change="editor_change" class="space-y-4">
                  <label class="form-control block"><span class="label-text">Формат бумаги</span><select
                    name="editor[paper]"
                    class="select select-bordered select-sm w-full"
                    disabled={not @can_edit}
                  ><option
                    :for={
                      {text, value} <- [
                        {"58 мм", "roll58"},
                        {"80 мм", "roll80"},
                        {"A4", "a4"},
                        {"A5", "a5"}
                      ]
                    }
                    value={value}
                    selected={to_string(@preset.paper) == value}
                  >
                    {text}
                  </option></select></label>
                  <div :if={@selected_block} class="space-y-3 border-t border-base-300 pt-4">
                    <div class="flex items-center justify-between">
                      <h4 class="font-medium">{label(@selected_block["type"])}</h4><button
                        :if={@can_edit}
                        type="button"
                        phx-click="layout_action"
                        phx-value-action="remove_block"
                        class="text-xs text-red-600"
                      >Удалить</button>
                    </div>
                    <label class="form-control block"><span class="label-text">Выравнивание</span><select
                      name="editor[align]"
                      class="select select-bordered select-sm w-full"
                      disabled={not @can_edit}
                    ><option
                      :for={
                        {text, value} <- [
                          {"Слева", "left"},
                          {"По центру", "center"},
                          {"Справа", "right"}
                        ]
                      }
                      value={value}
                      selected={@selected_block["align"] == value}
                    >
                      {text}
                    </option></select></label>
                    <label class="form-control block"><span class="label-text">Размер текста, px</span><input
                      name="editor[font_size]"
                      type="number"
                      min="8"
                      max="48"
                      value={@selected_block["font_size"]}
                      class="input input-bordered input-sm w-full"
                      disabled={not @can_edit}
                    /></label>
                    <label class="form-control block"><span class="label-text">Ширина блока, доли из 12</span><input
                      name="editor[width]"
                      type="number"
                      min="1"
                      max="12"
                      value={@selected_block["width"]}
                      class="input input-bordered input-sm w-full"
                      disabled={not @can_edit}
                    /></label>
                    <label :if={@selected_block["type"] == "qr"} class="form-control block"><span class="label-text">Размер QR, мм</span><input
                      name="editor[qr_size]"
                      type="number"
                      min="10"
                      max="100"
                      value={@selected_block["qr_size"] || 35}
                      class="input input-bordered input-sm w-full"
                      disabled={not @can_edit}
                    /></label>
                    <label :if={@selected_block["type"] == "logo"} class="form-control block"><span class="label-text">Ширина логотипа, мм</span><input
                      name="editor[logo_width]"
                      type="number"
                      min="10"
                      max="150"
                      value={@selected_block["logo_width"] || 55}
                      class="input input-bordered input-sm w-full"
                      disabled={not @can_edit}
                    /></label>
                    <label :if={@selected_block["type"] == "text"} class="form-control block"><span class="label-text">Текст блока</span><textarea
                      name="editor[text]"
                      maxlength="1000"
                      class="textarea textarea-bordered w-full"
                      disabled={not @can_edit}
                    >{@selected_block["text"]}</textarea></label>
                  </div>
                  <div :if={"free_text" in block_types(@layout)} class="border-t border-base-300 pt-4">
                    <label class="form-control block"><span class="label-text">Свободный текст</span><textarea
                      name="editor[free_text]"
                      class="textarea textarea-bordered w-full"
                      disabled={not @can_edit}
                    >{@preset.free_text}</textarea></label>
                  </div>
                  <div
                    :if={"qr" in block_types(@layout)}
                    class="space-y-3 border-t border-base-300 pt-4"
                  >
                    <label class="form-control block"><span class="label-text">Ссылка QR</span><select
                      name="editor[qr_kind]"
                      class="select select-bordered select-sm w-full"
                      disabled={not @can_edit}
                    ><option
                      :for={
                        {text, value} <- [
                          {"Меню филиала", "menu"},
                          {"Отзывы", "review"},
                          {"Своя ссылка", "custom"}
                        ]
                      }
                      value={value}
                      selected={to_string(@preset.qr_kind) == value}
                    >
                      {text}
                    </option></select></label>
                    <label :if={@preset.qr_kind in [:review, :custom]} class="form-control block"><span class="label-text">HTTPS ссылка</span><input
                      name="editor[qr_url]"
                      type="url"
                      value={@preset.qr_url}
                      class="input input-bordered input-sm w-full"
                      disabled={not @can_edit}
                    /></label>
                  </div>
                </form>
                <p :if={@dirty} class="text-xs text-warning">Есть несохранённые изменения</p>
              </div>
            </aside>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
