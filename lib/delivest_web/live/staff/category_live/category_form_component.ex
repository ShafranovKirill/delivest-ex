defmodule DelivestWeb.Staff.CategoryLive.CategoryFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.Net
  alias Delivest.Net.Category

  use Gettext, backend: DelivestWeb.Gettext

  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @impl true
  def update(%{category: category} = assigns, socket) do
    changeset = Category.changeset(category, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(changeset))}
  end

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @impl true
  def handle_event("validate", %{"category" => category_params}, socket) do
    changeset =
      socket.assigns.category
      |> Category.changeset(category_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"category" => category_params}, socket) do
    save_category(socket, socket.assigns.action, category_params)
  end

  defp save_category(socket, :edit, category_params) do
    staff = socket.assigns.current_staff
    category = socket.assigns.category

    case Net.update_category(staff, category, category_params) do
      {:ok, updated_category} ->
        notify_parent({:saved, updated_category})

        {:noreply,
         socket
         |> put_flash(:info, gettext("Category updated successfully"))
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_category(socket, :new, category_params) do
    staff = socket.assigns.current_staff
    branch_id = socket.assigns.branch_id

    # Передаем staff, branch_id и attrs в соответствии с нашей функцией создания
    case Net.create_category(staff, branch_id, category_params) do
      {:ok, created_category} ->
        notify_parent({:saved, created_category})

        {:noreply,
         socket
         |> put_flash(:info, gettext("Category created successfully"))
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <.form
        for={@form}
        id="category-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col h-full"
      >
        <div class="flex-1 overflow-y-auto p-6 space-y-6">
          <.input
            field={@form[:name]}
            type="text"
            label={gettext("Category Name")}
            required
            autofocus
          />
        </div>

        <div class="shrink-0 p-6 border-t border-base-200 bg-base-100 flex justify-end gap-3">
          <.link patch={@patch} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
            {gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
