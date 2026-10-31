defmodule DelivestWeb.Staff.ProductLive.Modifiers do
  use DelivestWeb, :live_view

  alias Delivest.Identity
  alias Delivest.Net.{Modifier, ModifierGroup, Modifiers}

  import DelivestWeb.Staff.ProductLive.ProductTags, only: [tabs: 1]

  on_mount {DelivestWeb.Hooks.Permission, "products.read"}

  @provider "frontpad"

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    {:ok,
     socket
     |> assign(
       page_title: gettext("Modifiers"),
       branch_id: socket.assigns.current_branch.id,
       can_edit: Identity.can?(staff, "products.update"),
       can_stop: Identity.can?(staff, "stops.update"),
       new_group: to_form(Modifiers.change_group(%ModifierGroup{}), as: :group),
       photo_for: nil,
       group_form: nil,
       modifier_form: nil
     )
     |> allow_upload(:photo,
       accept: ~w(.png .webp .jpg .jpeg),
       max_entries: 1,
       max_file_size: 5_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )
     |> load()}
  end

  @impl true
  def handle_event("new_group", _params, socket),
    do: {:noreply, assign(socket, group_form: %ModifierGroup{min: 0, max: 1})}

  def handle_event("edit_group", %{"id" => id}, socket),
    do: {:noreply, assign(socket, group_form: Modifiers.get_group(id))}

  def handle_event("new_modifier", %{"group_id" => group_id}, socket),
    do: {:noreply, assign(socket, modifier_form: %Modifier{group_id: group_id})}

  def handle_event("edit_modifier", %{"id" => id}, socket),
    do: {:noreply, assign(socket, modifier_form: Modifiers.get_modifier(id))}

  def handle_event("close_form", _params, socket),
    do: {:noreply, assign(socket, group_form: nil, modifier_form: nil)}

  def handle_event("save_group", %{"group" => params}, socket) do
    group = socket.assigns.group_form

    case Modifiers.save_group(socket.assigns.current_staff, group, group_attrs(params)) do
      {:ok, _group} ->
        {:noreply,
         socket |> assign(group_form: nil) |> put_flash(:info, gettext("Saved")) |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, errors(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  def handle_event("delete_group", %{"id" => id}, socket) do
    Modifiers.delete_group(socket.assigns.current_staff, Modifiers.get_group(id))
    {:noreply, load(socket)}
  end

  def handle_event("save_modifier", %{"modifier" => params}, socket) do
    modifier = socket.assigns.modifier_form
    staff = socket.assigns.current_staff
    attrs = params |> Map.delete("article") |> Map.put("max_quantity", "1")

    with {:ok, modifier} <- Modifiers.save_modifier(staff, modifier, attrs),
         {:ok, _id} <-
           Modifiers.put_crm_id(
             staff,
             modifier,
             socket.assigns.branch_id,
             @provider,
             params["article"]
           ) do
      {:noreply,
       socket |> assign(modifier_form: nil) |> put_flash(:info, gettext("Saved")) |> load()}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, errors(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  def handle_event("pick_photo", %{"id" => id}, socket),
    do: {:noreply, assign(socket, photo_for: id)}

  def handle_event("validate_photo", _params, socket), do: {:noreply, socket}

  def handle_event("remove_photo", %{"id" => id}, socket) do
    case Modifiers.remove_photo(socket.assigns.current_staff, Modifiers.get_modifier(id)) do
      {:ok, _modifier} -> {:noreply, load(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  def handle_event("delete_modifier", %{"id" => id}, socket) do
    Modifiers.delete_modifier(socket.assigns.current_staff, Modifiers.get_modifier(id))
    {:noreply, load(socket)}
  end

  def handle_event("stop", %{"id" => id}, socket) do
    Modifiers.stop(
      socket.assigns.current_staff,
      socket.assigns.branch_id,
      Modifiers.get_modifier(id),
      :until_resumed
    )

    {:noreply, load(socket)}
  end

  def handle_event("resume", %{"id" => id}, socket) do
    Modifiers.resume(
      socket.assigns.current_staff,
      socket.assigns.branch_id,
      Modifiers.get_modifier(id)
    )

    {:noreply, load(socket)}
  end

  defp group_attrs(params) do
    size? = params["is_size"] == "true"

    %{
      "name" => params["name"],
      "is_size" => params["is_size"] || "false",
      "is_active" => params["is_active"] || "false",
      "min" => if(params["required"] == "true", do: "1", else: "0"),
      "max" => if(size?, do: "1", else: params["max"] || "1")
    }
  end

  defp handle_progress(:photo, entry, socket) do
    if entry.done? do
      binary =
        consume_uploaded_entry(socket, entry, fn %{path: path} -> {:ok, File.read!(path)} end)

      modifier = Modifiers.get_modifier(socket.assigns.photo_for)

      case modifier && Modifiers.put_photo(socket.assigns.current_staff, modifier, binary) do
        {:ok, _modifier} ->
          {:noreply, socket |> put_flash(:info, gettext("Saved")) |> load()}

        {:error, :invalid_image} ->
          {:noreply, put_flash(socket, :error, gettext("Could not read the image"))}

        _ ->
          {:noreply, put_flash(socket, :error, gettext("Could not save the image, try again"))}
      end
    else
      {:noreply, socket}
    end
  end

  defp load(socket) do
    groups = Modifiers.list_groups()
    ids = for g <- groups, m <- g.modifiers, do: m.id

    assign(socket,
      groups: groups,
      stopped: Modifiers.stopped_ids(socket.assigns.branch_id),
      articles: Modifiers.crm_ids(ids, @provider)
    )
  end

  defp errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end

  defp rule_text(%{min: min, max: max} = group) do
    rule =
      cond do
        min >= 1 and max == 1 -> gettext("Required: the customer picks one.")
        min >= 1 -> gettext("Required: the customer picks from 1 to %{count}.", count: max)
        max == 1 -> gettext("Optional: the customer may pick one.")
        true -> gettext("Optional: the customer may pick up to %{count}.", count: max)
      end

    if group.is_size, do: "#{rule} #{gettext("Shown as a size switch.")}", else: rule
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <.page_header
        title={gettext("Modifiers")}
        subtitle={
          gettext("Size, dough and extras. A group is made once and attached to many products.")
        }
      >
        <:actions>
          <button :if={@can_edit} type="button" phx-click="new_group" class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" />
            {gettext("Add group")}
          </button>
        </:actions>
      </.page_header>

      <.tabs current={:modifiers} branch={@current_branch} />

      <form :if={@can_edit} id="photo-upload" phx-change="validate_photo" class="hidden">
        <.live_file_input upload={@uploads.photo} />
      </form>

      <details
        class="rounded-box border border-base-300 bg-base-100 group"
        open={@groups == []}
      >
        <summary class="flex cursor-pointer items-center justify-between gap-3 p-4 font-semibold">
          {gettext("How modifiers work")}
          <.icon name="hero-chevron-down" class="size-4 transition-transform group-open:rotate-180" />
        </summary>
        <div class="space-y-3 border-t border-base-200 p-4 text-sm text-base-content/80">
          <p>
            {gettext(
              "A modifier is a choice the customer makes on a product: size, dough, sauce, extra cheese. The choice changes the price and goes to the kitchen, the receipt and the cash register together with the dish."
            )}
          </p>
          <ol class="list-decimal space-y-2 pl-5">
            <li>
              <b>{gettext("Group")}</b>
              — {gettext(
                "a question to the customer: «Size», «Dough», «Extras». Tick «Required» if something must be chosen and set the maximum for extras. A group is made once and attached to any number of products."
              )}
            </li>
            <li>
              <b>{gettext("Modifier")}</b>
              — {gettext(
                "one answer in the group with its own price and photo: «30 cm» +0, «Jam» +80. It can be taken once per product. Sizes are shown without a price, extras with «+price»."
              )}
            </li>
            <li>
              {gettext(
                "Open a product in the catalog and tick the groups it has. The customer sees them in the product card before adding it to the cart."
              )}
            </li>
          </ol>
          <p>
            <b>{gettext("Stop")}</b>
            — {gettext(
              "temporarily hides the modifier from customers and aggregators, for example when an ingredient ran out. The product itself stays on sale."
            )}
          </p>
          <p>
            <b>{gettext("Frontpad article")}</b>
            — {gettext(
              "the code of the modifier in the cash register. Without it the order reaches Frontpad without this modifier."
            )}
          </p>
        </div>
      </details>

      <p :if={@groups == []} class="text-base-content/60">{gettext("No modifier groups yet")}</p>

      <details
        :for={group <- @groups}
        id={"group-#{group.id}"}
        class="group bg-base-100 rounded-box border border-base-300"
      >
        <summary class="flex cursor-pointer items-center justify-between gap-3 p-4">
          <span class="min-w-0">
            <span class="block font-semibold">
              {group.name}
              <span :if={!group.is_active} class="badge badge-ghost badge-sm ml-1">
                {gettext("Inactive")}
              </span>
            </span>
            <span class="block text-sm text-base-content/60">
              {rule_text(group)} · {ngettext(
                "%{count} modifier",
                "%{count} modifiers",
                length(group.modifiers)
              )}
            </span>
          </span>
          <.icon
            name="hero-chevron-down"
            class="size-4 shrink-0 transition-transform group-open:rotate-180"
          />
        </summary>

        <div class="space-y-3 border-t border-base-200 p-4">
          <div :if={@can_edit} class="flex flex-wrap items-center gap-2">
            <button
              type="button"
              phx-click="new_modifier"
              phx-value-group_id={group.id}
              class="btn btn-sm btn-outline"
            >
              <.icon name="hero-plus" class="size-4" />
              {gettext("Add modifier")}
            </button>
            <button
              type="button"
              phx-click="edit_group"
              phx-value-id={group.id}
              class="btn btn-sm btn-ghost"
            >
              <.icon name="hero-pencil-square" class="size-4" />
              {gettext("Edit group")}
            </button>
            <button
              type="button"
              phx-click="delete_group"
              phx-value-id={group.id}
              data-confirm={gettext("Delete the group with its modifiers?")}
              class="btn btn-sm btn-ghost text-error"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </div>

          <p :if={group.modifiers == []} class="text-sm text-base-content/50">
            {gettext("No modifiers in this group yet")}
          </p>

          <ul class="divide-y divide-base-200">
            <li
              :for={modifier <- group.modifiers}
              id={"modifier-#{modifier.id}"}
              class="flex flex-wrap items-center gap-3 py-2"
            >
              <label
                for={@can_edit && @uploads.photo.ref}
                phx-click={@can_edit && "pick_photo"}
                phx-value-id={modifier.id}
                title={gettext("Photo")}
                class={[
                  "size-10 shrink-0 rounded-box border border-base-300 bg-base-200 grid place-items-center overflow-hidden",
                  @can_edit && "cursor-pointer"
                ]}
              >
                <img
                  :if={modifier.photo_key}
                  src={Modifiers.photo_url(modifier)}
                  class="size-full object-cover"
                />
                <.icon
                  :if={!modifier.photo_key}
                  name="hero-photo"
                  class="size-5 text-base-content/30"
                />
              </label>
              <button
                :if={@can_edit && modifier.photo_key}
                type="button"
                phx-click="remove_photo"
                phx-value-id={modifier.id}
                title={gettext("Remove photo")}
                class="btn btn-ghost btn-xs"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>

              <div class="min-w-0 flex-1">
                <span class="font-medium">{modifier.name}</span>
                <span
                  :if={modifier.is_default}
                  class="badge badge-sm badge-primary badge-outline ml-1"
                >
                  {gettext("By default")}
                </span>
                <span
                  :if={MapSet.member?(@stopped, modifier.id)}
                  class="badge badge-sm badge-error ml-1"
                >
                  {gettext("Stopped")}
                </span>
              </div>

              <span class="text-sm tabular-nums">{Delivest.Money.input(modifier.price)}</span>

              <button
                :if={@can_stop}
                type="button"
                phx-click={if MapSet.member?(@stopped, modifier.id), do: "resume", else: "stop"}
                phx-value-id={modifier.id}
                class={["btn btn-sm", MapSet.member?(@stopped, modifier.id) && "btn-error"]}
              >
                {if MapSet.member?(@stopped, modifier.id),
                  do: gettext("Resume"),
                  else: gettext("Stop")}
              </button>
              <button
                :if={@can_edit}
                type="button"
                phx-click="edit_modifier"
                phx-value-id={modifier.id}
                class="btn btn-ghost btn-sm btn-square"
                title={gettext("Edit")}
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </button>
              <button
                :if={@can_edit}
                type="button"
                phx-click="delete_modifier"
                phx-value-id={modifier.id}
                data-confirm={gettext("Delete the modifier?")}
                class="btn btn-ghost btn-sm btn-square text-error"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </li>
          </ul>
        </div>
      </details>

      <.modal
        id="group-modal"
        show={@group_form != nil}
        title={
          if @group_form && @group_form.id, do: gettext("Edit group"), else: gettext("New group")
        }
        on_cancel={JS.push("close_form")}
      >
        <form :if={@group_form} id="group-form" phx-submit="save_group" class="mt-4 space-y-4">
          <.input
            name="group[name]"
            value={@group_form.name}
            label={gettext("Group")}
            placeholder={gettext("Size")}
          />
          <.input
            name="group[required]"
            type="checkbox"
            checked={@group_form.min >= 1}
            label={gettext("Required: the customer must pick something")}
          />
          <.input
            name="group[is_size]"
            type="checkbox"
            checked={@group_form.is_size}
            label={gettext("Size (shown as a switch, one choice)")}
          />
          <.input
            name="group[max]"
            type="number"
            value={@group_form.max}
            label={gettext("Maximum choices (ignored for a size)")}
          />
          <.input
            :if={@group_form.id}
            name="group[is_active]"
            type="checkbox"
            checked={@group_form.is_active}
            label={gettext("Active")}
          />
          <input :if={!@group_form.id} type="hidden" name="group[is_active]" value="true" />
          <div class="modal-action">
            <button type="button" class="btn btn-outline btn-sm" phx-click="close_form">
              {gettext("Cancel")}
            </button>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
          </div>
        </form>
      </.modal>

      <.modal
        id="modifier-modal"
        show={@modifier_form != nil}
        title={
          if @modifier_form && @modifier_form.id,
            do: gettext("Edit modifier"),
            else: gettext("New modifier")
        }
        on_cancel={JS.push("close_form")}
      >
        <form
          :if={@modifier_form}
          id="modifier-form"
          phx-submit="save_modifier"
          class="mt-4 space-y-4"
        >
          <.input name="modifier[name]" value={@modifier_form.name} label={gettext("Name")} />
          <.input
            name="modifier[price]"
            value={Delivest.Money.input(@modifier_form.price)}
            label={gettext("Price")}
          />
          <.input
            name="modifier[article]"
            value={@modifier_form.id && @articles[@modifier_form.id]}
            label={gettext("Frontpad article")}
          />
          <.input
            name="modifier[is_default]"
            type="checkbox"
            checked={@modifier_form.is_default}
            label={gettext("By default")}
          />
          <input
            :if={!@modifier_form.id}
            type="hidden"
            name="modifier[group_id]"
            value={@modifier_form.group_id}
          />
          <div class="modal-action">
            <button type="button" class="btn btn-outline btn-sm" phx-click="close_form">
              {gettext("Cancel")}
            </button>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
          </div>
        </form>
      </.modal>
    </div>
    """
  end
end
