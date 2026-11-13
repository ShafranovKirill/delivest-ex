defmodule DelivestWeb.Staff.AdvertisingLive.Index do
  import DelivestWeb.Staff.MarketingLive.Navigation
  use DelivestWeb, :live_view

  alias Delivest.Advertising.{Link, Links}

  on_mount {DelivestWeb.Hooks.Permission, "statistics.read"}

  @impl true
  def mount(_params, _session, socket) do
    branch_id = socket.assigns.current_branch.id

    case Links.list(socket.assigns.current_staff, branch_id) do
      {:ok, page} ->
        {:ok,
         socket
         |> assign(
           page_title: gettext("Advertising links"),
           form: form(),
           error: nil,
           next_cursor: page.next_cursor,
           has_more: page.has_more
         )
         |> stream(:links, page.links)}

      _ ->
        {:ok, redirect(socket, to: ~p"/staff/b/#{socket.assigns.current_branch}/statistics")}
    end
  end

  def handle_event("load_more", _, socket) do
    case Links.list(
           socket.assigns.current_staff,
           socket.assigns.current_branch.id,
           socket.assigns.next_cursor
         ) do
      {:ok, page} ->
        {:noreply,
         socket
         |> assign(next_cursor: page.next_cursor, has_more: page.has_more, error: nil)
         |> stream(:links, page.links)}

      _ ->
        {:noreply, assign(socket, error: gettext("Advertising links are unavailable"))}
    end
  end

  @impl true
  def handle_event("validate", %{"link" => attrs}, socket) do
    changeset = Link.changeset(%Link{}, attrs) |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(changeset), error: nil)}
  end

  def handle_event("create", %{"link" => attrs}, socket) do
    branch_id = socket.assigns.current_branch.id

    case Links.create(socket.assigns.current_staff, branch_id, attrs) do
      {:ok, link} ->
        {:noreply,
         socket |> assign(form: form(), error: nil) |> stream_insert(:links, link, at: 0)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(%{changeset | action: :insert}))}

      _ ->
        {:noreply, assign(socket, error: gettext("Advertising links are unavailable"))}
    end
  end

  def handle_event("toggle", %{"id" => id, "enabled" => value}, socket) do
    update_link(
      socket,
      Links.set_enabled(
        socket.assigns.current_staff,
        socket.assigns.current_branch.id,
        id,
        value == "true"
      )
    )
  end

  def handle_event("archive", %{"id" => id}, socket) do
    update_link(
      socket,
      Links.archive(socket.assigns.current_staff, socket.assigns.current_branch.id, id)
    )
  end

  defp update_link(socket, {:ok, link}), do: {:noreply, stream_insert(socket, :links, link)}

  defp update_link(socket, _),
    do: {:noreply, assign(socket, error: gettext("Could not update advertising link"))}

  defp form, do: %Link{} |> Link.changeset(%{}) |> to_form()

  def staff_page_header(assigns) do
    ~H"""
    <.page_header
      navigation_label={gettext("Marketing areas")}
      title={gettext("Advertising links")}
      subtitle={@current_branch.name}
    >
      <:navigation>
        <.navigation
          staff={@current_staff}
          branches={@staff_branches}
          branch={@current_branch}
          active={:links}
          part={:areas}
        />
      </:navigation>
      <:actions>
        <button type="submit" form="advertising-link-form" class="btn btn-primary">{gettext(
          "Create link"
        )}</button>
      </:actions>
    </.page_header>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.navigation
        staff={@current_staff}
        branches={@staff_branches}
        branch={@current_branch}
        active={:links}
        part={:branches}
      />

      <.form
        for={@form}
        id="advertising-link-form"
        phx-change="validate"
        phx-submit="create"
        class="rounded-2xl border border-base-300 p-5 grid gap-4 md:grid-cols-[1fr_1fr_auto] md:items-end"
      >
        <.input field={@form[:campaign]} type="text" label={gettext("Campaign slug")} required />
        <.input field={@form[:name]} type="text" label={gettext("Link name")} required />
      </.form>
      <p :if={@error} id="advertising-link-error" role="alert" class="text-error">{@error}</p>

      <div id="advertising-links" phx-update="stream" class="grid gap-3">
        <div
          :for={{id, link} <- @streams.links}
          id={id}
          class="rounded-2xl border border-base-300 p-4 space-y-3"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p class="font-semibold">{link.name}</p>
              <p class="text-sm text-base-content/60">{link.campaign}</p>
            </div>
            <span class="badge badge-outline">{if link.archived_at,
              do: gettext("Archived"),
              else: if(link.enabled, do: gettext("Enabled"), else: gettext("Disabled"))}</span>
          </div>
          <div class="flex gap-2">
            <input
              id={"advertising-url-#{link.id}"}
              class="input input-bordered w-full"
              readonly
              value={url(~p"/r/#{link.token}")}
              aria-label={gettext("Advertising URL")}
            />
            <button
              id={"advertising-copy-#{link.id}"}
              type="button"
              class="btn btn-outline"
              phx-hook="CopyLink"
              data-url={url(~p"/r/#{link.token}")}
              data-status-id={"advertising-copy-status-#{link.id}"}
              data-copy-success={gettext("Link copied")}
              data-copy-failure={gettext("Could not copy link. Select the URL to copy it manually.")}
            >{gettext("Copy")}</button>
          </div>
          <p
            id={"advertising-copy-status-#{link.id}"}
            role="status"
            aria-live="polite"
            class="text-sm"
          >
          </p>
          <div :if={is_nil(link.archived_at)} class="flex gap-2">
            <.link
              id={"advertising-statistics-#{link.id}"}
              navigate={
                ~p"/staff/b/#{@current_branch}/statistics?#{%{tab: "sources", link_id: link.id}}"
              }
              class="btn btn-sm btn-outline"
            >
              {gettext("View source statistics")}
            </.link>
            <button
              id={"advertising-toggle-#{link.id}"}
              type="button"
              class="btn btn-sm btn-outline"
              phx-click="toggle"
              phx-value-id={link.id}
              phx-value-enabled={to_string(!link.enabled)}
            >{if link.enabled, do: gettext("Disable"), else: gettext("Enable")}</button>
            <button
              id={"advertising-archive-#{link.id}"}
              type="button"
              class="btn btn-sm btn-ghost"
              phx-click="archive"
              phx-value-id={link.id}
              data-confirm={gettext("Archive this link?")}
            >{gettext("Archive")}</button>
          </div>
        </div>
      </div>
      <button
        :if={@has_more}
        id="advertising-load-more"
        type="button"
        class="btn btn-outline"
        phx-click="load_more"
      >{gettext("Load more")}</button>
    </div>
    """
  end
end
