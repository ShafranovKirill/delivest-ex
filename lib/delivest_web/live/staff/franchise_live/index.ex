defmodule DelivestWeb.Staff.FranchiseLive.Index do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.SettingsComponents

  alias Delivest.Franchise
  alias Delivest.Identity
  alias Delivest.InstanceBackup
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
    if connected?(socket) and Identity.can?(socket.assigns.current_staff, "admin"),
      do: Process.send_after(self(), :backup_poll, 2_000)

    socket =
      socket
      |> assign(
        page_title: gettext("Franchise settings"),
        settings: Franchise.get_settings()
      )
      |> load_documents()

    if socket.assigns.live_action == :section and params["section"] == "snapshot" and
         Identity.can?(socket.assigns.current_staff, "admin") do
      {:ok,
       socket
       |> allow_upload(:instance_archive,
         accept: ~w(.tar),
         max_entries: 1,
         max_file_size: InstanceBackup.max_archive()
       )
       |> assign(backup_job: InstanceBackup.active(), backup_agent: InstanceBackup.heartbeat?())}
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

  def handle_info(:backup_poll, socket) do
    if Identity.can?(socket.assigns.current_staff, "admin") do
      if connected?(socket), do: Process.send_after(self(), :backup_poll, 2_000)

      {:noreply,
       assign(socket,
         backup_job: InstanceBackup.active(),
         backup_agent: InstanceBackup.heartbeat?()
       )}
    else
      {:noreply, socket}
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
  def handle_event("backup_validate", _params, socket), do: {:noreply, backup_authorize(socket)}

  def handle_event("backup_export", _, socket) do
    result = InstanceBackup.submit(socket.assigns.current_staff, "export")
    {:noreply, backup_result(socket, result)}
  end

  def handle_event("backup_import", %{"confirm" => "replace"}, socket) do
    if InstanceBackup.authorized?(socket.assigns.current_staff) do
      results =
        consume_uploaded_entries(socket, :instance_archive, fn %{path: path}, _entry ->
          {:ok, InstanceBackup.submit(socket.assigns.current_staff, "import", path)}
        end)

      result =
        case results do
          [result] -> result
          _ -> {:error, :invalid_archive}
        end

      {:noreply, backup_result(socket, result)}
    else
      {:noreply, backup_result(socket, {:error, :forbidden})}
    end
  end

  def handle_event("backup_import", _, socket) do
    socket = backup_authorize(socket)

    if Identity.can?(socket.assigns.current_staff, "admin"),
      do:
        {:noreply,
         put_flash(socket, :error, gettext("Confirm full replacement before restoring."))},
      else: {:noreply, socket}
  end

  defp backup_authorize(socket) do
    if Identity.can?(socket.assigns.current_staff, "admin"),
      do: socket,
      else: put_flash(socket, :error, gettext("Administrator access is required."))
  end

  defp backup_available?(agent, nil), do: agent

  defp backup_available?(agent, job),
    do: agent and InstanceBackup.terminal?(job) and InstanceBackup.safe?(job)

  defp backup_phase("queued"), do: gettext("Queued")
  defp backup_phase("waiting"), do: gettext("Waiting for the site to stop")
  defp backup_phase("running"), do: gettext("Running")
  defp backup_phase("complete"), do: gettext("Complete")
  defp backup_phase("failed"), do: gettext("Failed")
  defp backup_phase("interrupted"), do: gettext("Interrupted; manual recovery required")
  defp backup_phase(_), do: gettext("Unknown status")

  defp backup_upload_error(:too_large), do: gettext("The archive exceeds the size limit.")
  defp backup_upload_error(:not_accepted), do: gettext("Choose a TAR archive.")
  defp backup_upload_error(_), do: gettext("The archive could not be uploaded.")
  defp backup_size_gib, do: div(InstanceBackup.max_archive() + 1_073_741_823, 1_073_741_824)

  defp backup_result(socket, {:ok, _id}) do
    socket
    |> assign(backup_job: InstanceBackup.active())
    |> put_flash(:info, gettext("Backup job queued."))
  end

  defp backup_result(socket, {:error, reason}) do
    message =
      case reason do
        :forbidden -> gettext("Administrator access is required.")
        :agent_unavailable -> gettext("Backup agent is unavailable. Start the agent and retry.")
        :disabled -> gettext("Instance backup is not configured.")
        :busy -> gettext("A backup job is active or needs manual recovery.")
        _ -> gettext("Could not submit backup job. Check the archive and retry.")
      end

    put_flash(socket, :error, message)
  end

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
        <p :if={!@backup_agent} id="backup-agent-unavailable" class="text-sm text-warning">
          {gettext("Backup agent is unavailable. Start the agent and check its shared directory.")}
        </p>
        <section
          id="instance-backup-status"
          class="rounded-box border border-base-300 bg-base-100 p-5"
        >
          <h2 class="font-semibold">{gettext("Full instance backup")}</h2>
          <p class="text-sm text-base-content/70">
            {gettext(
              "The archive contains the entire database and every stored file, including private files. Protect it as a secret."
            )}
          </p>
          <div :if={@backup_job} class="mt-3 text-sm">
            <span id="backup-phase">{backup_phase(@backup_job.status["phase"])}</span>
            <span :if={@backup_job.status["phase"] in ~w(failed interrupted)} id="backup-message">{@backup_job.status[
              "message"
            ]}</span>
            <.link
              :if={
                @backup_job.request["action"] == "export" and
                  @backup_job.status["phase"] == "complete" and
                  @backup_job.request["requested_by"] == @current_staff.id
              }
              id="backup-download"
              href={~p"/staff/franchise/instance-backup/#{@backup_job.id}"}
              class="btn btn-outline btn-sm ml-3"
            >{gettext("Download archive")}</.link>
          </div>
          <button
            id="backup-export"
            type="button"
            phx-click="backup_export"
            disabled={!backup_available?(@backup_agent, @backup_job)}
            class="btn btn-outline mt-4"
          >
            {gettext("Create full backup")}
          </button>
        </section>
        <section class="rounded-box border border-warning/50 bg-base-100 p-5 space-y-3">
          <h2 class="font-semibold">{gettext("Restore full instance")}</h2>
          <p class="text-sm text-warning">
            {gettext(
              "Restoring replaces the entire database and all stored files. The site will disconnect temporarily. Sign in with staff credentials from the restored archive after it restarts."
            )}
          </p>
          <.form
            for={to_form(%{}, as: :backup)}
            id="backup-import-form"
            phx-change="backup_validate"
            phx-submit="backup_import"
            class="space-y-3"
          >
            <.live_file_input upload={@uploads.instance_archive} class="file-input w-full" />
            <p class="text-xs text-base-content/60">
              {gettext("TAR archive, up to %{size} GiB.", size: backup_size_gib())}
            </p>
            <p :for={entry <- @uploads.instance_archive.entries} class="text-xs">
              {entry.client_name} · {entry.progress}%
            </p>
            <p :for={entry <- @uploads.instance_archive.entries} class="text-sm text-error">
              <span :for={error <- upload_errors(@uploads.instance_archive, entry)}>{backup_upload_error(
                error
              )}</span>
            </p>
            <p :for={error <- upload_errors(@uploads.instance_archive)} class="text-sm text-error">
              {backup_upload_error(error)}
            </p>
            <label class="flex items-center gap-2 text-sm">
              <input
                id="backup-confirm"
                type="checkbox"
                name="confirm"
                value="replace"
                class="checkbox checkbox-sm"
              />
              {gettext("I understand this replaces the full instance")}
            </label>
            <button
              id="backup-import"
              type="submit"
              disabled={!backup_available?(@backup_agent, @backup_job)}
              class="btn btn-warning"
            >
              {gettext("Restore archive")}
            </button>
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
