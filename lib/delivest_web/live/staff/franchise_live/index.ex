defmodule DelivestWeb.Staff.FranchiseLive.Index do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.SettingsComponents

  alias Delivest.Franchise
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  alias DelivestWeb.Staff.FranchiseLive.{
    DocumentFormComponent,
    FranchiseHelpers,
    ImagesComponent,
    LogoComponent,
    Sections,
    SettingsFormComponent
  }

  on_mount {DelivestWeb.Hooks.Permission, "franchise.update"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Franchise settings"), settings: Franchise.get_settings())
     |> load_documents()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    case section(socket.assigns.live_action, params) do
      {:ok, section} ->
        {:noreply,
         assign(socket,
           section: section,
           document: document(socket, params),
           page_title: title(section)
         )}

      :error ->
        {:noreply, push_navigate(socket, to: ~p"/staff/franchise")}
    end
  end

  defp section(:index, _params), do: {:ok, nil}
  defp section(:document, _params), do: {:ok, Sections.describe(:documents)}
  defp section(:section, %{"section" => section}), do: Sections.fetch(section)

  defp title(nil), do: gettext("Franchise settings")
  defp title(section), do: section.title

  defp document(socket, %{"kind" => kind}) do
    case Franchise.parse_document_kind(kind) do
      :error -> nil
      kind -> Enum.find(socket.assigns.documents, &(&1.kind == kind))
    end
  end

  defp document(_socket, _params), do: nil

  @impl true
  def handle_info({SettingsFormComponent, {:saved, settings}}, socket) do
    {:noreply,
     socket |> assign(settings: settings) |> put_flash(:info, gettext("Settings saved"))}
  end

  def handle_info({component, {:saved, settings}}, socket)
      when component in [ImagesComponent, LogoComponent] do
    {:noreply, socket |> assign(settings: settings) |> put_flash(:info, gettext("Image saved"))}
  end

  def handle_info({component, {:error, message}}, socket)
      when component in [ImagesComponent, LogoComponent],
      do: {:noreply, put_flash(socket, :error, message)}

  def handle_info({DocumentFormComponent, :saved}, socket) do
    {:noreply,
     socket
     |> load_documents()
     |> put_flash(:info, gettext("Document saved"))
     |> push_patch(to: ~p"/staff/franchise/documents")}
  end

  defp load_documents(socket), do: assign(socket, documents: Franchise.list_documents())

  @impl true
  def render(%{section: nil} = assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-6xl mx-auto">
      <.page_header
        title={gettext("Franchise settings")}
        subtitle={gettext("Name, brand color, seller details and legal documents for all branches.")}
      />

      <.settings_cards>
        <.settings_card
          :for={section <- Sections.all()}
          id={"franchise-section-#{section.id}"}
          navigate={~p"/staff/franchise/#{section.id}"}
          icon={section.icon}
          title={section.title}
          description={section.description}
        />
      </.settings_cards>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-4xl mx-auto">
      <.page_header
        title={@section.title}
        subtitle={@section.description}
        back={~p"/staff/franchise"}
      />

      <.live_component
        :if={@section.id in [:brand, :seller]}
        module={SettingsFormComponent}
        id="franchise-settings"
        section={@section.id}
        settings={@settings}
        current_staff={@current_staff}
      />

      <.live_component
        :if={@section.id == :logo}
        module={LogoComponent}
        id="franchise-logo"
        settings={@settings}
        current_staff={@current_staff}
      />

      <.live_component
        :if={@section.id == :images}
        module={ImagesComponent}
        id="franchise-images"
        settings={@settings}
        current_staff={@current_staff}
      />

      <section
        :if={@section.id == :documents}
        class="p-5 bg-base-100 rounded-box border border-base-300"
      >
        <div id="legal-documents" class="divide-y divide-base-200">
          <div
            :for={document <- @documents}
            id={"document-#{document.kind}"}
            class="flex items-center gap-3 py-3"
          >
            <.icon name="hero-document-text" class="size-5 text-primary shrink-0" />
            <div class="min-w-0 flex-1">
              <p class="font-medium truncate">{FranchiseHelpers.document_title(document.kind)}</p>
              <p class="text-xs text-base-content/50">
                {if document.custom,
                  do:
                    gettext("Edited %{date}",
                      date: OrderHelpers.local_datetime(document.updated_at)
                    ),
                  else: gettext("Default template")}
              </p>
            </div>
            <.link
              patch={~p"/staff/franchise/documents/#{document.kind}"}
              class="btn btn-sm btn-ghost btn-square text-info"
              title={gettext("Edit")}
            >
              <.icon name="hero-pencil-square" class="size-5" />
            </.link>
          </div>
        </div>
      </section>

      <.slide_over
        id="document-slideover"
        show={@document != nil}
        title={if @document, do: FranchiseHelpers.document_title(@document.kind), else: ""}
        on_close={JS.patch(~p"/staff/franchise/documents")}
      >
        <.live_component
          :if={@document}
          module={DocumentFormComponent}
          id={"document-#{@document.kind}"}
          document={@document}
          current_staff={@current_staff}
          patch={~p"/staff/franchise/documents"}
        />
      </.slide_over>
    </div>
    """
  end
end
