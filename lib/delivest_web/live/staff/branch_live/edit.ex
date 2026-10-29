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
