defmodule DelivestWeb.Staff.ProductLive.ProductFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Net}
  alias Delivest.Net.Product

  import Ecto.Changeset

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    current_product_id = socket.assigns[:product] && socket.assigns[:product].id
    new_product_id = assigns.product && assigns.product.id

    if is_nil(socket.assigns[:form]) || current_product_id != new_product_id ||
         socket.assigns[:action] != assigns.action do
      product = assigns.product
      current_staff = assigns.current_staff
      branch_id = assigns.branch_id

      form_data = if product && product.id, do: product, else: %Product{}

      changeset = Product.changeset(form_data, %{})

      category_options =
        case Net.Categories.list_staff_categories_for_branch(current_staff, branch_id) do
          categories when is_list(categories) ->
            Enum.map(categories, &{&1.name, &1.id})

          _ ->
            []
        end

      {:ok,
       socket
       |> assign(:form, to_form(changeset))
       |> assign(:category_options, category_options)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("validate", %{"product" => params}, socket) do
    base_form =
      if socket.assigns.product.id,
        do: socket.assigns.product,
        else: %Product{}

    changeset =
      base_form
      |> Product.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"product" => params}, socket) do
    save_product(socket, socket.assigns.action, params)
  end

  defp save_product(socket, :edit, params),
    do:
      socket.assigns.product
      |> Product.changeset(params)
      |> Map.put(:action, :update)
      |> do_save_product(socket, :edit)

  defp save_product(socket, :new, params),
    do:
      %Product{}
      |> Product.changeset(params)
      |> Map.put(:action, :insert)
      |> do_save_product(socket, :new)

  defp do_save_product(%Ecto.Changeset{valid?: true} = changeset, socket, :edit) do
    params = to_params(changeset)

    case Net.Products.update_product(
           socket.assigns.current_staff,
           socket.assigns.product,
           params
         ) do
      {:ok, product} ->
        notify_parent({:saved, product})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp do_save_product(%Ecto.Changeset{valid?: true} = changeset, socket, :new) do
    params = to_params(changeset)
    branch_id = socket.assigns.branch_id

    case Net.Products.create_product(
           socket.assigns.current_staff,
           branch_id,
           params
         ) do
      {:ok, product} ->
        notify_parent({:saved, product})
        {:noreply, socket}

      {:error, changeset_or_reason} ->
        # Если вернулся changesets или ошибка из Multi
        changeset =
          case changeset_or_reason do
            %Ecto.Changeset{} = cs ->
              cs

            _ ->
              Product.changeset(socket.assigns.product || %Product{}, params)
              |> Map.put(:action, :insert)
          end

        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp do_save_product(%Ecto.Changeset{valid?: false} = changeset, socket, _action) do
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  defp to_params(changeset) do
    data = apply_changes(changeset)

    data
    |> Map.take([:name, :price, :description, :is_active, :external_id, :category_id])
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <.form
        for={@form}
        id="product-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col h-full"
      >
        <div class="flex-1 overflow-y-auto p-6 space-y-6">
          <div class="divider text-xs font-bold uppercase text-base-content/50">
            {gettext("Product Information")}
          </div>

          <.input field={@form[:name]} type="text" label={gettext("Name")} required />

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input field={@form[:price]} type="number" label={gettext("Price")} required />

            <.input
              field={@form[:category_id]}
              type="select"
              label={gettext("Category")}
              options={@category_options}
              prompt={gettext("Select a category...")}
              required
            />
          </div>

          <.input
            field={@form[:description]}
            type="textarea"
            label={gettext("Description")}
            placeholder={gettext("Enter product description...")}
          />

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 items-center pt-2">
            <.input field={@form[:external_id]} type="text" label={gettext("External ID")} />

            <div class="form-control">
              <label class="label cursor-pointer justify-start gap-4 pt-6">
                <input
                  type="hidden"
                  name={@form[:is_active].name}
                  value="false"
                />
                <input
                  type="checkbox"
                  name={@form[:is_active].name}
                  value="true"
                  checked={@form[:is_active].value == true}
                  class="checkbox checkbox-primary"
                />
                <span class="label-text font-bold">{gettext("Active")}</span>
              </label>
            </div>
          </div>
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
