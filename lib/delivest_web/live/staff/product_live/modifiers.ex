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
       new_group: to_form(Modifiers.change_group(%ModifierGroup{}), as: :group)
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

        <div class="space-y-2">
          <form
            :for={modifier <- group.modifiers}
            id={"modifier-#{modifier.id}"}
            phx-submit="save_modifier"
            phx-value-id={modifier.id}
            class="grid gap-2 sm:grid-cols-[1fr_7rem_5rem_7rem_auto_auto_auto_auto] sm:items-end border-t border-base-200 pt-2"
          >
            <.input
              name="modifier[name]"
              value={modifier.name}
              label={gettext("Name")}
              disabled={!@can_edit}
            />
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
