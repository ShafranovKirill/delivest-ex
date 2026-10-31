defmodule DelivestWeb.Staff.FranchiseLive.ImagesComponent do
  use DelivestWeb, :live_component

  import DelivestWeb.Staff.FranchiseLive.ImageUploads, only: [image_input: 1]

  alias Delivest.Franchise
  alias Delivest.Franchise.Images
  alias DelivestWeb.Staff.FranchiseLive.ImageUploads

  @images [:icon, :share_image]

  @impl true
  def mount(socket), do: {:ok, ImageUploads.allow(socket, @images, &handle_progress/3)}

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
    binary = ImageUploads.read(socket, entry)
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
  def handle_event("validate", _params, socket),
    do: {:noreply, ImageUploads.drop_invalid(socket, @images, &notify({:error, &1}))}

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

  defp error_text(_name, reason), do: ImageUploads.error_text(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <section class="p-5 bg-base-100 rounded-box border border-base-300 space-y-5">
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
end
