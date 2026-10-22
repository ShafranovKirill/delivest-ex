defmodule DelivestWeb.Staff.FranchiseLive.ImagesComponent do
  use DelivestWeb, :live_component

  alias Delivest.Franchise
  alias Delivest.Franchise.Images
  alias Delivest.Media

  @impl true
  def mount(socket) do
    settings = Media.Config.upload_settings("image")

    {:ok,
     Enum.reduce([:icon, :share_image], socket, fn name, acc ->
       allow_upload(acc, name,
         accept: settings.accept,
         max_entries: 1,
         max_file_size: settings.max_size,
         auto_upload: true,
         progress: &handle_progress/3
       )
     end)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       icon_url: Franchise.icon_url(assigns.settings, "icon-192.png"),
       share_image_url: Franchise.share_image_url(assigns.settings)
     )}
  end

  defp handle_progress(name, entry, socket) when entry.done? do
    binary =
      consume_uploaded_entry(socket, entry, fn %{path: path} -> {:ok, File.read!(path)} end)

    staff = socket.assigns.current_staff

    result =
      case name do
        :icon -> Franchise.update_icon(staff, binary)
        :share_image -> Franchise.update_share_image(staff, binary)
      end

    {:noreply, handle_result(socket, name, result)}
  end

  defp handle_progress(_name, _entry, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply,
     Enum.reduce([:icon, :share_image], socket, fn name, acc ->
       upload = acc.assigns.uploads[name]

       Enum.reduce(upload.entries, acc, fn entry, acc ->
         case upload_errors(upload, entry) do
           [] ->
             acc

           [error | _rest] ->
             notify({:error, upload_error_text(error)})
             cancel_upload(acc, name, entry.ref)
         end
       end)
     end)}
  end

  def handle_event("remove", %{"image" => "icon"}, socket),
    do:
      {:noreply,
       handle_result(socket, :icon, Franchise.remove_icon(socket.assigns.current_staff))}

  def handle_event("remove", %{"image" => "share_image"}, socket) do
    result = Franchise.remove_share_image(socket.assigns.current_staff)
    {:noreply, handle_result(socket, :share_image, result)}
  end

  defp handle_result(socket, _name, {:ok, settings}) do
    notify({:saved, settings})
    socket
  end

  defp handle_result(socket, name, {:error, reason}) do
    notify({:error, error_text(name, reason)})
    socket
  end

  defp notify(message), do: send(self(), {__MODULE__, message})

  defp error_text(:icon, :too_small),
    do: gettext("The icon must be at least %{size}×%{size} px", size: Images.icon_min())

  defp error_text(:share_image, :too_small),
    do: gettext("The image must be at least %{width} px wide", width: Images.share_min_width())

  defp error_text(_name, :invalid_image), do: gettext("Could not read the image")

  defp error_text(_name, :forbidden),
    do: gettext("You don't have permission to perform this action.")

  defp error_text(_name, _reason), do: gettext("Could not save the image, try again")

  defp upload_error_text(:too_large), do: gettext("File is too large")
  defp upload_error_text(:not_accepted), do: gettext("Unsupported file type")
  defp upload_error_text(_error), do: gettext("Upload failed")

  @impl true
  def render(assigns) do
    ~H"""
    <section class="p-5 bg-base-100 rounded-box border border-base-200 shadow-sm space-y-5">
      <div>
        <h2 class="font-bold text-lg">{gettext("Icon and link preview")}</h2>
        <p class="text-sm text-base-content/60">
          {gettext("Shown in the browser tab, on the phone home screen and when the link is shared.")}
        </p>
      </div>

      <form
        id="franchise-images-form"
        phx-target={@myself}
        phx-change="validate"
        class="grid grid-cols-1 md:grid-cols-[14rem_1fr] gap-6"
      >
        <div class="space-y-3">
          <span class="text-sm font-medium">{gettext("Site icon")}</span>
          <div class="flex items-center gap-3 rounded-xl bg-base-200 px-3 py-2">
            <img
              :if={@icon_url}
              id="franchise-icon-preview"
              src={@icon_url}
              class="size-5 rounded-sm"
              alt=""
            />
            <.icon :if={!@icon_url} name="hero-globe-alt" class="size-5 text-base-content/40" />
            <span class="truncate text-sm">{@settings.name}</span>
          </div>
          <.image_input
            upload={@uploads.icon}
            image="icon"
            present={@icon_url != nil}
            target={@myself}
            hint={
              gettext("Square PNG from %{size}×%{size} px, 512×512 is best",
                size: Images.icon_min()
              )
            }
          />
        </div>

        <div class="space-y-3">
          <span class="text-sm font-medium">{gettext("Link preview")}</span>
          <div class="max-w-sm overflow-hidden rounded-xl border-l-4 border-primary bg-base-200">
            <div class="p-3 space-y-0.5">
              <p class="text-sm font-semibold text-primary">{@settings.name}</p>
              <p :if={@settings.description} class="text-xs text-base-content/70 line-clamp-3">
                {@settings.description}
              </p>
            </div>
            <img
              :if={@share_image_url}
              id="franchise-share-preview"
              src={@share_image_url}
              class="aspect-[1200/630] w-full object-cover"
              alt=""
            />
            <div
              :if={!@share_image_url}
              class="aspect-[1200/630] w-full flex items-center justify-center text-base-content/30"
            >
              <.icon name="hero-photo" class="size-10" />
            </div>
          </div>
          <.image_input
            upload={@uploads.share_image}
            image="share_image"
            present={@share_image_url != nil}
            target={@myself}
            hint={
              gettext("Cropped to 1200×630 px from the center, keep the main thing in the middle")
            }
          />
        </div>
      </form>
    </section>
    """
  end

  attr :upload, :any, required: true
  attr :image, :string, required: true
  attr :present, :boolean, required: true
  attr :target, :any, required: true
  attr :hint, :string, required: true

  defp image_input(assigns) do
    assigns = assign(assigns, entry: List.first(assigns.upload.entries))

    ~H"""
    <div class="space-y-1.5" phx-drop-target={@upload.ref}>
      <.live_file_input upload={@upload} class="hidden" />
      <div class="flex flex-wrap items-center gap-2">
        <label for={@upload.ref} class="btn btn-sm btn-outline">
          <.icon name="hero-arrow-up-tray" class="size-4" />
          {if @present, do: gettext("Replace"), else: gettext("Upload")}
        </label>
        <button
          :if={@present}
          type="button"
          class="btn btn-sm btn-ghost text-error"
          phx-click="remove"
          phx-value-image={@image}
          phx-target={@target}
          data-confirm={gettext("Are you sure?")}
        >
          <.icon name="hero-trash" class="size-4" /> {gettext("Remove")}
        </button>
        <span :if={@entry && !@entry.done?} class="text-xs text-base-content/60">
          {@entry.progress}%
        </span>
      </div>
      <p class="text-xs text-base-content/50">{@hint}</p>
      <p :for={error <- upload_errors(@upload)} class="text-xs text-error">
        {upload_error_text(error)}
      </p>
    </div>
    """
  end
end
