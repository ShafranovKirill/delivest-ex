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
       branch_id: branch_id
     )
     |> stream(:stocks, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    branch_id = socket.assigns.branch_id

    case Net.Stocks.list_staff_stocks_for_branch(socket.assigns.current_staff, branch_id) do
      stocks when is_list(stocks) ->
        socket =
          socket
          |> stream(:stocks, stocks, reset: true)
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
    if Identity.can?(socket.assigns.current_staff, "stocks.create") do
      assign(socket, page_title: gettext("Create promotion"), stock: %Stock{})
    else
      socket
      |> put_flash(:error, gettext("You don't have permission to create promotions."))
      |> push_patch(to: ~p"/staff/stocks")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if Identity.can?(socket.assigns.current_staff, "stocks.update") do
      case Repo.get(Stock, id) do
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

  def handle_event("confirm_delete", _, %{assigns: %{stock_to_delete: stock}} = socket) do
    case Net.Stocks.delete_stock(socket.assigns.current_staff, stock) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Promotion deleted successfully"))
         |> stream_delete(:stocks, stock)
         |> assign(stock_to_delete: nil)}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, gettext("Failed to delete promotion"))}
    end
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, stock_to_delete: nil)}
  end

  @impl true
  def handle_event("cancel_media_upload", _params, socket) do
    {:noreply, assign(socket, show_upload_modal: false)}
  end

  @impl true
  def handle_info({StockFormComponent, {:saved, stock}}, socket) do
    action = socket.assigns.live_action

    msg =
      case action do
        :new -> gettext("Promotion created successfully")
        :edit -> gettext("Promotion updated successfully")
        _ -> gettext("Promotion saved successfully")
      end

    {:noreply,
     socket
     |> put_flash(:info, msg)
     |> stream_insert(:stocks, stock)
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
    <div class="space-y-6 p-6">
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-display font-bold text-base-content">{gettext("Promotions")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Manage branch promotions and special offers.")}
          </p>
        </div>
        <div class="flex gap-2">
          <.button
            :if={Identity.can?(@current_staff, "stocks.create")}
            patch={~p"/staff/stocks/new"}
            class="btn btn-primary"
          >
            <.icon name="hero-plus" class="size-5" />
            {gettext("Create Promotion")}
          </.button>
        </div>
      </div>

      <.table id="stocks" rows={@streams.stocks}>
        <:col :let={{_id, stock}} label={gettext("Banner")}>
          <%= if stock.media_id do %>
            <span class="badge badge-outline text-xs">{gettext("Has photo")}</span>
          <% else %>
            <span class="text-xs opacity-40">—</span>
          <% end %>
        </:col>

        <:col :let={{_id, stock}} label={gettext("Description")}>
          <%= if stock.text && stock.text != "" do %>
            <span class="text-sm font-medium">{stock.text}</span>
          <% else %>
            <span class="text-xs opacity-40">—</span>
          <% end %>
        </:col>

        <:col :let={{_id, stock}} label={gettext("Status")}>
          <%= if stock.is_active do %>
            <span class="badge badge-success badge-sm whitespace-nowrap">{gettext("Active")}</span>
          <% else %>
            <span class="badge badge-error badge-sm text-error-content whitespace-nowrap">
              {gettext("Inactive")}
            </span>
          <% end %>
        </:col>

        <:col :let={{_id, stock}} label={gettext("Created At")}>
          <span class="text-sm opacity-60">{Calendar.strftime(stock.inserted_at, "%d.%m.%Y")}</span>
        </:col>

        <:action :let={{_id, stock}}>
          <div class="flex justify-end gap-2">
            <.button
              :if={Identity.can?(@current_staff, "stocks.update")}
              patch={~p"/staff/stocks/#{stock.id}/edit"}
              class="btn btn-ghost btn-xs btn-square"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.button>
            <.button
              :if={Identity.can?(@current_staff, "stocks.delete")}
              phx-click="delete_click"
              phx-value-id={stock.id}
              class="btn btn-ghost btn-xs btn-square text-error hover:bg-error/10"
            >
              <.icon name="hero-trash" class="size-4" />
            </.button>
          </div>
        </:action>
      </.table>

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
