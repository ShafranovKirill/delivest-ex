defmodule DelivestWeb.Staff.ProductLive.CopyComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Identity, Net}

  @impl true
  def update(assigns, socket) do
    targets =
      assigns.current_staff
      |> Identity.list_branch_for_staff()
      |> Enum.reject(&(&1.id == assigns.branch_id))

    {:ok, socket |> assign(assigns) |> assign(targets: targets)}
  end

  @impl true
  def handle_event("copy", %{"target_branch_id" => target_id, "scope" => scope}, socket) do
    %{current_staff: staff, branch_id: branch_id, selected_ids: selected_ids} = socket.assigns
    selection = if scope == "all", do: :all, else: selected_ids

    case Net.copy_products(staff, selection, branch_id, target_id) do
      {:ok, count} ->
        send(self(), {__MODULE__, {:copied, count}})
        {:noreply, socket}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Products were not copied"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.modal
        id="copy-products-modal"
        show={@show}
        title={gettext("Copy products to another branch")}
        description={gettext("Photos and categories are copied, CRM IDs are not.")}
        on_cancel={JS.push("close_copy")}
      >
        <p :if={@targets == []} class="text-sm text-base-content/60">
          {gettext("You have no other branches to copy to.")}
        </p>

        <.form
          :if={@targets != []}
          for={nil}
          id="copy-products-form"
          phx-target={@myself}
          phx-submit="copy"
          class="space-y-4"
        >
          <.input
            type="select"
            name="target_branch_id"
            value={nil}
            label={gettext("Branch")}
            options={Enum.map(@targets, &{&1.name, &1.id})}
          />

          <div class="space-y-2">
            <label class="flex items-center gap-2">
              <input
                type="radio"
                name="scope"
                value="selected"
                class="radio radio-sm"
                checked={@selected_ids != []}
                disabled={@selected_ids == []}
              />
              {gettext("Selected products (%{count})", count: length(@selected_ids))}
            </label>
            <label class="flex items-center gap-2">
              <input
                type="radio"
                name="scope"
                value="all"
                class="radio radio-sm"
                checked={@selected_ids == []}
              />
              {gettext("All products of this branch")}
            </label>
          </div>

          <div class="modal-action">
            <button type="button" class="btn btn-outline btn-sm" phx-click="close_copy">
              {gettext("Cancel")}
            </button>
            <button
              type="submit"
              class="btn btn-primary btn-sm"
              phx-disable-with={gettext("Copying...")}
            >
              {gettext("Copy")}
            </button>
          </div>
        </.form>
      </.modal>
    </div>
    """
  end
end
