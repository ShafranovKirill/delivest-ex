defmodule DelivestWeb.Staff.BranchLive.Edit do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.SettingsComponents

  alias Delivest.Identity
  alias Delivest.Identity.Branch
  alias Delivest.SiteSnapshot
  alias DelivestWeb.Staff.BranchLive.{BranchFormComponent, Sections}

  @impl true
  def mount(%{"slug" => slug, "section" => "ycart"}, _session, socket) do
    staff = socket.assigns.current_staff

    if Identity.can?(staff, "branches.read") and Identity.can?(staff, "integrations.read") and
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
          settings_branches: Identity.list_branch_for_staff(socket.assigns.current_staff),
          can_edit_identity: can_edit_identity?(socket.assigns.current_staff),
          delete_open: false,
          delete_name: "",
          delete_form: to_form(%{"name" => ""}, as: :confirmation)
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
    if Identity.can?(staff, "branches.read") and Identity.can?(staff, "branches.create"),
      do: {:ok, %Branch{}},
      else: {:error, gettext("You don't have permission to create branch."), ~p"/staff/branches"}
  end

  defp load(action, %{"slug" => slug}, staff) do
    with true <- action == :edit or can_edit_identity?(staff),
         %Branch{} = branch <-
           Enum.find(Identity.list_branch_for_staff(staff), &(&1.slug == slug)),
         true <-
           can_edit_identity?(staff) or
             Identity.authorize(staff, "delivery.read", branch.id) == :ok,
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

  defp can_edit_identity?(staff),
    do: Identity.can?(staff, "branches.read") and Identity.can?(staff, "branches.update")

  defp can_delete?(%{branch: %Branch{id: id}, current_staff: staff, section: %{id: :general}})
       when not is_nil(id),
       do: can_edit_identity?(staff) and Identity.authorize(staff, "branches.delete", id) == :ok

  defp can_delete?(_assigns), do: false

  defp assign_delete(socket, open?, name) do
    assign(socket,
      delete_open: open?,
      delete_name: name,
      delete_form: to_form(%{"name" => name}, as: :confirmation)
    )
  end

  @impl true
  def handle_event("reset_board_token", _params, socket) do
    if match?(%{id: :board}, socket.assigns.section) and socket.assigns.can_edit_identity do
      case Identity.reset_board_token(socket.assigns.current_staff, socket.assigns.branch) do
        {:ok, branch} ->
          {:noreply,
           socket |> assign(branch: branch) |> put_flash(:info, gettext("New link created"))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  def handle_event("open_delete", _params, socket) do
    if can_delete?(socket.assigns) do
      {:noreply, assign_delete(socket, true, "")}
    else
      {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  def handle_event("validate_delete", %{"confirmation" => %{"name" => name}}, socket)
      when is_binary(name) do
    if can_delete?(socket.assigns) and socket.assigns.delete_open do
      {:noreply, assign_delete(socket, true, name)}
    else
      {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  def handle_event("validate_delete", _params, socket),
    do: {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign_delete(socket, false, "")}

  def handle_event("confirm_delete", %{"confirmation" => %{"name" => name}}, socket)
      when is_binary(name) do
    if can_delete?(socket.assigns) and socket.assigns.delete_open do
      case Identity.soft_delete_branch(socket.assigns.current_staff, socket.assigns.branch, name) do
        {:ok, _branch} ->
          {:noreply,
           socket
           |> assign_delete(false, "")
           |> put_flash(:info, gettext("Branch deleted successfully"))
           |> push_navigate(to: ~p"/staff/branches")}

        {:error, :confirmation_mismatch} ->
          {:noreply,
           socket
           |> assign_delete(true, name)
           |> put_flash(:error, gettext("The branch name does not match."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Failed to delete branch."))}

        {:error, _operation, _reason, _changes} ->
          {:noreply, put_flash(socket, :error, gettext("Failed to delete branch."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Permission denied"))}
    end
  end

  def handle_event("confirm_delete", _params, socket),
    do: {:noreply, put_flash(socket, :error, gettext("The branch name does not match."))}

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

  def staff_page_header(%{section: nil} = assigns) do
    ~H"""
    <.page_header
      navigation_label={gettext("Settings")}
      title={@page_title}
      subtitle={gettext("Branches")}
      back={back(@branch, nil)}
    >
      <:navigation>
        <.settings_navigation
          staff={@current_staff}
          branches={@settings_branches}
          selected={@branch.id}
          current_path={@current_path}
        />
      </:navigation>
      <:actions :if={@can_edit_identity and !@branch.is_active}>
        <span class="badge badge-error badge-soft">{gettext("Branch is not active")}</span>
      </:actions>
    </.page_header>
    """
  end

  def staff_page_header(%{section: %{id: :snapshot}} = assigns) do
    ~H"""
    <.page_header
      navigation_label={gettext("Settings")}
      title={@page_title}
      subtitle={subtitle(@branch)}
      back={back(@branch, @section)}
    >
      <:navigation>
        <.settings_navigation
          staff={@current_staff}
          branches={@settings_branches}
          selected={@branch.id}
          current_path={@current_path}
        />
      </:navigation>
    </.page_header>
    """
  end

  def staff_page_header(%{section: %{id: :board}} = assigns) do
    ~H"""
    <.page_header
      navigation_label={gettext("Settings")}
      title={@page_title}
      subtitle={subtitle(@branch)}
      back={back(@branch, @section)}
    >
      <:navigation>
        <.settings_navigation
          staff={@current_staff}
          branches={@settings_branches}
          selected={@branch.id}
          current_path={@current_path}
        />
      </:navigation>
    </.page_header>
    """
  end

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      navigation_label={gettext("Settings")}
      title={@page_title}
      subtitle={subtitle(@branch)}
      back={back(@branch, @section)}
    >
      <:navigation>
        <.settings_navigation
          staff={@current_staff}
          branches={@settings_branches}
          selected={@branch.id}
          current_path={@current_path}
        />
      </:navigation>
      <:actions>
        <button
          id="branch-save"
          type="submit"
          form="branch-form"
          class="btn btn-primary"
          phx-disable-with={gettext("Saving...")}
        >
          {gettext("Save")}
        </button>
      </:actions>
    </.page_header>
    """
  end

  @impl true
  def render(%{section: nil} = assigns) do
    ~H"""
    <div class="space-y-6">
      <.settings_cards>
        <.settings_card
          :for={section <- if(@can_edit_identity, do: Sections.all(), else: [])}
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
    <div class="space-y-6">
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
    <div class="space-y-6">
      <section class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6">
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
    <div class="space-y-6">
      <.live_component
        module={BranchFormComponent}
        id={@branch.id || :new}
        action={@live_action}
        branch={@branch}
        section={@section}
        current_staff={@current_staff}
      />

      <section
        :if={can_delete?(assigns)}
        id="branch-delete-section"
        class="rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
      >
        <button
          id="branch-delete-open"
          type="button"
          phx-click={if @delete_open, do: "cancel_delete", else: "open_delete"}
          aria-expanded={to_string(@delete_open)}
          aria-controls="branch-delete-form"
          class="flex w-full items-center justify-between text-left text-sm font-medium text-base-content/70 hover:text-error"
        >
          {gettext("Branch deletion")}
          <.icon
            name={if @delete_open, do: "hero-chevron-up", else: "hero-chevron-down"}
            class="size-4"
          />
        </button>
        <.form
          :if={@delete_open}
          for={@delete_form}
          id="branch-delete-form"
          phx-change="validate_delete"
          data-staff-dirty
          phx-submit="confirm_delete"
          class="mt-4 space-y-4"
        >
          <p class="text-sm text-base-content/70">
            {gettext("Deleting the branch removes it from staff access and hides it from the app.")}
          </p>
          <p class="text-sm">
            {gettext("Enter the exact branch name to confirm deletion: %{name}", name: @branch.name)}
          </p>
          <.input
            field={@delete_form[:name]}
            type="text"
            id="branch-delete-name"
            label={gettext("Branch name")}
            autocomplete="off"
          />
          <div class="flex flex-wrap gap-2">
            <button type="button" phx-click="cancel_delete" class="btn btn-ghost">
              {gettext("Cancel")}
            </button>
            <button
              id="branch-delete-confirm"
              type="submit"
              disabled={@delete_name != @branch.name}
              class="btn btn-error"
            >
              {gettext("Delete branch")}
            </button>
          </div>
        </.form>
      </section>
    </div>
    """
  end
end
