defmodule DelivestWeb.Staff.ReceiptLive.Printing do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Printing}
  alias Delivest.Printing.{Preset, Settings}
  alias DelivestWeb.Staff.IntegrationLive.{HealthComponent, Presentation}

  on_mount {DelivestWeb.Hooks.Permission, "integrations.read"}

  @impl true
  def mount(_, _, socket) do
    branch_id = socket.assigns.current_branch.id
    settings = Printing.settings(branch_id)

    {:ok,
     socket
     |> assign(
       page_title: "Чеки и печать",
       can_edit: Identity.can?(socket.assigns.current_staff, "integrations.update"),
       fiscal: Delivest.Fiscal.settings(branch_id),
       context: Presentation.context(branch_id)
     )
     |> assign_settings(settings)}
  end

  def handle_event("fiscal_toggle", _, socket) do
    enabled = not socket.assigns.fiscal.enabled

    case Delivest.Fiscal.update_settings(
           Identity.fresh_staff(socket.assigns.current_staff),
           socket.assigns.current_branch.id,
           %{"enabled" => enabled}
         ) do
      {:ok, fiscal} ->
        {:noreply, socket |> assign(fiscal: fiscal) |> put_flash(:info, "Настройки сохранены")}

      _ ->
        {:noreply, put_flash(socket, :error, "Не удалось сохранить настройки")}
    end
  end

  @impl true
  def handle_event("validate", %{"printing" => attrs}, socket) do
    changeset = Settings.changeset(socket.assigns.settings, normalize(attrs))

    {:noreply,
     socket
     |> assign(settings: Ecto.Changeset.apply_changes(changeset))
     |> assign(form: to_form(%{changeset | action: :validate}, as: "printing"))}
  end

  def handle_event("save", %{"printing" => attrs}, socket) do
    case Printing.update_settings(
           socket.assigns.current_staff,
           socket.assigns.current_branch.id,
           normalize(attrs)
         ) do
      {:ok, settings} ->
        {:noreply, socket |> assign_settings(settings) |> put_flash(:info, "Настройки сохранены")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(%{changeset | action: :update}, as: "printing"))}

      _ ->
        {:noreply, put_flash(socket, :error, "Не удалось сохранить настройки")}
    end
  end

  def handle_event("block", %{"type" => type, "block" => block, "action" => action}, socket)
      when type in ["kitchen", "customer"] and action in ["toggle", "up", "down"] do
    kind = String.to_existing_atom(type)
    allowed = if kind == :kitchen, do: Preset.kitchen_blocks(), else: Preset.customer_blocks()

    if block in allowed do
      settings = socket.assigns.settings
      preset = Map.get(settings, kind) || Preset.default(kind)
      blocks = move(preset.blocks, block, action)
      {:noreply, assign_settings(socket, Map.put(settings, kind, %{preset | blocks: blocks}))}
    else
      {:noreply, socket}
    end
  end

  defp move(blocks, block, "toggle"),
    do: if(block in blocks, do: List.delete(blocks, block), else: blocks ++ [block])

  defp move(blocks, block, direction) do
    index = Enum.find_index(blocks, &(&1 == block))
    target = if direction == "up", do: index && index - 1, else: index && index + 1

    if index && target && target >= 0 && target < length(blocks),
      do: List.replace_at(List.replace_at(blocks, index, Enum.at(blocks, target)), target, block),
      else: blocks
  end

  defp assign_settings(socket, settings) do
    settings = %{
      settings
      | kitchen: settings.kitchen || Preset.default(:kitchen),
        customer: settings.customer || Preset.default(:customer)
    }

    assign(socket,
      settings: settings,
      form: to_form(Settings.changeset(settings, %{}), as: "printing")
    )
  end

  defp block_label("number"), do: "Номер заказа"
  defp block_label("readiness"), do: "Время готовности"
  defp block_label("items"), do: "Позиции и модификаторы"
  defp block_label("kitchen_comments"), do: "Комментарий для кухни"
  defp block_label("logo"), do: "Логотип"
  defp block_label("prices"), do: "Цены"
  defp block_label("contacts"), do: "Контакты"
  defp block_label("free_text"), do: "Свободный текст"
  defp block_label("qr"), do: "QR код"
  defp fiscal_toggle_label(%{enabled: true}), do: "✓ Выпуск новых чеков включён"
  defp fiscal_toggle_label(_), do: "Включить выпуск новых чеков"

  defp normalize(attrs) do
    Enum.reduce(["kitchen", "customer"], attrs, fn kind, acc ->
      update_in(acc, [kind], fn
        nil ->
          %{"blocks" => []}

        preset ->
          Map.update(preset, "blocks", [], fn
            blocks when is_list(blocks) -> Enum.reject(blocks, &(&1 == ""))
            other -> other
          end)
      end)
    end)
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      title="Чеки и печать"
      subtitle="Настройки печати текущего филиала"
    >
      <:actions>
        <.link navigate={~p"/staff/b/#{@current_branch}/finance/receipts"} class="btn btn-ghost">Журнал чеков</.link>
      </:actions>
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="printing-settings-page" class="space-y-6">
      <section class="card bg-base-100 border border-base-300 p-5">
        <h2 class="text-lg font-semibold">Фискальные чеки</h2>
        <p>
          Источник: {if @fiscal.mode == :own,
            do: "АТОL Online",
            else: if(@fiscal.mode == :external, do: "Внешняя система", else: "Не настроен")}
        </p>
        <button
          :if={@can_edit}
          id="fiscal-toggle"
          type="button"
          phx-click="fiscal_toggle"
          class="btn btn-outline mt-2"
        >
          {fiscal_toggle_label(@fiscal)}
        </button>
        <p>
          Выпуск через АТОЛ для собственных платежей. Чеки внешних систем выпускает их владелец. Отключение останавливает новые чеки продажи; история, незавершённые операции и возвраты по зарегистрированным чекам сохраняются.
        </p>
        <.link
          navigate={~p"/staff/b/#{@current_branch}/integrations/fiscal"}
          class="btn btn-outline mt-3"
        >Настроить АТОЛ и проверить соединение</.link>
        <.live_component
          module={HealthComponent}
          id="printing-fiscal-health"
          provider={:atol}
          branch_id={@current_branch.id}
          staff={@current_staff}
          context={@context}
        />
      </section>
      <.form
        for={@form}
        id="printing-settings"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.input
          field={@form[:kitchen_enabled]}
          type="checkbox"
          label="Кухонный талон"
          disabled={not @can_edit}
        />
        <.input
          field={@form[:customer_enabled]}
          type="checkbox"
          label="Лист заказа для клиента"
          disabled={not @can_edit}
        />
        <section
          :for={kind <- [:kitchen, :customer]}
          id={"preset-#{kind}"}
          class="card bg-base-100 border border-base-300 p-5 space-y-3"
        >
          <h2 class="font-semibold">
            {if kind == :kitchen, do: "Кухонный талон", else: "Лист заказа для клиента"}
          </h2>
          <.inputs_for :let={preset} field={@form[kind]}>
            <input type="hidden" name={"printing[#{kind}][blocks][]"} value="" />
            <input
              :for={block <- @settings |> Map.get(kind) |> Map.get(:blocks)}
              type="hidden"
              name={"printing[#{kind}][blocks][]"}
              value={block}
            />
            <div
              :for={block <- Map.get(@settings, kind).blocks}
              class="flex items-center gap-2"
            >
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="block"
                phx-value-type={kind}
                phx-value-block={block}
                phx-value-action="toggle"
                disabled={not @can_edit}
              >
                ✓ {block_label(block)}
              </button>
              <button
                :if={block in Map.get(@settings, kind).blocks}
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="block"
                phx-value-type={kind}
                phx-value-block={block}
                phx-value-action="up"
                disabled={not @can_edit}
              >↑</button>
              <button
                :if={block in Map.get(@settings, kind).blocks}
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="block"
                phx-value-type={kind}
                phx-value-block={block}
                phx-value-action="down"
                disabled={not @can_edit}
              >↓</button>
            </div>
            <div :for={
              block <-
                if(kind == :kitchen, do: Preset.kitchen_blocks(), else: Preset.customer_blocks()) --
                  Map.get(@settings, kind).blocks
            }>
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="block"
                phx-value-type={kind}
                phx-value-block={block}
                phx-value-action="toggle"
                disabled={not @can_edit}
              >+ {block_label(block)}</button>
            </div>
            <div :if={kind == :customer} class="space-y-3">
              <.input
                field={preset[:paper]}
                type="select"
                label="Формат"
                options={[{"A4", :a4}, {"A5", :a5}]}
                disabled={not @can_edit}
              />
              <.input
                field={preset[:free_text]}
                type="textarea"
                label="Свободный текст"
                disabled={not @can_edit}
              />
              <.input
                field={preset[:qr_kind]}
                type="select"
                label="QR"
                options={[{"Меню", :menu}, {"Отзывы", :feedback}]}
                disabled={not @can_edit}
              />
              <.input
                field={preset[:qr_url]}
                type="url"
                label="HTTPS ссылка QR"
                disabled={not @can_edit}
              />
            </div>
          </.inputs_for>
          <a
            :if={@can_edit}
            id={"preview-#{kind}"}
            href={~p"/staff/b/#{@current_branch}/printing/#{kind}/demo"}
            target="_blank"
            rel="noopener"
            class="link"
          >Предпросмотр сохранённого шаблона и тестовая печать</a>
        </section>
        <button :if={@can_edit} id="save-printing" type="submit" class="btn btn-primary">Сохранить</button>
      </.form>
    </div>
    """
  end
end
