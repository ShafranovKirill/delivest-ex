defmodule DelivestWeb.Staff.BranchLive.TimingComponent do
  use DelivestWeb, :live_component

  alias Delivest.Identity
  alias Delivest.Net.{Categories, Products}
  alias Delivest.Oms.OrderTiming

  @impl true
  def update(assigns, socket) do
    if socket.assigns[:branch] && socket.assigns.branch.id == assigns.branch.id do
      {:ok, assign(socket, assigns)}
    else
      settings = OrderTiming.get(assigns.branch.id)
      params = params(settings, assigns.branch.info && assigns.branch.info.delivery_time)

      {:ok,
       socket
       |> assign(assigns)
       |> assign(
         categories: Categories.list_branch_categories(assigns.branch.id),
         products: Products.list_product_options_for_branch(assigns.branch.id),
         params: params,
         category_ids: Map.keys(params["category_minutes"]),
         product_ids: Map.keys(params["product_minutes"]),
         form: to_form(params, as: "timing")
       )}
    end
  end

  @impl true
  def handle_event("change", %{"timing" => params}, socket) do
    {:noreply, put_params(socket, params)}
  end

  def handle_event("add_category", _params, socket) do
    id = socket.assigns.params["new_category_id"]
    known = Enum.any?(socket.assigns.categories, &(&1.id == id))

    if known and id not in socket.assigns.category_ids do
      {:noreply, assign(socket, category_ids: socket.assigns.category_ids ++ [id])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_product", _params, socket) do
    id = socket.assigns.params["new_product_id"]
    known = Enum.any?(socket.assigns.products, fn {_name, product_id} -> product_id == id end)

    if known and id not in socket.assigns.product_ids do
      {:noreply, assign(socket, product_ids: socket.assigns.product_ids ++ [id])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_category", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(category_ids: List.delete(socket.assigns.category_ids, id))
     |> put_params(Map.update!(socket.assigns.params, "category_minutes", &Map.delete(&1, id)))}
  end

  def handle_event("remove_product", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(product_ids: List.delete(socket.assigns.product_ids, id))
     |> put_params(Map.update!(socket.assigns.params, "product_minutes", &Map.delete(&1, id)))}
  end

  def handle_event("save", %{"timing" => params}, socket) do
    params = Map.merge(socket.assigns.params, params)

    attrs =
      if params["mode"] == "calculated" do
        params
        |> Map.put(
          "category_minutes",
          only_present(params["category_minutes"], socket.assigns.category_ids)
        )
        |> Map.put(
          "product_minutes",
          only_present(params["product_minutes"], socket.assigns.product_ids)
        )
        |> Map.drop(["new_category_id", "new_product_id"])
      else
        Map.take(params, ["mode", "fixed_delivery_minutes"])
      end

    case OrderTiming.update(
           Identity.fresh_staff(socket.assigns.current_staff),
           socket.assigns.branch.id,
           attrs
         ) do
      {:ok, settings} ->
        saved = params(settings, params["fixed_delivery_minutes"])

        {:noreply,
         socket
         |> put_params(saved)
         |> put_flash(:info, gettext("Order timing saved"))
         |> push_event("staff:form-saved", %{id: "branch-timing-form"})}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_params(params)
         |> put_flash(:error, gettext("Check the time settings"))
         |> push_event("staff:form-failed", %{id: "branch-timing-form"})}
    end
  end

  defp only_present(values, ids) when is_map(values),
    do: Map.take(values, ids) |> Map.reject(fn {_id, minutes} -> minutes in [nil, ""] end)

  defp only_present(_, _), do: %{}

  defp put_params(socket, params) do
    merged = Map.merge(socket.assigns.params, params)
    assign(socket, params: merged, form: to_form(merged, as: "timing"))
  end

  defp params(settings, fixed) do
    %{
      "mode" => to_string(settings.mode),
      "fixed_delivery_minutes" => fixed || 60,
      "kitchen_minutes" => settings.kitchen_minutes,
      "packing_minutes" => settings.packing_minutes,
      "travel_minutes" => settings.travel_minutes,
      "category_minutes" => settings.category_minutes || %{},
      "product_minutes" => settings.product_minutes || %{},
      "new_category_id" => "",
      "new_product_id" => ""
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id="branch-timing-form"
        phx-target={@myself}
        phx-change="change"
        phx-submit="save"
        data-staff-dirty
        class="space-y-5"
      >
        <section class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6">
          <h2 class="text-lg font-semibold">{gettext("Customer delivery estimate")}</h2>
          <p class="text-sm text-base-content/70">
            {gettext("Choose how the time shown to customers is calculated.")}
          </p>
          <div class="grid gap-3 sm:grid-cols-2">
            <label class={[
              "cursor-pointer rounded-box border p-4",
              @params["mode"] == "fixed" && "border-primary bg-primary/5"
            ]}>
              <input
                id="timing-mode-fixed"
                type="radio"
                name="timing[mode]"
                value="fixed"
                checked={@params["mode"] == "fixed"}
                class="radio radio-primary radio-sm mr-2"
              />
              <span class="font-medium">{gettext("One delivery time")}</span>
              <span class="mt-1 block text-sm text-base-content/65">{gettext(
                "Show one full time from order to handover for every delivery."
              )}</span>
            </label>
            <label class={[
              "cursor-pointer rounded-box border p-4",
              @params["mode"] == "calculated" && "border-primary bg-primary/5"
            ]}>
              <input
                id="timing-mode-calculated"
                type="radio"
                name="timing[mode]"
                value="calculated"
                checked={@params["mode"] == "calculated"}
                class="radio radio-primary radio-sm mr-2"
              />
              <span class="font-medium">{gettext("Calculated time")}</span>
              <span class="mt-1 block text-sm text-base-content/65">{gettext(
                "Kitchen time plus the time to deliver to the address."
              )}</span>
            </label>
          </div>
          <.input
            field={@form[:fixed_delivery_minutes]}
            type="number"
            min="1"
            max="600"
            label={gettext("Full delivery time, minutes")}
          />
          <p class="text-sm text-base-content/60">
            {gettext(
              "Used in one-time mode. Includes cooking and delivery. This value is also editable in Delivery settings."
            )}
          </p>
        </section>

        <section
          :if={@params["mode"] == "calculated"}
          class="space-y-5 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
        >
          <div>
            <h2 class="text-lg font-semibold">{gettext("Kitchen estimate")}</h2>
            <p class="text-sm text-base-content/70">
              {gettext(
                "Enter times for categories. Add a product only when it differs from its category."
              )}
            </p>
          </div>
          <div class="grid gap-4 sm:grid-cols-3">
            <.input
              field={@form[:kitchen_minutes]}
              type="number"
              min="1"
              max="600"
              label={gettext("Default cooking, minutes")}
            />
            <.input
              field={@form[:packing_minutes]}
              type="number"
              min="0"
              max="120"
              label={gettext("Packing, minutes")}
            />
            <.input
              field={@form[:travel_minutes]}
              type="number"
              min="1"
              max="600"
              label={gettext("Average travel after ready, minutes")}
            />
          </div>
          <div class="border-t border-base-200 pt-4 space-y-3">
            <h3 class="font-semibold">{gettext("Category times")}</h3>
            <div :for={id <- @category_ids} class="flex items-end gap-2">
              <label class="form-control flex-1 min-w-0">
                <span class="label-text text-sm">{Enum.find_value(
                  @categories,
                  &(&1.id == id && &1.name)
                )}</span>
                <input
                  id={"timing-category-#{id}"}
                  name={"timing[category_minutes][#{id}]"}
                  value={@params["category_minutes"][id]}
                  type="number"
                  min="1"
                  max="600"
                  class="input input-bordered w-full"
                />
              </label>
              <button
                type="button"
                phx-click="remove_category"
                phx-target={@myself}
                phx-value-id={id}
                class="btn btn-ghost"
                aria-label={gettext("Remove category time")}
              ><.icon name="hero-x-mark" class="size-4" /></button>
            </div>
            <div class="flex flex-wrap gap-2">
              <select
                id="timing-add-category"
                name="timing[new_category_id]"
                class="select select-bordered flex-1 min-w-36"
              >
                <option value="">{gettext("Choose category")}</option>
                <option
                  :for={category <- @categories}
                  :if={category.id not in @category_ids}
                  value={category.id}
                  selected={@params["new_category_id"] == category.id}
                >
                  {category.name}
                </option>
              </select>
              <button
                id="timing-add-category-button"
                type="button"
                phx-click="add_category"
                phx-target={@myself}
                class="btn btn-outline"
              >{gettext("Add category")}</button>
            </div>
          </div>
          <div class="border-t border-base-200 pt-4 space-y-3">
            <h3 class="font-semibold">{gettext("Product exceptions")}</h3>
            <div :for={id <- @product_ids} class="flex items-end gap-2">
              <label class="form-control flex-1 min-w-0">
                <span class="label-text text-sm">{Enum.find_value(@products, fn {name, product_id} ->
                  product_id == id && name
                end)}</span>
                <input
                  id={"timing-product-#{id}"}
                  name={"timing[product_minutes][#{id}]"}
                  value={@params["product_minutes"][id]}
                  type="number"
                  min="1"
                  max="600"
                  class="input input-bordered w-full"
                />
              </label>
              <button
                type="button"
                phx-click="remove_product"
                phx-target={@myself}
                phx-value-id={id}
                class="btn btn-ghost"
                aria-label={gettext("Remove product time")}
              ><.icon name="hero-x-mark" class="size-4" /></button>
            </div>
            <div class="flex flex-wrap gap-2">
              <select
                id="timing-add-product"
                name="timing[new_product_id]"
                class="select select-bordered flex-1 min-w-36"
              >
                <option value="">{gettext("Choose product")}</option>
                <option
                  :for={{name, id} <- @products}
                  :if={id not in @product_ids}
                  value={id}
                  selected={@params["new_product_id"] == id}
                >
                  {name}
                </option>
              </select>
              <button
                id="timing-add-product-button"
                type="button"
                phx-click="add_product"
                phx-target={@myself}
                class="btn btn-outline"
              >{gettext("Add product")}</button>
            </div>
          </div>
        </section>
        <div class="flex justify-end">
          <button
            id="timing-save"
            type="submit"
            class="btn btn-primary"
            phx-disable-with={gettext("Saving...")}
          >{gettext("Save")}</button>
        </div>
      </.form>
    </div>
    """
  end
end
