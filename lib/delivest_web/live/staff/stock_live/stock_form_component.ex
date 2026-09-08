defmodule DelivestWeb.Staff.StockLive.StockFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Net, Media}
  alias Delivest.Net.Stock

  import Ecto.Changeset

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if uploaded_media = assigns[:uploaded_media] do
      changeset =
        socket.assigns.form.source
        |> Ecto.Changeset.put_change(:media_id, uploaded_media.id)

      {:ok,
       socket
       |> assign(:form, to_form(changeset))
       |> assign(:current_media, uploaded_media)
       |> assign(:show_upload_modal, false)}
    else
      current_stock_id = socket.assigns[:stock] && socket.assigns[:stock].id
      new_stock_id = assigns.stock && assigns.stock.id

      if is_nil(socket.assigns[:form]) || current_stock_id != new_stock_id ||
           socket.assigns[:action] != assigns.action do
        stock = assigns.stock

        form_data = if stock && stock.id, do: stock, else: %Stock{}
        changeset = Stock.changeset(form_data, %{})

        current_media = if stock && stock.media_id, do: Media.get_file(stock.media_id), else: nil

        socket =
          socket
          |> assign(:form, to_form(changeset))
          |> assign(:current_media, current_media)
          |> assign(:show_upload_modal, false)

        {:ok, socket}
      else
        {:ok, socket}
      end
    end
  end

  @impl true
  def handle_event("validate", %{"stock" => params}, socket) do
    base_form =
      if socket.assigns.stock.id,
        do: socket.assigns.stock,
        else: %Stock{}

    changeset =
      base_form
      |> Stock.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("open_upload_modal", _, socket) do
    notify_parent({:open_upload_modal})
    {:noreply, socket}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :show_upload_modal, false)}
  end

  @impl true
  def handle_event("save", %{"stock" => params}, socket) do
    save_stock_with_params(socket, socket.assigns.action, params)
  end

  defp save_stock_with_params(socket, :edit, params) do
    socket.assigns.stock
    |> Stock.changeset(params)
    |> Map.put(:action, :update)
    |> do_save_stock(socket, :edit)
  end

  defp save_stock_with_params(socket, :new, params) do
    %Stock{}
    |> Stock.changeset(params)
    |> Map.put(:action, :insert)
    |> do_save_stock(socket, :new)
  end

  defp do_save_stock(%Ecto.Changeset{valid?: true} = changeset, socket, :edit) do
    params = to_params(changeset)

    case Net.Stocks.update_stock(
           socket.assigns.current_staff,
           socket.assigns.stock,
           params
         ) do
      {:ok, stock} ->
        notify_parent({:saved, stock})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp do_save_stock(%Ecto.Changeset{valid?: true} = changeset, socket, :new) do
    params = to_params(changeset)
    branch_id = socket.assigns.branch_id

    case Net.Stocks.create_stock(
           socket.assigns.current_staff,
           branch_id,
           params
         ) do
      {:ok, stock} ->
        notify_parent({:saved, stock})
        {:noreply, socket}

      {:error, changeset_or_reason} ->
        {changeset, error_message} =
          case changeset_or_reason do
            %Ecto.Changeset{} = cs ->
              {cs, gettext("Please check the fields below.")}

            :forbidden ->
              cs =
                Stock.changeset(socket.assigns.stock || %Stock{}, params)
                |> Map.put(:action, :insert)

              {cs, gettext("You don't have permission to perform this action.")}

            other_error ->
              cs =
                Stock.changeset(socket.assigns.stock || %Stock{}, params)
                |> Map.put(:action, :insert)

              {cs, "#{gettext("Failed to save promotion:")} #{inspect(other_error)}"}
          end

        {:noreply,
         socket
         |> put_flash(:error, error_message)
         |> assign(form: to_form(changeset))}
    end
  end

  defp do_save_stock(%Ecto.Changeset{valid?: false} = changeset, socket, _action) do
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  defp to_params(changeset) do
    data = apply_changes(changeset)

    data
    |> Map.take([:text, :media_id, :is_active])
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <.form
        for={@form}
        id="stock-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col h-full"
      >
        <div class="flex-1 overflow-y-auto p-6 space-y-6">
          <div class="divider text-xs font-bold uppercase text-base-content/50">
            {gettext("Promotion Information")}
          </div>

          <input type="hidden" name={@form[:media_id].name} value={@form[:media_id].value} />

          <div class="form-control w-full">
            <label class="label">
              <span class="label-text font-bold">{gettext("Banner Image")}</span>
            </label>

            <div class="flex items-center gap-4">
              <div class="avatar">
                <div class="w-24 h-24 rounded-box bg-base-200 border border-base-300 flex items-center justify-center overflow-hidden">
                  <%= if url = Media.get_url(@current_media && @current_media.id) do %>
                    <img src={url} class="w-full h-full object-cover" />
                  <% else %>
                    <span class="text-xs text-base-content/40">{gettext("No image")}</span>
                  <% end %>
                </div>
              </div>

              <div class="flex-1">
                <button
                  type="button"
                  phx-click="open_upload_modal"
                  phx-target={@myself}
                  class="btn btn-outline btn-sm"
                >
                  <.icon name="hero-photo" class="size-4 mr-1" />
                  {if @current_media, do: gettext("Change Image"), else: gettext("Upload Image")}
                </button>
                <p class="text-xs text-base-content/60 mt-1">
                  {gettext("PNG, JPG, WEBP up to 5MB")}
                </p>
              </div>
            </div>
          </div>

          <.input
            field={@form[:text]}
            type="textarea"
            label={gettext("Description")}
            placeholder={gettext("Enter promotion details...")}
          />

          <.input field={@form[:is_active]} type="checkbox" label={gettext("Active")} />
        </div>

        <div class="shrink-0 p-6 border-t border-base-200 bg-base-100 flex justify-end gap-3">
          <.link patch={@patch} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button
            type="submit"
            class="btn btn-primary"
            phx-disable-with={gettext("Saving...")}
          >
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
