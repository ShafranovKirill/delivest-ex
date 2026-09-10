defmodule DelivestWeb.Staff.StockLive.Stocks do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Repo, Net}
  alias Delivest.Net.Stock
  alias DelivestWeb.Staff.StockLive.StockFormComponent

  on_mount {DelivestWeb.Hooks.Permission, "stocks.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id

    {:ok,
     socket
     |> assign(
       stock_to_delete: nil,
       branch_id: branch_id,
       stocks: []
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    branch_id = socket.assigns.branch_id

    case Net.list_staff_stocks_for_branch(socket.assigns.current_staff, branch_id) do
      stocks when is_list(stocks) ->
        socket =
          socket
          |> assign(stocks: stocks)
          |> apply_action(socket.assigns.live_action, params)

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, push_patch(socket, to: ~p"/staff/stocks")}
    end
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, page_title: gettext("Promotions"), stock: nil)
  end

  defp apply_action(socket, :new, _params) do
    if Identity.can?(socket.assigns.current_staff, "categories.create") or
         Identity.can?(socket.assigns.current_staff, "stocks.create") do
      assign(socket, page_title: gettext("Create promotion"), stock: %Stock{})
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to create promotions."))
      |> push_patch(to: ~p"/staff/stocks")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if Identity.can?(socket.assigns.current_staff, "stocks.update") do
      case Repo.get(Stock, id) |> Repo.preload(:media) do
        %Stock{} = stock ->
          assign(socket, page_title: gettext("Edit promotion"), stock: stock)

        _ ->
          push_patch(socket, to: ~p"/staff/stocks")
      end
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to edit promotions."))
      |> push_patch(to: ~p"/staff/stocks")
    end
  end

  @impl true
  def handle_event(
        "reorder_stock",
        %{"id" => id, "above_order" => above_order, "below_order" => below_order},
        socket
      ) do
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.branch_id

    with %Stock{} = stock <- Repo.get(Stock, id),
         {:ok, _updated} <- Net.update_stock_order(staff, stock, above_order, below_order) do
      stocks = Net.list_staff_stocks_for_branch(staff, branch_id)
      {:noreply, assign(socket, stocks: stocks)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Failed to reorder promotion"))}
    end
  end

  @impl true
  def handle_event("delete_click", %{"id" => id}, socket) do
    if Identity.can?(socket.assigns.current_staff, "stocks.delete") do
      stock = Repo.get(Stock, id)
      {:noreply, assign(socket, stock_to_delete: stock)}
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("You don't have permission to delete promotions."))
       |> push_patch(to: ~p"/staff/stocks")}
    end
  end

  @impl true
  def handle_event(
        "confirm_delete",
        _,
        %{assigns: %{stock_to_delete: stock, branch_id: branch_id}} = socket
      ) do
    case Net.delete_stock(socket.assigns.current_staff, stock) do
      {:ok, _} ->
        stocks = Net.list_staff_stocks_for_branch(socket.assigns.current_staff, branch_id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Promotion deleted successfully"))
         |> assign(stocks: stocks, stock_to_delete: nil)}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, gettext("Failed to delete promotion"))}
    end
  end

  @impl true
  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, stock_to_delete: nil)}
  end

  @impl true
  def handle_event("cancel_media_upload", _params, socket) do
    {:noreply, assign(socket, show_upload_modal: false)}
  end

  @impl true
  def handle_info({StockFormComponent, {:saved, _stock}}, socket) do
    branch_id = socket.assigns.branch_id
    stocks = Net.list_staff_stocks_for_branch(socket.assigns.current_staff, branch_id)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Promotion saved successfully"))
     |> assign(stocks: stocks)
     |> push_patch(to: ~p"/staff/stocks")}
  end

  @impl true
  def handle_info({StockFormComponent, {:open_upload_modal}}, socket) do
    {:noreply, assign(socket, show_upload_modal: true)}
  end

  @impl true
  def handle_info(
        {DelivestWeb.StudioLive.MediaUploadComponent, {:saved, results}},
        socket
      ) do
    handle_media_results(results, socket)
  end

  @impl true
  def handle_info(
        {DelivestWeb.StudioLive.MediaUploadComponent, {:saved, _context_or_id, _type, results}},
        socket
      ) do
    handle_media_results(results, socket)
  end

  defp handle_media_results(results, socket) do
    {successes, _errors} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    media_file =
      case List.first(successes) do
        {:ok, file} -> file
        _ -> nil
      end

    if media_file do
      form_component_id = (socket.assigns.stock && socket.assigns.stock.id) || :new

      send_update(StockFormComponent,
        id: form_component_id,
        uploaded_media: media_file
      )
    end

    {:noreply,
     socket
     |> put_flash(:info, gettext("Image uploaded successfully"))
     |> assign(:show_upload_modal, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 p-6 max-w-4xl mx-auto">
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-display font-bold text-base-content">{gettext("Promotions")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Drag and drop items to reorder promotions.")}
          </p>
        </div>
        <div class="flex gap-2">
          <.link
            :if={Identity.can?(@current_staff, "stocks.create")}
            patch={~p"/staff/stocks/new"}
            class="btn btn-primary"
          >
            <.icon name="hero-plus" class="size-5" />
            {gettext("Create Promotion")}
          </.link>
        </div>
      </div>

      <div id="stocks-list" phx-hook="SortableStocks" class="space-y-3">
        <%= for stock <- @stocks do %>
          <div
            class="flex items-center justify-between p-3 bg-base-100 shadow rounded-xl border border-base-200 cursor-default"
            data-id={stock.id}
            data-order={stock.order}
          >
            <div class="flex items-center gap-4 min-w-0">
              <span class="drag-handle cursor-grab hover:text-primary text-base-content/50 p-1 shrink-0">
                <.icon name="hero-bars-3" class="w-5 h-5" />
              </span>

              <div class="w-16 h-12 rounded-lg bg-base-200 overflow-hidden shrink-0 border border-base-300 flex items-center justify-center">
                <%= if stock.media do %>
                  <img
                    src={Delivest.Media.get_url_from_file(stock.media)}
                    alt=""
                    class="w-full h-full object-cover"
                  />
                <% else %>
                  <.icon name="hero-photo" class="w-6 h-6 opacity-30" />
                <% end %>
              </div>

              <div class="flex flex-col min-w-0">
                <span class="font-medium text-base truncate">
                  <%= if stock.text && stock.text != "" do %>
                    {stock.text}
                  <% else %>
                    <span class="italic opacity-50">{gettext("No description")}</span>
                  <% end %>
                </span>

                <div class="flex items-center gap-2 mt-0.5">
                  <%= if stock.is_active do %>
                    <span class="badge badge-success badge-xs">{gettext("Active")}</span>
                  <% else %>
                    <span class="badge badge-error badge-xs text-error-content">{gettext("Inactive")}</span>
                  <% end %>
                  <span class="text-xs opacity-50">{Calendar.strftime(stock.inserted_at, "%d.%m.%Y")}</span>
                </div>
              </div>
            </div>

            <div class="flex items-center gap-1 shrink-0">
              <.link
                :if={Identity.can?(@current_staff, "stocks.update")}
                patch={~p"/staff/stocks/#{stock.id}/edit"}
                class="btn btn-sm btn-ghost btn-square text-info"
                title={gettext("Edit")}
              >
                <.icon name="hero-pencil-square" class="w-5 h-5" />
              </.link>

              <button
                :if={Identity.can?(@current_staff, "stocks.delete")}
                type="button"
                phx-click="delete_click"
                phx-value-id={stock.id}
                class="btn btn-sm btn-ghost btn-square text-error"
                title={gettext("Delete")}
              >
                <.icon name="hero-trash" class="w-5 h-5" />
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <.slide_over
        id="stock-slideover"
        show={@live_action in [:new, :edit]}
        title={@page_title}
        on_close={JS.patch(~p"/staff/stocks")}
      >
        <.live_component
          :if={@stock}
          module={StockFormComponent}
          id={@stock.id || :new}
          action={@live_action}
          stock={@stock}
          branch_id={@branch_id}
          current_staff={@current_staff}
          patch={~p"/staff/stocks"}
        />
      </.slide_over>

      <%= if assigns[:show_upload_modal] do %>
        <.live_component
          module={DelivestWeb.StudioLive.MediaUploadComponent}
          id="stock-media-upload"
          user_id={@current_staff.id}
          media_group_name={@current_branch.id}
          upload_type="image"
          context="stock"
          is_private={false}
        />
      <% end %>

      <.modal
        id="delete-stock-modal"
        show={@stock_to_delete != nil}
        title={gettext("Delete Promotion")}
        description={
          gettext("Are you sure you want to delete this promotion? This action cannot be undone.")
        }
        confirm_label={gettext("Delete")}
        danger={true}
        on_cancel={JS.push("cancel_delete")}
        on_confirm={JS.push("confirm_delete")}
      />
    </div>
    """
  end
end
