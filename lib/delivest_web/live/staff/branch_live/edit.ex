defmodule DelivestWeb.Staff.BranchLive.Edit do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.SettingsComponents

  alias Delivest.Identity
  alias Delivest.Identity.Branch
  alias Delivest.SiteSnapshot
  alias DelivestWeb.Staff.BranchLive.{BranchFormComponent, Sections}

  on_mount {DelivestWeb.Hooks.Permission, "branches.read"}

  @impl true
  def mount(%{"slug" => slug, "section" => "ycart"}, _session, socket) do
    staff = socket.assigns.current_staff

    if Identity.can?(staff, "integrations.read") and
         Enum.any?(Identity.list_branch_for_staff(staff), &(&1.slug == slug)) do
      {:ok, push_navigate(socket, to: ~p"/staff/b/#{slug}/integrations/ycart")}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Permission denied"))
       |> push_navigate(to: ~p"/staff/branches")}
    end
  end

  def mount(params, _session, socket) do
    with {:ok, branch} <- load(socket.assigns.live_action, params, socket.assigns.current_staff),
         {:ok, section} <- section(socket.assigns.live_action, params) do
      socket =
        assign(socket,
          branch: branch,
          section: section,
          page_title: title(branch, section),
          settings_branches: Identity.list_branch_for_staff(socket.assigns.current_staff)
        )

      if section && section.id == :snapshot do
        {:ok,
         socket
         |> allow_upload(:snapshot,
           accept: ~w(.zip),
           max_entries: 1,
           max_file_size: SiteSnapshot.max_archive(),
           auto_upload: true,
           progress: &handle_snapshot_progress/3
         )
         |> assign(snapshot_busy: false)}
      else
        {:ok, socket}
      end
    else
      {:error, message, to} ->
        {:ok, socket |> put_flash(:error, message) |> push_navigate(to: to)}
    end
  end

  defp load(:new, _params, staff) do
    if Identity.can?(staff, "branches.create"),
      do: {:ok, %Branch{}},
      else: {:error, gettext("You don't have permission to create branch."), ~p"/staff/branches"}
  end

  defp load(_action, %{"slug" => slug}, staff) do
    with true <- Identity.can?(staff, "branches.update"),
         %Branch{} = branch <-
           Enum.find(Identity.list_branch_for_staff(staff), &(&1.slug == slug)),
         {:ok, branch} <- Identity.get_branch(branch.id, preload: [:info]) do
      {:ok, branch}
    else
      false ->
        {:error, gettext("You don't have permission to edit branches."), ~p"/staff/branches"}

      _ ->
        {:error, gettext("Branch not found."), ~p"/staff/branches"}
    end
  end

  defp section(:new, _params), do: {:ok, Sections.describe(:general)}
  defp section(:edit, _params), do: {:ok, nil}

  defp section(:section, %{"slug" => slug, "section" => section}) do
    case Sections.fetch(section) do
      {:ok, section} -> {:ok, section}
      :error -> {:error, gettext("Page not found"), ~p"/staff/branches/#{slug}/edit"}
    end
  end

  defp title(%Branch{id: nil}, _section), do: gettext("Create branch")
  defp title(branch, nil), do: branch.name
  defp title(_branch, section), do: section.title

  defp back(%Branch{id: nil}, _section), do: ~p"/staff/branches"
  defp back(_branch, nil), do: ~p"/staff/branches"
  defp back(branch, _section), do: ~p"/staff/branches/#{branch.slug}/edit"

  defp subtitle(%Branch{id: nil}), do: gettext("Branches")
  defp subtitle(branch), do: branch.name

  @impl true
  def handle_event("reset_board_token", _params, socket) do
    case Identity.reset_board_token(socket.assigns.current_staff, socket.assigns.branch) do
      {:ok, branch} ->
        {:noreply,
         socket |> assign(branch: branch) |> put_flash(:info, gettext("New link created"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
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
          branch_id = socket.assigns.branch.id

          {:ok, pid} =
            Task.start(fn ->
              result =
                try do
                  SiteSnapshot.import(staff, branch_id, archive)
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

  @impl true
  def handle_info({:snapshot_result, result}, socket) do
    message =
      case result do
        {:ok, counts} ->
          gettext(
            "Created records: %{created}. Updated records: %{updated}.",
            counts
          )

        {:error, reason} ->
          snapshot_error(reason)
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

  defp snapshot_upload_error(:too_large), do: gettext("The archive exceeds the size limit.")
  defp snapshot_upload_error(:not_accepted), do: gettext("Choose a ZIP archive.")
  defp snapshot_upload_error(_), do: gettext("The archive could not be uploaded.")

  defp snapshot_error(:different_build),
    do: gettext("The archive was created by another Delivest build.")

  defp snapshot_error(:invalid_archive), do: gettext("The archive is damaged or incomplete.")
  defp snapshot_error(:archive_too_large), do: gettext("The archive exceeds the size limit.")

  defp snapshot_error({:shared_catalog_conflict, type, id}),
    do: gettext("Catalog item %{type} (%{id}) is shared with another branch.", type: type, id: id)

  defp snapshot_error(:shared_catalog_conflict),
    do: gettext("The catalog contains items shared with another branch.")

  defp snapshot_error(:id_collision),
    do: gettext("The destination contains a conflicting catalog item.")

  defp snapshot_error(:forbidden),
    do: gettext("You do not have permission to import this archive.")

  defp snapshot_error(_), do: gettext("Import failed. Check the archive and try again.")

  defp board_url(%Branch{info: %{board_token: token}}) when is_binary(token),
    do: url(~p"/board/#{token}")

  defp board_url(_branch), do: nil

  @impl true
  def render(%{section: nil} = assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl space-y-6 p-6">
      <.page_header title={@page_title} subtitle={gettext("Branches")} back={back(@branch, nil)}>
        <:actions :if={!@branch.is_active}>
          <span class="badge badge-error badge-soft">{gettext("Branch is not active")}</span>
        </:actions>
      </.page_header>

      <.settings_navigation
        staff={@current_staff}
        branches={@settings_branches}
        selected={@branch.id}
      />

      <.settings_cards>
        <.settings_card
          :for={section <- Sections.all()}
          id={"branch-section-#{section.id}"}
          navigate={~p"/staff/branches/#{@branch.slug}/edit/#{section.id}"}
          icon={section.icon}
          title={section.title}
          description={section.description}
        />
        <.settings_card
          :if={Identity.authorize(@current_staff, "delivery.read", @branch.id) == :ok}
          id="branch-delivery-card"
          navigate={~p"/staff/b/#{@branch}/delivery"}
          icon="hero-truck"
          title={gettext("Delivery")}
          description={gettext("Delivery zones and couriers for this branch.")}
        />
      </.settings_cards>
    </div>
    """
  end

  def render(%{section: %{id: :snapshot}} = assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl space-y-6 p-6">
      <.page_header title={@page_title} subtitle={subtitle(@branch)} back={back(@branch, @section)} />
      <.settings_navigation
        staff={@current_staff}
        branches={@settings_branches}
        selected={@branch.id}
      />
      <section class="space-y-5 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6">
        <p class="text-sm text-base-content/70">
          {gettext(
            "Transfer this branch's storefront settings, catalog and images between sites running the same build. The storefront appearance is shared across the destination site."
          )}
        </p>
        <a
          id="snapshot-export"
          href={~p"/staff/b/#{@branch.slug}/site-snapshot"}
          class="btn btn-outline"
        >
          {gettext("Download site snapshot")}
        </a>
        <.form
          for={to_form(%{}, as: :snapshot)}
          id="snapshot-import-form"
          phx-change="snapshot_validate"
          class="space-y-3"
        >
          <label for={@uploads.snapshot.ref} class="block text-sm font-semibold">
            {gettext("Load site snapshot")}
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
    """
  end

  def render(%{section: %{id: :board}} = assigns) do
    assigns = assign(assigns, url: board_url(assigns.branch))

    ~H"""
    <div class="mx-auto max-w-3xl space-y-6 p-6">
      <.page_header title={@page_title} subtitle={subtitle(@branch)} back={back(@branch, @section)} />
      <.settings_navigation
        staff={@current_staff}
        branches={@settings_branches}
        selected={@branch.id}
      />

      <section class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6">
        <p class="text-sm text-base-content/60">{@section.description}</p>
        <p class="text-sm text-base-content/60">
          {gettext(
            "Open the link on the screen in the hall, no sign-in is needed. Pickup and hall orders only, the number stays in «Ready» until the order is handed over or cancelled."
          )}
        </p>

        <div :if={@url} class="join w-full">
          <input
            id="board-url"
            type="text"
            readonly
            value={@url}
            class="input join-item w-full font-mono text-sm"
          />
          <a href={@url} target="_blank" class="btn join-item">
            <.icon name="hero-arrow-top-right-on-square" class="size-4" />
          </a>
        </div>

        <button
          id="board-reset"
          type="button"
          phx-click="reset_board_token"
          data-confirm={@url && gettext("The old link stops working. Continue?")}
          class="btn btn-primary"
        >
          {if @url, do: gettext("New link"), else: gettext("Create link")}
        </button>
      </section>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl space-y-6 p-6">
      <.page_header title={@page_title} subtitle={subtitle(@branch)} back={back(@branch, @section)} />
      <.settings_navigation
        staff={@current_staff}
        branches={@settings_branches}
        selected={@branch.id}
      />

      <.live_component
        module={BranchFormComponent}
        id={@branch.id || :new}
        action={@live_action}
        branch={@branch}
        section={@section}
        current_staff={@current_staff}
      />
    </div>
    """
  end
end
