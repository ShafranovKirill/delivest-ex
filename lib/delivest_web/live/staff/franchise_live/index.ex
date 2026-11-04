defmodule DelivestWeb.Staff.FranchiseLive.Index do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.SettingsComponents

  alias Delivest.Franchise
  alias Delivest.Identity
  alias Delivest.SiteSnapshot
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
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: gettext("Franchise settings"),
        settings: Franchise.get_settings(),
        export_sections: Sections.export_sections()
      )
      |> load_documents()

    if socket.assigns.live_action == :section and params["section"] == "snapshot" do
      {:ok,
       socket
       |> allow_upload(:snapshot,
         accept: ~w(.zip),
         max_entries: 1,
         max_file_size: SiteSnapshot.max_archive(),
         auto_upload: true,
         progress: &handle_snapshot_progress/3
       )
       |> assign(snapshot_busy: false, snapshot_ref: nil)}
    else
      {:ok, socket}
    end
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

  def handle_info({:snapshot_result, result}, socket) do
    message =
      case result do
        {:ok, counts} ->
          gettext(
            "Branches created: %{created}. Branches updated: %{updated}.",
            created: Map.get(counts, :branches_created, 0),
            updated: Map.get(counts, :branches_updated, 0)
          )

        {:error, reason} ->
          snapshot_error(reason)
      end

    socket =
      if match?({:ok, _}, result) do
        socket
        |> assign(settings: Franchise.get_settings())
        |> load_documents()
      else
        socket
      end

    kind = if match?({:ok, _}, result), do: :info, else: :error
    {:noreply, socket |> assign(snapshot_busy: false) |> put_flash(kind, message)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{assigns: %{snapshot_ref: ref}} = socket) do
    socket = assign(socket, snapshot_ref: nil)

    if reason == :normal or !socket.assigns.snapshot_busy do
      {:noreply, socket}
    else
      {:noreply,
       socket |> assign(snapshot_busy: false) |> put_flash(:error, snapshot_error(:import_failed))}
    end
  end

  defp load_documents(socket), do: assign(socket, documents: Franchise.list_documents())

  defp visible_sections(staff) do
    sections = Sections.all()

    if Identity.can?(staff, "admin"),
      do: sections,
      else: Enum.reject(sections, &(&1.id == :snapshot))
  end

  @impl true
  def handle_event("snapshot_validate", _params, socket), do: {:noreply, socket}

  defp handle_snapshot_progress(:snapshot, entry, %{assigns: %{snapshot_busy: false}} = socket) do
    if entry.done? do
      case consume_uploaded_entries(socket, :snapshot, fn %{path: path}, _entry ->
             {:ok, File.read!(path)}
           end) do
        [archive] ->
          owner = self()
          staff = socket.assigns.current_staff

          {:ok, pid} =
            Task.start(fn ->
              result =
                try do
                  SiteSnapshot.import_franchise(staff, archive)
                rescue
                  _ -> {:error, :import_failed}
                catch
                  _, _ -> {:error, :import_failed}
                end

              send(owner, {:snapshot_result, result})
            end)

          {:noreply, socket |> assign(snapshot_busy: true, snapshot_ref: Process.monitor(pid))}

        _ ->
          {:noreply, put_flash(socket, :error, gettext("Choose a ZIP archive."))}
      end
    else
      {:noreply, socket}
    end
  end

  defp handle_snapshot_progress(:snapshot, _entry, socket), do: {:noreply, socket}

  defp snapshot_upload_error(:too_large), do: gettext("The archive exceeds the size limit.")
  defp snapshot_upload_error(:not_accepted), do: gettext("Choose a ZIP archive.")
  defp snapshot_upload_error(_), do: gettext("The archive could not be uploaded.")

  defp snapshot_error(:different_build),
    do: gettext("The archive was created by another Delivest build.")

  defp snapshot_error(:invalid_archive), do: gettext("The archive is damaged or incomplete.")
  defp snapshot_error(:archive_too_large), do: gettext("The archive exceeds the size limit.")
  defp snapshot_error(:invalid_sections), do: gettext("Choose at least one section.")

  defp snapshot_error(:too_many_branches),
    do: gettext("The archive contains too many branches.")

  defp snapshot_error(:branch_code_conflict),
    do: gettext("The archive contains a branch code that is already in use.")

  defp snapshot_error({:branch_conflict, :slug}),
    do: gettext("A branch with the same link already exists.")

  defp snapshot_error({:branch_conflict, :name}),
    do: gettext("A branch with the same name already exists.")

  defp snapshot_error({:shared_catalog_conflict, type, id}),
    do: gettext("Catalog item %{type} (%{id}) is shared with another branch.", type: type, id: id)

  defp snapshot_error({:shared_catalog_conflict, type, id, _branches}),
    do:
      gettext("Catalog item %{type} (%{id}) is shared with a branch outside the archive.",
        type: type,
        id: id
      )

  defp snapshot_error({:conflicting_mapping, type, id, _targets}),
    do: gettext("Conflicting destination mappings for %{type} (%{id}).", type: type, id: id)

  defp snapshot_error({:ambiguous_branch, source_id, _target_id}),
    do: gettext("Branch %{id} has an ambiguous destination.", id: source_id)

  defp snapshot_error(:shared_catalog_conflict),
    do: gettext("The catalog contains items shared with another branch.")

  defp snapshot_error(:id_collision),
    do: gettext("The destination contains a conflicting catalog item.")

  defp snapshot_error(:zone_conflict),
    do: gettext("A delivery zone belongs to another branch.")

  defp snapshot_error(:forbidden),
    do: gettext("You do not have permission to import this archive.")

  defp snapshot_error(_), do: gettext("Import failed. Check the archive and try again.")

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
          :for={section <- visible_sections(@current_staff)}
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

  def render(%{section: %{id: :snapshot}} = assigns) do
    ~H"""
    <div class="space-y-6 py-4 sm:p-6 max-w-4xl mx-auto">
      <.page_header
        title={@section.title}
        subtitle={@section.description}
        back={~p"/staff/franchise"}
      />

      <p
        :if={!Identity.can?(@current_staff, "admin")}
        id="snapshot-forbidden"
        class="text-sm text-error"
      >
        {gettext("Only administrators can export and import the franchise snapshot.")}
      </p>

      <div :if={Identity.can?(@current_staff, "admin")} class="space-y-6">
        <section class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6">
          <h2 class="font-semibold">{gettext("Export")}</h2>
          <p class="text-sm text-base-content/70">
            {gettext(
              "Download every branch, the shared franchise settings, legal documents and integrations into one archive."
            )}
          </p>

          <form
            id="snapshot-export-form"
            action={~p"/staff/franchise/site-snapshot"}
            method="get"
            class="space-y-4"
          >
            <div class="grid gap-2 sm:grid-cols-2">
              <label
                :for={section <- @export_sections}
                class="flex items-start gap-3 rounded-box border border-base-300 p-3 transition-colors hover:border-base-content/30"
              >
                <input
                  type="checkbox"
                  name="sections[]"
                  value={section.id}
                  checked
                  class="checkbox checkbox-sm mt-0.5"
                />
                <span class="min-w-0">
                  <span class="block text-sm font-medium">{section.title}</span>
                  <span class="block text-xs text-base-content/60">{section.description}</span>
                </span>
              </label>
            </div>

            <p class="flex items-start gap-2 text-xs text-warning">
              <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
              <span>
                {gettext(
                  "An archive with integrations contains payment and service secret keys. Store it as carefully as a password."
                )}
              </span>
            </p>

            <button id="snapshot-export" type="submit" class="btn btn-outline">
              {gettext("Download franchise snapshot")}
            </button>
          </form>
        </section>

        <section class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6">
          <h2 class="font-semibold">{gettext("Import")}</h2>
          <p class="text-sm text-base-content/70">
            {gettext(
              "Branches are matched by link: existing branches are updated, missing ones are created. Nothing in the current site is deleted."
            )}
          </p>

          <.form
            for={to_form(%{}, as: :snapshot)}
            id="snapshot-import-form"
            phx-change="snapshot_validate"
            class="space-y-3"
          >
            <label for={@uploads.snapshot.ref} class="block text-sm font-semibold">
              {gettext("Load franchise snapshot")}
            </label>
            <.live_file_input
              upload={@uploads.snapshot}
              disabled={@snapshot_busy}
              class="file-input w-full"
            />
            <p :for={entry <- @uploads.snapshot.entries} class="text-xs text-base-content/60">
              {entry.client_name} · {entry.progress}%
            </p>
            <p class="text-xs text-base-content/60">{gettext("ZIP archive, up to 100 MB.")}</p>
            <p :if={@snapshot_busy} id="snapshot-importing" class="text-sm text-base-content/70">
              {gettext("Importing…")}
            </p>
            <p :for={error <- upload_errors(@uploads.snapshot)} class="text-sm text-error">
              {snapshot_upload_error(error)}
            </p>
          </.form>
        </section>
      </div>
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
        :if={@section.id in [:brand, :auth, :seller, :loyalty]}
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
