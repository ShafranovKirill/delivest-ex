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
       photo_for: nil
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
  def handle_event("save_group", %{"group" => params} = event, socket) do
    group = if id = event["id"], do: Modifiers.get_group(id), else: %ModifierGroup{}

    case Modifiers.save_group(socket.assigns.current_staff, group, params) do
      {:ok, _group} ->
        {:noreply,
         socket
         |> assign(new_group: to_form(Modifiers.change_group(%ModifierGroup{}), as: :group))
         |> put_flash(:info, gettext("Saved"))
         |> load()}

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

  def handle_event("save_modifier", %{"modifier" => params} = event, socket) do
    modifier =
      if id = event["id"],
        do: Modifiers.get_modifier(id),
        else: %Modifier{group_id: event["group_id"]}

    staff = socket.assigns.current_staff

    with {:ok, modifier} <-
           Modifiers.save_modifier(staff, modifier, Map.delete(params, "article")),
         {:ok, _id} <-
           Modifiers.put_crm_id(
             staff,
             modifier,
             socket.assigns.branch_id,
             @provider,
             params["article"]
           ) do
      {:noreply, socket |> put_flash(:info, gettext("Saved")) |> load()}
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

  defp rule_text(%{min: min, max: max} = group) do
    kind = if group.is_size, do: gettext("Shown as a size switch."), else: ""

    rule =
      cond do
        min == 1 and max == 1 -> gettext("The customer must pick exactly one.")
        min == 0 and max == 1 -> gettext("The customer may pick one or skip.")
        min == max -> gettext("The customer must pick %{count}.", count: min)
        min == 0 -> gettext("The customer may skip or pick up to %{count}.", count: max)
        true -> gettext("The customer picks from %{min} to %{max}.", min: min, max: max)
      end

    String.trim("#{rule} #{kind}")
  end

  defp errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
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
      />

      <.tabs current={:modifiers} branch={@current_branch} />

      <details
        class="rounded-box border border-base-300 bg-base-100 group"
        open={@groups == []}
      >
        <summary class="flex cursor-pointer items-center justify-between gap-3 p-4 font-semibold">
          {gettext("How modifiers work")}
          <.icon name="hero-chevron-down" class="size-4 transition-transform group-open:rotate-180" />
        </summary>
        <div class="space-y-4 border-t border-base-200 p-4 text-sm text-base-content/80">
          <p>
            {gettext(
              "A modifier is a choice the customer makes on a product: size, dough, sauce, extra cheese. The choice changes the price and goes to the kitchen, the receipt and the cash register together with the dish."
            )}
          </p>

          <ol class="list-decimal space-y-2 pl-5">
            <li>
              <b>{gettext("Group")}</b>
              — {gettext(
                "a question to the customer: «Size», «Dough», «Extras». A group is made once and attached to any number of products."
              )}
            </li>
            <li>
              <b>{gettext("Modifier")}</b>
              — {gettext(
                "one answer in the group with its own price: «30 cm» +0, «35 cm» +150, «Double cheese» +80. The price of the line is the product plus the chosen modifiers."
              )}
            </li>
            <li>
              {gettext(
                "Open a product in the catalog and tick the groups it has. The customer sees them in the product card before adding it to the cart."
              )}
            </li>
          </ol>

          <dl class="grid gap-x-6 gap-y-2 sm:grid-cols-[10rem_1fr]">
            <dt class="font-semibold">{gettext("Min / Max")}</dt>
            <dd>
              {gettext(
                "How many modifiers of the group the customer must and may take. 1 and 1 — pick exactly one (size). 0 and 3 — can skip, up to three (extras). 0 and 1 — one optional (sauce)."
              )}
            </dd>
            <dt class="font-semibold">{gettext("Size")}</dt>
            <dd>
              {gettext(
                "Mark the group as size: the customer sees a switch instead of a list, and CRMs with a size scale (iiko) get it as the product size."
              )}
            </dd>
            <dt class="font-semibold">{gettext("Up to")}</dt>
            <dd>
              {gettext("How many times one modifier can be taken. 2 makes «Double cheese» possible.")}
            </dd>
            <dt class="font-semibold">{gettext("By default")}</dt>
            <dd>
              {gettext(
                "The modifier is already chosen when the card opens, for example the usual size."
              )}
            </dd>
            <dt class="font-semibold">{gettext("Stop")}</dt>
            <dd>
              {gettext(
                "Temporarily hides the modifier from customers and aggregators, for example when an ingredient ran out. The product itself stays on sale."
              )}
            </dd>
            <dt class="font-semibold">{gettext("Frontpad article")}</dt>
            <dd>
              {gettext(
                "The code of the modifier in the cash register. Without it the order reaches Frontpad without this modifier."
              )}
            </dd>
            <dt class="font-semibold">{gettext("Active")}</dt>
            <dd>
              {gettext("A switched off group disappears from all products without being deleted.")}
            </dd>
          </dl>
        </div>
      </details>

      <.form
        :if={@can_edit}
        for={@new_group}
        id="new-group"
        phx-submit="save_group"
        class="p-4 bg-base-100 rounded-box border border-base-300 grid gap-3 sm:grid-cols-[1fr_6rem_6rem_auto_auto] sm:items-end"
      >
        <.input field={@new_group[:name]} label={gettext("New group")} placeholder={gettext("Size")} />
        <.input field={@new_group[:min]} type="number" label={gettext("Min")} />
        <.input field={@new_group[:max]} type="number" label={gettext("Max")} />
        <.input field={@new_group[:is_size]} type="checkbox" label={gettext("Size")} />
        <.button>{gettext("Add")}</.button>
      </.form>

      <form id="photo-upload" phx-change="validate_photo" class="hidden">
        <.live_file_input upload={@uploads.photo} />
      </form>

      <p :if={@groups == []} class="text-base-content/60">{gettext("No modifier groups yet")}</p>

      <section
        :for={group <- @groups}
        id={"group-#{group.id}"}
        class="p-4 bg-base-100 rounded-box border border-base-300 space-y-3"
      >
        <form
          phx-submit="save_group"
          phx-value-id={group.id}
          id={"group-form-#{group.id}"}
          class="grid gap-3 sm:grid-cols-[1fr_6rem_6rem_auto_auto_auto_auto] sm:items-end"
        >
          <.input
            name="group[name]"
            value={group.name}
            label={gettext("Group")}
            disabled={!@can_edit}
          />
          <.input
            name="group[min]"
            type="number"
            value={group.min}
            label={gettext("Min")}
            disabled={!@can_edit}
          />
          <.input
            name="group[max]"
            type="number"
            value={group.max}
            label={gettext("Max")}
            disabled={!@can_edit}
          />
          <.input
            name="group[is_size]"
            type="checkbox"
            checked={group.is_size}
            label={gettext("Size")}
            disabled={!@can_edit}
          />
          <.input
            name="group[is_active]"
            type="checkbox"
            checked={group.is_active}
            label={gettext("Active")}
            disabled={!@can_edit}
          />
          <.button :if={@can_edit}>{gettext("Save")}</.button>
          <button
            :if={@can_edit}
            type="button"
            phx-click="delete_group"
            phx-value-id={group.id}
            data-confirm={gettext("Delete the group with its modifiers?")}
            class="btn btn-ghost btn-sm text-error"
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </form>

        <p class="text-xs text-base-content/60">{rule_text(group)}</p>

        <div class="space-y-2">
          <form
            :for={modifier <- group.modifiers}
            id={"modifier-#{modifier.id}"}
            phx-submit="save_modifier"
            phx-value-id={modifier.id}
            class="grid gap-2 sm:grid-cols-[1fr_7rem_5rem_7rem_auto_auto_auto_auto] sm:items-end border-t border-base-200 pt-2"
          >
            <div class="flex items-end gap-2">
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
              <.input
                name="modifier[name]"
                value={modifier.name}
                label={gettext("Name")}
                disabled={!@can_edit}
                class="w-full input"
              />
            </div>
            <.input
              name="modifier[price]"
              value={Delivest.Money.input(modifier.price)}
              label={gettext("Price")}
              disabled={!@can_edit}
            />
            <.input
              name="modifier[max_quantity]"
              type="number"
              value={modifier.max_quantity}
              label={gettext("Up to")}
              disabled={!@can_edit}
            />
            <.input
              name="modifier[article]"
              value={@articles[modifier.id]}
              label={gettext("Frontpad article")}
              disabled={!@can_edit}
            />
            <.input
              name="modifier[is_default]"
              type="checkbox"
              checked={modifier.is_default}
              label={gettext("By default")}
              disabled={!@can_edit}
            />
            <.button :if={@can_edit} class="btn-sm">{gettext("Save")}</.button>
            <button
              :if={@can_stop}
              type="button"
              phx-click={if MapSet.member?(@stopped, modifier.id), do: "resume", else: "stop"}
              phx-value-id={modifier.id}
              class={["btn btn-sm", MapSet.member?(@stopped, modifier.id) && "btn-error"]}
            >
              {if MapSet.member?(@stopped, modifier.id), do: gettext("Resume"), else: gettext("Stop")}
            </button>
            <button
              :if={@can_edit}
              type="button"
              phx-click="delete_modifier"
              phx-value-id={modifier.id}
              data-confirm={gettext("Delete the modifier?")}
              class="btn btn-ghost btn-sm text-error"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </form>

          <form
            :if={@can_edit}
            id={"new-modifier-#{group.id}"}
            phx-submit="save_modifier"
            phx-value-group_id={group.id}
            class="grid gap-2 sm:grid-cols-[1fr_7rem_5rem_auto] sm:items-end border-t border-base-200 pt-2"
          >
            <.input name="modifier[name]" value="" label={gettext("New modifier")} />
            <.input name="modifier[price]" value="0" label={gettext("Price")} />
            <.input name="modifier[max_quantity]" type="number" value="1" label={gettext("Up to")} />
            <.button class="btn-sm">{gettext("Add")}</.button>
          </form>
        </div>
      </section>
    </div>
    """
  end
end
