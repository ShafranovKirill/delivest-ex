defmodule DelivestWeb.Staff.BranchLive.Edit do
  use DelivestWeb, :live_view

  import DelivestWeb.Staff.SettingsComponents

  alias Delivest.Identity
  alias Delivest.Identity.Branch
  alias DelivestWeb.Staff.BranchLive.{BranchFormComponent, Sections}

  on_mount {DelivestWeb.Hooks.Permission, "branches.read"}

  @impl true
  def mount(params, _session, socket) do
    with {:ok, branch} <- load(socket.assigns.live_action, params, socket.assigns.current_staff),
         {:ok, section} <- section(socket.assigns.live_action, params) do
      {:ok, assign(socket, branch: branch, section: section, page_title: title(branch, section))}
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

      <.settings_cards>
        <.settings_card
          :for={section <- Sections.all()}
          id={"branch-section-#{section.id}"}
          navigate={~p"/staff/branches/#{@branch.slug}/edit/#{section.id}"}
          icon={section.icon}
          title={section.title}
          description={section.description}
        />
      </.settings_cards>
    </div>
    """
  end

  def render(%{section: %{id: :board}} = assigns) do
    assigns = assign(assigns, url: board_url(assigns.branch))

    ~H"""
    <div class="mx-auto max-w-3xl space-y-6 p-6">
      <.page_header title={@page_title} subtitle={subtitle(@branch)} back={back(@branch, @section)} />

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
