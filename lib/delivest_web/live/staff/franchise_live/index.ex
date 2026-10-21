defmodule DelivestWeb.Staff.FranchiseLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.Franchise
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  alias DelivestWeb.Staff.FranchiseLive.{
    DocumentFormComponent,
    FranchiseHelpers,
    SettingsFormComponent
  }

  on_mount {DelivestWeb.Hooks.Permission, "admin"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Franchise settings"), settings: Franchise.get_settings())
     |> load_documents()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, assign(socket, document: document(socket, params))}
  end

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

  def handle_info({DocumentFormComponent, :saved}, socket) do
    {:noreply,
     socket
     |> load_documents()
     |> put_flash(:info, gettext("Document saved"))
     |> push_patch(to: ~p"/staff/franchise")}
  end

  defp load_documents(socket), do: assign(socket, documents: Franchise.list_documents())

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-4xl mx-auto">
      <.page_header
        title={gettext("Franchise settings")}
        subtitle={gettext("Name, brand color, seller details and legal documents for all branches.")}
      />

      <.live_component
        module={SettingsFormComponent}
        id="franchise-settings"
        settings={@settings}
        current_staff={@current_staff}
      />

      <section class="p-5 bg-base-100 rounded-box border border-base-200 shadow-sm space-y-3">
        <div>
          <h2 class="font-bold text-lg">{gettext("Legal documents")}</h2>
          <p class="text-sm text-base-content/60">
            {gettext(
              "Default templates already contain your details. Have a lawyer check them before publishing."
            )}
          </p>
        </div>

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
        on_close={JS.patch(~p"/staff/franchise")}
      >
        <.live_component
          :if={@document}
          module={DocumentFormComponent}
          id={"document-#{@document.kind}"}
          document={@document}
          current_staff={@current_staff}
          patch={~p"/staff/franchise"}
        />
      </.slide_over>
    </div>
    """
  end
end
