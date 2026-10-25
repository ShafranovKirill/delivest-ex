defmodule DelivestWeb.Staff.ProductLive.Tags do
  use DelivestWeb, :live_view

  alias Delivest.{Identity, Net}
  alias Delivest.Net.{ProductTag, ProductTags, TagIcons}

  import DelivestWeb.Staff.ProductLive.ProductTags, only: [tabs: 1, tag_icon: 1]

  on_mount {DelivestWeb.Hooks.Permission, "products.read"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(tag: nil, form: nil, tag_to_delete: nil)
     |> allow_upload(:icon,
       accept: ~w(.png .webp .jpg .jpeg),
       max_entries: 1,
       max_file_size: 2_000_000
     )
     |> load_tags()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params),
    do: assign(socket, page_title: gettext("Product tags"), tag: nil, form: nil)

  defp apply_action(socket, action, params) when action in [:new, :edit] do
    tag =
      if action == :new, do: %ProductTag{icon: "star"}, else: Net.get_product_tag(params["id"])

    cond do
      !can_edit?(socket) ->
        socket
        |> put_flash(:error, gettext("You don't have permission to perform this action."))
        |> push_patch(to: ~p"/staff/products/tags")

      is_nil(tag) ->
        push_patch(socket, to: ~p"/staff/products/tags")

      true ->
        title = if action == :new, do: gettext("New tag"), else: gettext("Edit tag")

        socket
        |> cancel_uploads()
        |> assign(page_title: title, tag: tag, form: to_form(Net.change_product_tag(tag)))
    end
  end

  @impl true
  def handle_event("validate", %{"product_tag" => params}, socket) do
    changeset =
      socket.assigns.tag
      |> Net.change_product_tag(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :icon, ref)}

  def handle_event("save", %{"product_tag" => params}, socket) do
    upload =
      consume_uploaded_entries(socket, :icon, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)
      |> List.first()

    staff = socket.assigns.current_staff

    result =
      case socket.assigns.tag do
        %ProductTag{id: nil} -> Net.create_product_tag(staff, params, upload)
        tag -> Net.update_product_tag(staff, tag, params, upload)
      end

    case result do
      {:ok, _tag} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Tag saved"))
         |> load_tags()
         |> push_patch(to: ~p"/staff/products/tags")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("delete_click", %{"id" => id}, socket),
    do: {:noreply, assign(socket, tag_to_delete: Net.get_product_tag(id))}

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, tag_to_delete: nil)}

  def handle_event("confirm_delete", _params, socket) do
    socket =
      case Net.delete_product_tag(socket.assigns.current_staff, socket.assigns.tag_to_delete) do
        {:ok, _tag} -> put_flash(socket, :info, gettext("Tag deleted"))
        _error -> put_flash(socket, :error, gettext("Could not delete the tag"))
      end

    {:noreply, socket |> assign(tag_to_delete: nil) |> load_tags()}
  end

  defp load_tags(socket),
    do: assign(socket, tags: Net.list_product_tags(), usage: ProductTags.usage_counts())

  defp cancel_uploads(socket) do
    Enum.reduce(socket.assigns.uploads.icon.entries, socket, fn entry, acc ->
      cancel_upload(acc, :icon, entry.ref)
    end)
  end

  defp can_edit?(socket), do: Identity.can?(socket.assigns.current_staff, "products.update")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6">
      <.page_header
        title={gettext("Products")}
        subtitle={gettext("Tags are shown on product cards on the website.")}
      >
        <:actions>
          <.button
            :if={Identity.can?(@current_staff, "products.update")}
            patch={~p"/staff/products/tags/new"}
            class="btn btn-primary"
          >
            <.icon name="hero-plus" class="size-5" />
            {gettext("Add tag")}
          </.button>
        </:actions>
      </.page_header>

      <.tabs current={:tags} />

      <div id="product-tags" class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <div
          :for={tag <- @tags}
          id={"product-tag-#{tag.id}"}
          class="flex items-center gap-3 rounded-box border border-base-300 bg-base-100 p-3"
        >
          <div class="grid size-10 shrink-0 place-items-center rounded-full bg-base-200">
            <.tag_icon tag={tag} class="size-5" />
          </div>
          <div class="min-w-0 flex-1">
            <div class="font-bold truncate">{tag.name}</div>
            <div class="text-xs text-base-content/60">
              {ngettext("%{count} product", "%{count} products", Map.get(@usage, tag.id, 0))}
            </div>
          </div>
          <div :if={Identity.can?(@current_staff, "products.update")} class="flex gap-1">
            <.button
              patch={~p"/staff/products/tags/#{tag.id}/edit"}
              class="btn btn-ghost btn-xs btn-square"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </.button>
            <.button
              phx-click="delete_click"
              phx-value-id={tag.id}
              class="btn btn-ghost btn-xs btn-square text-error hover:bg-error/10"
            >
              <.icon name="hero-trash" class="size-4" />
            </.button>
          </div>
        </div>

        <p :if={@tags == []} class="text-base-content/60">{gettext("No tags yet")}</p>
      </div>

      <.slide_over
        id="product-tag-slideover"
        show={@live_action in [:new, :edit]}
        title={@page_title}
        on_close={JS.patch(~p"/staff/products/tags")}
      >
        <.form
          :if={@form}
          for={@form}
          id="product-tag-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
        >
          <.input field={@form[:name]} type="text" label={gettext("Name")} maxlength="24" />

          <fieldset class="space-y-2">
            <legend class="label-text font-bold">{gettext("Icon")}</legend>
            <div class="grid grid-cols-8 gap-1.5">
              <label
                :for={icon <- TagIcons.names()}
                class="grid aspect-square place-items-center rounded-lg border border-base-300 cursor-pointer has-checked:border-primary has-checked:bg-primary/10 has-checked:ring-1 has-checked:ring-primary"
                title={icon}
              >
                <input
                  type="radio"
                  name={@form[:icon].name}
                  value={icon}
                  checked={@form[:icon].value == icon and @uploads.icon.entries == []}
                  class="sr-only"
                />
                <img src={TagIcons.path(icon)} alt={icon} class="size-5" />
              </label>
            </div>
            <p :for={error <- @form[:icon].errors} class="text-xs text-error">
              {translate_error(error)}
            </p>
          </fieldset>

          <div class="space-y-2" phx-drop-target={@uploads.icon.ref}>
            <div class="label-text font-bold">{gettext("Or upload your own")}</div>
            <div
              :if={@tag.icon_key && @uploads.icon.entries == [] && is_nil(@form[:icon].value)}
              class="flex items-center gap-2 text-sm"
            >
              <.tag_icon tag={@tag} class="size-6" /> {gettext("Your icon is used now")}
            </div>
            <div :for={entry <- @uploads.icon.entries} class="flex items-center gap-3">
              <.live_img_preview entry={entry} class="size-8 object-contain" />
              <span class="text-sm truncate flex-1">{entry.client_name}</span>
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
            <label for={@uploads.icon.ref} class="btn btn-sm btn-outline">
              <.icon name="hero-arrow-up-tray" class="size-4" /> {gettext("Upload icon")}
            </label>
            <.live_file_input upload={@uploads.icon} class="hidden" />
            <p class="text-xs text-base-content/60">
              {gettext(
                "Best is a square PNG with a transparent background, at least 64×64. It is shrunk to 64×64 and compressed: on the website the icon is tiny, so high quality is not needed. An uploaded icon replaces the one picked above."
              )}
            </p>
            <p :for={error <- upload_errors(@uploads.icon)} class="text-xs text-error">
              {upload_error_text(error)}
            </p>
          </div>

          <div class="flex justify-end gap-2">
            <.link patch={~p"/staff/products/tags"} class="btn btn-ghost">
              {gettext("Cancel")}
            </.link>
            <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
              {gettext("Save")}
            </button>
          </div>
        </.form>
      </.slide_over>

      <.modal
        id="delete-product-tag-modal"
        show={@tag_to_delete != nil}
        title={gettext("Delete tag")}
        description={gettext("The tag will be removed from all products.")}
        confirm_label={gettext("Delete")}
        danger={true}
        on_cancel={JS.push("cancel_delete")}
        on_confirm={JS.push("confirm_delete")}
      />
    </div>
    """
  end

  defp upload_error_text(:too_large), do: gettext("File is too large")
  defp upload_error_text(:not_accepted), do: gettext("Unsupported file type")
  defp upload_error_text(_error), do: gettext("Upload failed")
end
