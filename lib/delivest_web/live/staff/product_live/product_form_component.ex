defmodule DelivestWeb.Staff.ProductLive.ProductFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Media, Money, Net}
  alias Delivest.Integrations.Crm
  alias Delivest.Net.Product

  import Ecto.Changeset
  import DelivestWeb.Staff.ProductLive.ProductTags, only: [tag_checkboxes: 1]

  alias DelivestWeb.Staff.ProductLive.ProductTags

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
              no_category_option = {gettext("Without category"), ""}
              mapped_categories = Enum.map(categories, &{&1.name, &1.id})
              [no_category_option | mapped_categories]

            _ ->
              [{gettext("Without category"), ""}]
          end

        current_media = if product, do: Media.get_file(product.media_id), else: nil

        socket =
          socket
          |> assign(:form, to_form(changeset))
          |> assign(:category_options, category_options)
          |> assign(:crm_owner, Crm.menu_owner(branch_id, product && product.id))
          |> assign(:product_tags, Net.list_product_tags())
          |> assign(:modifier_groups, Delivest.Net.Modifiers.list_groups())
          |> assign(
            :modifier_group_ids,
            if(product && product.id, do: Delivest.Net.Modifiers.group_ids(product.id), else: [])
          )
          |> assign(:crm_providers, Crm.providers())
          |> assign(:current_media, current_media)
          |> assign(:show_upload_modal, false)

        {:ok, socket}
      else
        {:ok, socket}
      end
    end
  end

  @impl true
  def handle_event("validate", %{"product" => params}, socket) do
    base_form =
      if socket.assigns.product.id,
        do: socket.assigns.product,
        else: %Product{}

    normalized_params = normalize_params(params)

    changeset =
      base_form
      |> Product.changeset(normalized_params)
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
  def handle_event("save", %{"product" => params} = event, socket) do
    socket =
      assign(
        socket,
        :modifier_group_ids,
        Enum.reject(List.wrap(event["modifier_group_ids"]), &(&1 == ""))
      )

    params =
      params
      |> Map.put_new("category_id", nil)
      |> normalize_params()

    save_product_with_params(socket, socket.assigns.action, params)
  end

  defp normalize_params(params) do
    params = ProductTags.without_blank(params)

    case params["category_id"] do
      "" -> Map.put(params, "category_id", nil)
      _ -> params
    end
  end

  defp save_product_with_params(socket, :edit, normalized_params) do
    socket.assigns.product
    |> Product.changeset(normalized_params)
    |> Map.put(:action, :update)
    |> do_save_product(socket, :edit)
  end

  defp save_product_with_params(socket, :new, normalized_params) do
    %Product{}
    |> Product.changeset(normalized_params)
    |> Map.put(:action, :insert)
    |> do_save_product(socket, :new)
  end

  defp do_save_product(%Ecto.Changeset{valid?: true} = changeset, socket, :edit) do
    params = to_params(changeset)

    case Net.update_product(
           socket.assigns.current_staff,
           socket.assigns.product,
           params
         ) do
      {:ok, product} ->
        Delivest.Net.Modifiers.attach(
          socket.assigns.current_staff,
          product.id,
          socket.assigns.modifier_group_ids
        )

        notify_parent({:saved, product})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp do_save_product(%Ecto.Changeset{valid?: true} = changeset, socket, :new) do
    params = to_params(changeset)
    branch_id = socket.assigns.branch_id

    case Net.create_product(
           socket.assigns.current_staff,
           branch_id,
           params
         ) do
      {:ok, product} ->
        Delivest.Net.Modifiers.attach(
          socket.assigns.current_staff,
          product.id,
          socket.assigns.modifier_group_ids
        )

        notify_parent({:saved, product})
        {:noreply, socket}

      {:error, changeset_or_reason} ->
        {changeset, error_message} =
          case changeset_or_reason do
            %Ecto.Changeset{} = cs ->
              {cs, gettext("Please check the fields below.")}

            :forbidden ->
              cs =
                Product.changeset(socket.assigns.product || %Product{}, params)
                |> Map.put(:action, :insert)

              {cs, gettext("You don't have permission to perform this action.")}

            other_error ->
              cs =
                Product.changeset(socket.assigns.product || %Product{}, params)
                |> Map.put(:action, :insert)

              {cs, "#{gettext("Failed to save product:")} #{inspect(other_error)}"}
          end

        {:noreply,
         socket
         |> put_flash(:error, error_message)
         |> assign(socket.assigns, form: to_form(changeset))}
    end
  end

  defp do_save_product(%Ecto.Changeset{valid?: false} = changeset, socket, _action) do
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  defp to_params(changeset) do
    data = apply_changes(changeset)

    data
    |> Map.take([
      :name,
      :old_price,
      :price,
      :description,
      :quantity,
      :weight,
      :measure_unit,
      :calories,
      :proteins,
      :fats,
      :carbohydrates,
      :excise,
      :is_active,
      :crm_ids,
      :category_id,
      :media_id,
      :slug,
      :tags,
      :stars_price,
      :stars_reward,
      :suggested
    ])
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

          <input type="hidden" name={@form[:media_id].name} value={@form[:media_id].value} />

          <div class="form-control w-full">
            <label class="label">
              <span class="label-text font-bold">{gettext("Product Image")}</span>
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

          <p :if={@crm_owner} id="product-crm-owner" class="text-sm text-base-content/60">
            {gettext("Name, price and weight come from %{crm}", crm: @crm_owner)}
          </p>

          <.input
            field={@form[:name]}
            type="text"
            label={gettext("Name")}
            required
            disabled={@crm_owner != nil}
          />

          <div>
            <.input
              field={@form[:slug]}
              type="text"
              label={gettext("URL slug")}
              placeholder={Delivest.Slug.slugify(@form[:name].value) || "hinkali"}
            />
            <p class="text-xs text-base-content/60 mt-1">
              {gettext(
                "Used in the product link on the website. Leave empty to generate it from the name."
              )}
            </p>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:price]}
              type="text"
              inputmode="decimal"
              value={Money.input(@form[:price].value)}
              label={gettext("Price")}
              required
              disabled={@crm_owner != nil}
            />

            <p class="text-xs text-base-content/60 sm:self-end sm:pb-3">
              {gettext("Discounts are set in «Discounts & promo codes» by the product URL slug.")}
            </p>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input field={@form[:quantity]} type="number" label={gettext("Quantity")} />

            <div class="grid grid-cols-[1fr_6rem] gap-2">
              <.input
                field={@form[:weight]}
                type="number"
                label={gettext("Weight")}
                disabled={@crm_owner != nil}
              />
              <.input
                field={@form[:measure_unit]}
                type="select"
                label={gettext("Unit")}
                options={[{gettext("g"), "g"}, {gettext("ml"), "ml"}]}
              />
            </div>
          </div>

          <div>
            <span class="label-text font-bold">{gettext("Nutrition per 100 g")}</span>
            <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
              <.input field={@form[:calories]} type="number" step="any" label={gettext("Calories")} />
              <.input field={@form[:proteins]} type="number" step="any" label={gettext("Proteins")} />
              <.input field={@form[:fats]} type="number" step="any" label={gettext("Fats")} />
              <.input
                field={@form[:carbohydrates]}
                type="number"
                step="any"
                label={gettext("Carbohydrates")}
              />
            </div>
          </div>

          <.input
            field={@form[:excise]}
            type="select"
            label={gettext("Excise")}
            options={[
              {gettext("Sugary drink"), "sugary_drink"},
              {gettext("Other excise goods"), "other"}
            ]}
            prompt={gettext("No excise")}
          />

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:category_id]}
              type="select"
              label={gettext("Category")}
              options={@category_options}
              prompt={gettext("Select a category...")}
            />

            <.input
              :for={{provider, name} <- @crm_providers}
              id={"product-crm-id-#{provider}"}
              name={"product[crm_ids][#{provider}]"}
              value={Map.get(@form[:crm_ids].value || %{}, to_string(provider))}
              type="text"
              label={gettext("%{crm} ID", crm: name)}
              errors={Enum.map(@form[:crm_ids].errors, &translate_error/1)}
            />
          </div>

          <.input
            field={@form[:description]}
            type="textarea"
            label={gettext("Description")}
            placeholder={gettext("Enter product description...")}
          />

          <.tag_checkboxes field={@form[:tags]} tags={@product_tags} branch={@current_branch} />

          <fieldset :if={@modifier_groups != []} class="space-y-2">
            <legend class="label-text font-bold">{gettext("Modifiers")}</legend>
            <input type="hidden" name="modifier_group_ids[]" value="" />
            <div class="flex flex-wrap gap-2">
              <label
                :for={group <- @modifier_groups}
                class="flex items-center gap-2 rounded-full border border-base-300 px-3 py-1.5 cursor-pointer has-checked:border-primary has-checked:bg-primary/10"
              >
                <input
                  type="checkbox"
                  name="modifier_group_ids[]"
                  value={group.id}
                  checked={group.id in @modifier_group_ids}
                  class="checkbox checkbox-xs checkbox-primary"
                />
                <span class="text-sm">{group.name}</span>
              </label>
            </div>
          </fieldset>

          <div>
            <.input
              field={@form[:stars_price]}
              type="number"
              min="1"
              label={gettext("Price in stars")}
            />
            <.input
              field={@form[:stars_reward]}
              type="number"
              min="0"
              label={gettext("Extra stars per product")}
            />
            <.input
              field={@form[:suggested]}
              type="checkbox"
              label={gettext("Suggest in the cart")}
            />
            <p class="text-xs text-base-content/60 mt-1">
              {gettext("Offered in the «Add to your order» block when it is not in the cart yet.")}
            </p>
          </div>

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
