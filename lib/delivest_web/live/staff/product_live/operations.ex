defmodule DelivestWeb.Staff.ProductLive.Operations do
  use DelivestWeb, :live_view
  alias Delivest.{Identity, Net.ProductOperations}
  alias Delivest.Net.ProductWorkbook

  on_mount {DelivestWeb.Hooks.Permission, "products.read"}

  @impl true
  def mount(params, _session, socket) do
    selected_ids =
      case Map.get(params, "ids") do
        ids when is_list(ids) ->
          ids
          |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1)))
          |> Enum.uniq()
          |> Enum.take(1000)

        _ ->
          []
      end

    targets =
      socket.assigns.current_staff
      |> Identity.list_branch_for_staff()
      |> Enum.reject(&(&1.id == socket.assigns.current_branch.id))

    {:ok,
     socket
     |> assign(
       page_title: "Товарные операции",
       targets: targets,
       selected_ids: selected_ids,
       return_params:
         Map.take(params, ~w(search page page_size order_by order_directions filters stopped)),
       preview: nil,
       operation: nil,
       error: nil,
       summary: nil,
       applying: false,
       workbook_headers: Enum.join(ProductWorkbook.headers(), ", ")
     )
     |> allow_upload(:workbook,
       accept: ~w(.xlsx),
       max_entries: 1,
       max_file_size: ProductWorkbook.limits().compressed
     )}
  end

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("preview_import", _params, socket) do
    case consume_uploaded_entries(socket, :workbook, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [binary] ->
        set_preview(
          socket,
          ProductOperations.import_preview(
            socket.assigns.current_staff,
            socket.assigns.current_branch.id,
            binary
          ),
          :import
        )

      _ ->
        {:noreply, assign(socket, error: "Выберите файл .xlsx размером до 5 МБ")}
    end
  end

  def handle_event("preview_copy", %{"target_branch_id" => target_id}, socket) do
    set_preview(
      socket,
      ProductOperations.copy_preview(
        socket.assigns.current_staff,
        if(socket.assigns.selected_ids == [], do: :all, else: socket.assigns.selected_ids),
        socket.assigns.current_branch.id,
        target_id
      ),
      :copy
    )
  end

  def handle_event("apply", _params, %{assigns: %{preview: nil}} = socket) do
    {:noreply,
     assign(socket, error: "Предпросмотр устарел. Подготовьте его заново.", applying: false)}
  end

  def handle_event("apply", params, socket) do
    socket = assign(socket, applying: true)

    choices =
      socket.assigns.preview.rows
      |> Enum.reduce(%{}, fn row, acc ->
        case get_in(params, ["choices", to_string(row.line)]) do
          choice when choice in ["skip", "update"] ->
            Map.put(acc, row.values["source_key"], choice)

          _ ->
            acc
        end
      end)

    case ProductOperations.apply_changes(
           Identity.fresh_staff(socket.assigns.current_staff),
           socket.assigns.preview,
           choices
         ) do
      {:ok, summary} ->
        {:noreply,
         socket
         |> assign(preview: nil, summary: summary, error: nil, applying: false)
         |> push_event("staff:form-saved", %{})}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           error: "Не удалось применить: #{human_error(reason)}. Обновите предпросмотр.",
           applying: false
         )}
    end
  end

  defp set_preview(socket, {:ok, preview}, operation),
    do:
      {:noreply, assign(socket, preview: preview, operation: operation, error: nil, summary: nil)}

  defp set_preview(socket, {:error, reason}, _),
    do:
      {:noreply,
       assign(socket, error: "Ошибка предпросмотра: #{human_error(reason)}", preview: nil)}

  defp human_error({:row, line, reason}), do: "строка #{line}: #{human_error(reason)}"
  defp human_error([reason | _]), do: human_error(reason)
  defp human_error(:stale_preview), do: "данные изменились после предпросмотра"
  defp human_error(:stale_source), do: "исходный товар изменился"
  defp human_error(:forbidden), do: "недостаточно прав"
  defp human_error(:forbidden_category), do: "нет права создать категорию"
  defp human_error(:crm_owned_menu), do: "каталогом целевого филиала управляет CRM"
  defp human_error(:same_branch), do: "выберите другой филиал"
  defp human_error(:invalid_product_fields), do: "проверьте поля товара и цену"
  defp human_error(:missing_measure_unit), do: "укажите единицу измерения"
  defp human_error(:invalid_boolean), do: "логическое поле должно быть true или false"
  defp human_error(:invalid_integer), do: "ожидается целое число"
  defp human_error(:invalid_number), do: "ожидается число"
  defp human_error(:invalid_tags), do: "теги должны быть массивом JSON из строк"
  defp human_error(:invalid_category_reference), do: "категория недоступна"
  defp human_error(:invalid_modifier_reference), do: "группа модификаторов недоступна"

  defp human_error(:forbidden_modifier_reference),
    do: "нет права читать группы модификаторов целевого филиала"

  defp human_error(:invalid_media_reference), do: "фотография недоступна"
  defp human_error(:shared_or_forbidden_target), do: "общий товар нельзя обновить"
  defp human_error(:deleted_target), do: "товар с этим ключом удалён в целевом филиале"

  defp human_error(:invalid_source_keys),
    do: "ключи товаров пусты, повторяются или слишком длинные"

  defp human_error(:invalid_header), do: "заголовок не соответствует шаблону v1"
  defp human_error(:unsafe_xml), do: "файл содержит небезопасное содержимое"
  defp human_error(:invalid_archive_entries), do: "файл содержит недопустимые элементы"
  defp human_error(:workbook_too_large), do: "книга превышает допустимый размер"
  defp human_error(:file_too_large), do: "файл превышает 5 МБ"
  defp human_error(:too_many_rows), do: "в книге больше 1000 товаров"
  defp human_error(:invalid_relationships), do: "не найден лист Products или есть внешние связи"
  defp human_error(_), do: "проверьте файл и права доступа"

  defp row_status(:new), do: "новый"
  defp row_status(:match), do: "совпадение по ключу"
  defp row_status(:error), do: "ошибка"

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title="Товарные операции"
      subtitle="Экспорт, импорт и копирование товаров филиала"
    >
      <:actions>
        <.link
          id="product-operations-back"
          navigate={~p"/staff/b/#{@current_branch}/products?#{@return_params}"}
          class="btn btn-ghost"
        >{gettext("Back to products")}</.link>
      </:actions>
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <div class="grid gap-4 lg:grid-cols-3">
        <section id="workbook-export" class="rounded-xl border border-base-300 p-5 space-y-3">
          <h2 class="font-semibold">Экспорт Excel</h2>
          <p class="text-sm text-base-content/60">
            Шаблон v1: {@workbook_headers}. Денежные значения указаны в рублях; CRM ID не переносится.
          </p>
          <.link href={~p"/staff/b/#{@current_branch}/products/workbook"} class="btn btn-outline">Скачать .xlsx</.link>
        </section>
        <section id="workbook-import" class="rounded-xl border border-base-300 p-5 space-y-3">
          <h2 class="font-semibold">Импорт Excel</h2>
          <p class="text-sm text-base-content/60">
            До 5 МБ и 1000 строк. source_key обязателен; для новых строк укажите постоянный ключ SKU.
          </p>
          <.form
            for={nil}
            id="workbook-upload-form"
            phx-submit="preview_import"
            phx-change="validate_upload"
          >
            <.live_file_input upload={@uploads.workbook} class="file-input w-full" />
            <button
              type="submit"
              class="btn btn-primary mt-3"
              phx-disable-with="Чтение файла..."
            >Предпросмотр</button>
          </.form>
          <p :for={entry <- @uploads.workbook.entries} class="text-xs">
            {entry.client_name}: {entry.progress}%
          </p>
        </section>
        <section id="product-copy" class="rounded-xl border border-base-300 p-5 space-y-3">
          <h2 class="font-semibold">Копирование</h2>
          <p :if={@selected_ids != []} class="text-sm text-base-content/60">
            Выбрано товаров: {length(@selected_ids)}
          </p>
          <.form for={nil} id="copy-preview-form" phx-submit="preview_copy">
            <.input
              type="select"
              name="target_branch_id"
              value={nil}
              label="Целевой филиал"
              options={Enum.map(@targets, &{&1.name, &1.id})}
            />
            <button
              type="submit"
              class="btn btn-primary mt-3"
              disabled={@targets == []}
              phx-disable-with="Подготовка..."
            >Предпросмотр</button>
          </.form>
        </section>
      </div>
      <p :if={@error} id="operations-error" class="alert alert-error">{@error}</p>
      <p :if={@summary} id="operations-result" class="alert alert-success">
        Создано: {@summary.created}, обновлено: {@summary.updated}, пропущено: {@summary.skipped}
      </p>
      <section
        :if={@preview}
        id="operations-preview"
        class="rounded-xl border border-base-300 p-5 space-y-4"
      >
        <h2 class="font-semibold">
          Предпросмотр: новых {Map.get(@preview.counts, :new, 0)}, совпадений {Map.get(
            @preview.counts,
            :match,
            0
          )}, ошибок {Map.get(@preview.counts, :error, 0)}
        </h2>
        <.form for={nil} id="operations-apply-form" data-staff-dirty phx-submit="apply">
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Строка</th><th>Товар</th><th>Ключ</th><th>Состояние</th><th>Действие</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @preview.rows} id={"operation-row-#{row.line}"}>
                  <td>{row.line}</td><td>{row.values["name"]}</td><td>
                    {row.values["source_key"]}
                  </td><td>
                    {row_status(row.status)}{if row.errors != [], do: ": #{human_error(row.errors)}"}
                  </td>
                  <td>
                    <select
                      :if={row.status == :match}
                      name={"choices[#{row.line}]"}
                      class="select select-sm"
                    ><option value="skip">Пропустить</option><option
                      value="update"
                      disabled={!row.update_allowed}
                    >
                      Обновить
                    </option></select>
                    <span
                      :if={row.status == :match and not row.update_allowed}
                      class="text-xs text-base-content/60"
                    >Обновление недоступно: нет права или товар общий для филиалов</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <button
            type="submit"
            class="btn btn-primary mt-4"
            disabled={Map.get(@preview.counts, :error, 0) > 0 or @applying}
            phx-disable-with="Применение..."
          >Применить</button>
        </.form>
      </section>
    </div>
    """
  end
end
