defmodule DelivestWeb.Staff.ProductLive.ProductFormComponent do
  use DelivestWeb, :live_component

  alias Delivest.{Gateway, Identity, Media, Money, Net, Repo}
  alias Delivest.Identity.Branch
  alias Delivest.Identity.Staff
  alias Delivest.Integrations.Crm
  alias Delivest.Net.{Product, ProductCrmIds}
  alias Delivest.Net.SharedOwnership

  import Ecto.Changeset
  import Ecto.Query

  import DelivestWeb.Staff.FoundationComponents,
    only: [form_section: 1, error_summary: 1, changeset_errors: 1]

  import DelivestWeb.Staff.ProductLive.ProductTags, only: [tag_checkboxes: 1]

  alias DelivestWeb.Staff.ProductLive.ProductTags

  @editable_fields ~w(name old_price price description quantity weight measure_unit calories proteins fats carbohydrates excise is_active category_id media_id slug tags stars_price stars_reward suggested)a
  @advanced_fields ~w(quantity weight measure_unit calories proteins fats carbohydrates excise tags suggested stars_price stars_reward crm_ids slug)a

  @impl true
  def update(assigns, socket) do
    previous_product_id = socket.assigns[:product] && socket.assigns[:product].id
    previous_action = socket.assigns[:action]
    previous_version = socket.assigns[:form_version]

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:save_error, fn -> nil end)
      |> assign_new(:conflict?, fn -> false end)

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
      new_product_id = assigns.product && assigns.product.id

      if is_nil(socket.assigns[:form]) || previous_product_id != new_product_id ||
           previous_action != assigns.action || previous_version != assigns[:form_version] do
        product = assigns.product
        current_staff = assigns.current_staff
        branch_id = assigns.branch_id

        form_data = if product && product.id, do: product, else: %Product{is_active: false}
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
        provider = Crm.active_provider(assigns.current_branch)
        saved_ids = (product && product.crm_ids) || %{}
        providers = Crm.providers()
        active_providers = Enum.filter(providers, fn {key, _} -> key == provider end)

        unused_providers =
          Enum.filter(providers, fn {key, _} ->
            key != provider and Map.get(saved_ids, to_string(key)) not in [nil, ""]
          end)

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
          |> assign(
            :original_modifier_group_ids,
            if(product && product.id, do: Delivest.Net.Modifiers.group_ids(product.id), else: [])
          )
          |> assign(:active_crm_providers, active_providers)
          |> assign(:unused_crm_providers, unused_providers)
          |> assign(:current_media, current_media)
          |> assign(:show_upload_modal, false)
          |> assign(:save_error, nil)
          |> assign(:conflict?, false)
          |> assign(:advanced_open, assigns.action in [:edit, :show])

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
        else: %Product{is_active: false}

    normalized_params = normalize_params(params)

    changeset =
      base_form
      |> Product.changeset(normalized_params)
      |> Map.put(:action, :validate)

    advanced_errors? = Enum.any?(changeset.errors, fn {field, _} -> field in @advanced_fields end)

    {:noreply,
     assign(socket,
       form: to_form(changeset),
       save_error: nil,
       conflict?: false,
       advanced_open: socket.assigns.advanced_open or advanced_errors?
     )}
  end

  def handle_event("toggle_advanced", _, socket) do
    {:noreply, assign(socket, advanced_open: not socket.assigns.advanced_open)}
  end

  def handle_event("open_upload_modal", _, socket) do
    unless socket.assigns[:readonly], do: notify_parent({:open_upload_modal})
    {:noreply, socket}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :show_upload_modal, false)}
  end

  def handle_event("reload_latest", _, socket) do
    notify_parent(:reload_requested)
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"product" => params} = event, socket) do
    if socket.assigns[:readonly], do: {:noreply, socket}, else: save_event(params, event, socket)
  end

  defp save_event(params, event, socket) do
    socket =
      if Map.has_key?(event, "modifier_group_ids") do
        assign(
          socket,
          :modifier_group_ids,
          Enum.reject(List.wrap(event["modifier_group_ids"]), &(&1 == ""))
        )
      else
        socket
      end

    params =
      params
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
    %Product{is_active: false}
    |> Product.changeset(normalized_params)
    |> Map.put(:action, :insert)
    |> do_save_product(socket, :new)
  end

  defp do_save_product(%Ecto.Changeset{valid?: true} = changeset, socket, :edit) do
    params = changeset |> changed_params() |> Map.put("branch_id", socket.assigns.branch_id)
    result = update_current_product(socket, params)

    case result do
      {:ok, product} ->
        notify_parent({:saved, product})
        {:noreply, push_event(socket, "staff:form-saved", %{id: "product-form"})}

      {:error, %Ecto.Changeset{} = error_changeset} ->
        {:noreply, assign_error_form(socket, error_changeset)}

      {:error, :forbidden} ->
        message = gettext("You don't have permission to perform this action.")
        form = changeset |> add_error(:name, message) |> to_form()
        {:noreply, socket |> assign(form: form, save_error: message)}

      {:error, :conflict} ->
        {:noreply,
         assign(socket,
           form: to_form(changeset),
           conflict?: true,
           save_error:
             gettext(
               "This product changed after you opened it. Review the latest version before saving again."
             )
         )}

      {:error, :crm_owned} ->
        {:noreply,
         assign(socket,
           form: to_form(changeset),
           save_error: gettext("Name, price and weight are managed by the connected CRM.")
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save product"))}
    end
  end

  defp do_save_product(%Ecto.Changeset{valid?: true} = changeset, socket, :new) do
    params = to_params(changeset)
    branch_id = socket.assigns.branch_id

    result =
      Repo.transaction(fn ->
        actor = Identity.fresh_staff(socket.assigns.current_staff)

        branch =
          case Repo.get(Branch, branch_id) do
            nil -> nil
            found -> Repo.preload(found, :info)
          end

        with %Staff{} <- actor,
             %Branch{} <- branch,
             false <- Gateway.crm?(branch, :menu),
             {:ok, product} <- Net.create_product(actor, branch_id, params),
             {:ok, _} <-
               maybe_attach_groups(
                 actor,
                 product.id,
                 socket.assigns.modifier_group_ids,
                 []
               ) do
          product
        else
          true -> Repo.rollback(:forbidden)
          nil -> Repo.rollback(:forbidden)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, product} ->
        notify_parent({:saved, product})
        {:noreply, push_event(socket, "staff:form-saved", %{id: "product-form"})}

      {:error, changeset_or_reason} ->
        {changeset, error_message} =
          case changeset_or_reason do
            %Ecto.Changeset{} = cs ->
              {cs, gettext("Please check the fields below.")}

            :forbidden ->
              cs =
                Product.changeset(socket.assigns.product || %Product{is_active: false}, params)
                |> Map.put(:action, :insert)

              {cs, gettext("You don't have permission to perform this action.")}

            _other_error ->
              cs =
                Product.changeset(socket.assigns.product || %Product{is_active: false}, params)
                |> Map.put(:action, :insert)

              {cs, gettext("Failed to save product")}
          end

        {:noreply,
         socket
         |> put_flash(:error, error_message)
         |> assign_error_form(changeset)}
    end
  end

  defp do_save_product(%Ecto.Changeset{valid?: false} = changeset, socket, _action) do
    {:noreply, assign_error_form(socket, changeset)}
  end

  defp assign_error_form(socket, changeset) do
    advanced_errors? = Enum.any?(changeset.errors, fn {field, _} -> field in @advanced_fields end)

    assign(socket,
      form: to_form(changeset),
      advanced_open: socket.assigns.advanced_open or advanced_errors?
    )
  end

  defp update_current_product(socket, params) do
    baseline = socket.assigns.product
    branch_id = socket.assigns.branch_id
    selected_groups = socket.assigns.modifier_group_ids
    original_groups = socket.assigns.original_modifier_group_ids

    Repo.transaction(fn ->
      staff = Identity.fresh_staff(socket.assigns.current_staff)

      current =
        Product
        |> where([p], p.id == ^baseline.id and is_nil(p.deleted_at))
        |> lock("FOR UPDATE")
        |> preload(:external_ids)
        |> Repo.one()

      current_groups = if current, do: Delivest.Net.Modifiers.group_ids(current.id), else: []

      with %Staff{} <- staff,
           %Product{} <- current,
           {:ok, _} <- Net.get_branch_product(branch_id, current.id),
           true <- same_baseline?(baseline, current, branch_id),
           true <- MapSet.new(current_groups) == MapSet.new(original_groups),
           :ok <- crm_edit_permission(current, branch_id, params),
           :ok <- group_permission(staff, current.id, selected_groups, current_groups),
           {:ok, saved} <- Net.update_product(staff, current, params),
           {:ok, _} <- maybe_attach_groups(staff, saved.id, selected_groups, current_groups) do
        saved
      else
        false -> Repo.rollback(:conflict)
        nil -> Repo.rollback(:conflict)
        {:error, :not_found} -> Repo.rollback(:conflict)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp same_baseline?(baseline, current, branch_id) do
    Map.take(baseline, @editable_fields) == Map.take(current, @editable_fields) and
      baseline.crm_ids == ProductCrmIds.load(current, branch_id).crm_ids
  end

  defp crm_edit_permission(current, branch_id, params) do
    if Crm.menu_owner(branch_id, current.id) &&
         Enum.any?(~w(name price weight), fn field ->
           Map.has_key?(params, field) &&
             Map.get(params, field) != Map.get(current, String.to_existing_atom(field))
         end) do
      {:error, :crm_owned}
    else
      :ok
    end
  end

  defp group_permission(_staff, _id, selected, current) when selected == current, do: :ok

  defp group_permission(staff, id, _selected, _current),
    do: SharedOwnership.authorize(staff, "products.update", "Product", id)

  defp maybe_attach_groups(_staff, _id, selected, current) when selected == current,
    do: {:ok, :unchanged}

  defp maybe_attach_groups(staff, id, selected, _current),
    do: Delivest.Net.Modifiers.attach(staff, id, selected)

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

  defp changed_params(changeset) do
    changeset.changes
    |> Map.take(@editable_fields ++ [:crm_ids])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <p
        :if={@save_error}
        id="product-save-error"
        role="alert"
        class="m-4 rounded-lg border border-red-300 bg-red-50 p-3 text-sm text-red-700"
      >
        {@save_error}
      </p>
      <button
        :if={@conflict? && @action == :edit}
        id="product-reload-latest"
        type="button"
        phx-click="reload_latest"
        phx-target={@myself}
        class="btn btn-outline mx-4"
      >{gettext("Load latest version")}</button>
      <.form
        for={@form}
        id="product-form"
        phx-target={@myself}
        phx-change={if @readonly, do: nil, else: "validate"}
        data-staff-dirty={if @readonly, do: nil, else: true}
        phx-submit={if @readonly, do: nil, else: "save"}
        class={["flex flex-col h-full", @readonly && "product-readonly-form"]}
      >
        <fieldset disabled={@readonly} class="min-w-0 flex-1 overflow-y-auto p-6 space-y-6">
          <.error_summary
            :if={not @readonly}
            id="product-error-summary"
            errors={changeset_errors(@form.source)}
            form_name={@form.name}
          />
          <.form_section id="product-main-section" title={gettext("Basics")}>
            <input type="hidden" name={@form[:media_id].name} value={@form[:media_id].value} />

            <div class="form-control w-full">
              <label class="label">
                <span class="label-text font-bold">{gettext("Product Image")}</span>
              </label>

              <div class="flex items-center gap-4">
                <div class="avatar">
                  <div class="w-24 h-24 rounded-box bg-base-200 border border-base-300 flex items-center justify-center overflow-hidden">
                    <%= if url = Media.get_url(@current_media && @current_media.id) do %>
                      <img
                        src={url}
                        alt={gettext("Product Image")}
                        class="w-full h-full object-cover"
                      />
                    <% else %>
                      <span class="text-xs text-base-content/40">{gettext("No image")}</span>
                    <% end %>
                  </div>
                </div>

                <div :if={not @readonly} class="flex-1">
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

            <.input
              field={@form[:category_id]}
              type="select"
              label={gettext("Category")}
              options={@category_options}
              prompt={gettext("Select a category...")}
            />

            <.input
              field={@form[:description]}
              type="textarea"
              label={gettext("Description")}
              placeholder={gettext("Enter product description...")}
            />

            <.input field={@form[:is_active]} type="checkbox" label={gettext("Show in menu")} />
            <p class="text-xs text-base-content/60">
              {gettext("Unpublished products do not appear in the customer menu.")}
            </p>
          </.form_section>

          <details id="product-advanced-fields" open={@advanced_open}>
            <summary
              class="cursor-pointer font-semibold"
              phx-click="toggle_advanced"
              phx-target={@myself}
            >
              {gettext("More settings")}
            </summary>
            <.form_section id="product-dish-section" title={gettext("Dish parameters")}>
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
                  <.input
                    field={@form[:calories]}
                    type="number"
                    step="any"
                    label={gettext("Calories")}
                  />
                  <.input
                    field={@form[:proteins]}
                    type="number"
                    step="any"
                    label={gettext("Proteins")}
                  />
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
            </.form_section>

            <.form_section
              id="product-organization-section"
              title={gettext("Organization and links")}
            >
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

              <.input
                field={@form[:suggested]}
                type="checkbox"
                label={gettext("Suggest in the cart")}
              />
            </.form_section>

            <.form_section id="product-loyalty-section" title={gettext("Loyalty")}>
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
                <p class="text-xs text-base-content/60">
                  {gettext("Stars are used when loyalty is enabled for this branch.")}
                </p>
              </div>
            </.form_section>

            <.form_section id="product-external-section" title={gettext("External systems")}>
              <.input
                :for={{provider, name} <- @active_crm_providers}
                id={"product-crm-id-#{provider}"}
                name={"product[crm_ids][#{provider}]"}
                value={Map.get(@form[:crm_ids].value || %{}, to_string(provider))}
                type="text"
                label={gettext("%{crm} ID", crm: name)}
                errors={Enum.map(@form[:crm_ids].errors, &translate_error/1)}
              />
              <details :if={@unused_crm_providers != []} id="product-unused-connections">
                <summary class="cursor-pointer">{gettext("Unused connections")}</summary>
                <.input
                  :for={{provider, name} <- @unused_crm_providers}
                  id={"product-crm-id-#{provider}"}
                  name={"product[crm_ids][#{provider}]"}
                  value={Map.get(@form[:crm_ids].value || %{}, to_string(provider))}
                  type="text"
                  label={gettext("%{crm} ID", crm: name)}
                  errors={Enum.map(@form[:crm_ids].errors, &translate_error/1)}
                />
              </details>
            </.form_section>

            <.form_section id="product-extra-section" title={gettext("Additional")}>
              <.input
                field={@form[:slug]}
                type="text"
                label={gettext("URL slug")}
                placeholder={Delivest.Slug.slugify(@form[:name].value) || "hinkali"}
              />
              <p class="text-xs text-base-content/60">
                {gettext(
                  "Used in the product link on the website. Leave empty to generate it from the name."
                )}
              </p>
            </.form_section>
          </details>
        </fieldset>

        <div class="shrink-0 p-6 border-t border-base-200 bg-base-100 flex justify-end gap-3">
          <.link :if={@action == :new} patch={@patch} class="btn btn-ghost">{gettext("Cancel")}</.link>
          <.link :if={@action != :new} navigate={@patch} class="btn btn-ghost">{if @readonly,
            do: gettext("Back to products"),
            else: gettext("Cancel")}</.link>
          <button
            :if={not @readonly}
            type="submit"
            class="btn btn-primary"
            data-staff-save={if @action == :new, do: "create", else: "edit"}
            phx-disable-with={gettext("Saving...")}
          >
            {if @action == :new, do: gettext("Create Product"), else: gettext("Save")}
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
