defmodule DelivestWeb.Staff.FranchiseLive.LogoComponent do
  use DelivestWeb, :live_component

  import DelivestWeb.Staff.FranchiseLive.ImageUploads, only: [image_input: 1]

  alias Delivest.Franchise
  alias Delivest.Franchise.Images
  alias DelivestWeb.Staff.FranchiseLive.ImageUploads

  @variants %{logo: :light, logo_dark: :dark}

  @impl true
  def mount(socket),
    do: {:ok, ImageUploads.allow(socket, Map.keys(@variants), &handle_progress/3)}

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       logo_url: Franchise.logo_url(assigns.settings),
       logo_dark_url: Franchise.logo_dark_url(assigns.settings)
     )}
  end

  defp handle_progress(name, entry, socket) when entry.done? do
    binary = ImageUploads.read(socket, entry)
    result = Franchise.update_logo(socket.assigns.current_staff, @variants[name], binary)
    {:noreply, handle_result(socket, result)}
  end

  defp handle_progress(_name, _entry, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", _params, socket),
    do: {:noreply, ImageUploads.drop_invalid(socket, Map.keys(@variants), &notify({:error, &1}))}

  def handle_event("remove", %{"image" => image}, socket) do
    result = Franchise.remove_logo(socket.assigns.current_staff, removed_variant(image))
    {:noreply, handle_result(socket, result)}
  end

  defp removed_variant("logo"), do: :light
  defp removed_variant("logo_dark"), do: :dark

  defp handle_result(socket, {:ok, settings}) do
    notify({:saved, settings})
    socket
  end

  defp handle_result(socket, {:error, reason}) do
    notify({:error, error_text(reason)})
    socket
  end

  defp notify(message), do: send(self(), {__MODULE__, message})

  defp error_text(:too_small),
    do: gettext("The logo must be at least %{height} px high", height: Images.logo_min_height())

  defp error_text(reason), do: ImageUploads.error_text(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <section class="p-5 bg-base-100 rounded-box border border-base-300 space-y-5">
      <form
        id="franchise-logo-form"
        phx-target={@myself}
        phx-change="validate"
        class="grid grid-cols-1 md:grid-cols-2 gap-6"
      >
        <div class="space-y-3">
          <span class="text-sm font-medium">{gettext("Light theme")}</span>
          <.logo_preview
            id="franchise-logo-preview"
            url={@logo_url}
            name={@settings.name}
            color={@settings.primary_color}
            class="bg-white"
          />
          <.image_input
            upload={@uploads.logo}
            image="logo"
            present={@logo_url != nil}
            target={@myself}
            hint={
              gettext("Transparent PNG, from %{height} px high, wide logos fit best",
                height: Images.logo_min_height()
              )
            }
          />
        </div>

        <div class="space-y-3">
          <span class="text-sm font-medium">{gettext("Dark theme")}</span>
          <.logo_preview
            id="franchise-logo-dark-preview"
            url={@logo_dark_url || @logo_url}
            name={@settings.name}
            color={@settings.primary_color}
            class="bg-neutral-900"
          />
          <.image_input
            upload={@uploads.logo_dark}
            image="logo_dark"
            present={@logo_dark_url != nil}
            target={@myself}
            hint={gettext("Optional, a light version for the dark theme")}
          />
        </div>
      </form>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :url, :string, default: nil
  attr :name, :string, required: true
  attr :color, :string, required: true
  attr :class, :string, required: true

  defp logo_preview(assigns) do
    ~H"""
    <div class={["flex h-16 items-center rounded-xl border border-base-200 px-4", @class]}>
      <img :if={@url} id={@id} src={@url} class="h-10 max-w-40 object-contain" alt="" />
      <span :if={!@url} class="truncate text-2xl font-semibold" style={"color: #{@color}"}>
        {@name}
      </span>
    </div>
    """
  end
end
