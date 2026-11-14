defmodule DelivestWeb.Staff.StaffActiveBranchController do
  use DelivestWeb, :controller

  alias Delivest.Identity
  alias Delivest.Oms.Kitchen
  alias DelivestWeb.Hooks.StaffActiveBranch
  alias DelivestWeb.KitchenAccess
  alias DelivestWeb.StaffBranchPath
  alias DelivestWeb.Staff.StaffHomeController

  def all(conn, params) do
    with staff_id when is_binary(staff_id) <- get_session(conn, :staff_id),
         {:ok, _staff} <- Identity.get_staff(staff_id, preload: [:role, :branches]) do
      case network_destination(params) do
        {:ok, path} ->
          conn |> delete_session(:active_branch_id) |> redirect(to: path)

        {:choice, source} ->
          conn
          |> put_flash(
            :info,
            gettext("Choose Overview of the network to leave this branch page.")
          )
          |> redirect(to: source)

        :error ->
          redirect(conn, to: ~p"/staff/branches/select")
      end
    else
      _ -> redirect(conn, to: ~p"/staff/auth/login")
    end
  end

  def set(conn, %{"branch_id" => branch_id} = params) do
    with staff_id when is_binary(staff_id) <- get_session(conn, :staff_id),
         {:ok, staff} <- Identity.get_staff(staff_id, preload: [:role, :branches]),
         {:ok, branch} <- StaffActiveBranch.accessible(staff, branch_id) do
      case branch_destination(params, branch, staff) do
        {:ok, path} ->
          if Kitchen.account?(staff) and not Kitchen.available?(staff, branch) do
            conn
            |> put_flash(:error, KitchenAccess.message(branch))
            |> redirect(to: ~p"/staff/branches/select")
          else
            conn
            |> put_session(:active_branch_id, branch.id)
            |> redirect(to: path)
          end

        {:choice, source} ->
          conn
          |> put_flash(
            :info,
            gettext("Choose Overview of the branch to leave this network page.")
          )
          |> redirect(to: source)

        :error ->
          conn
          |> put_flash(
            :error,
            dgettext("errors", "This section is not available in the selected branch.")
          )
          |> redirect(to: ~p"/staff/branches/select")
      end
    else
      _ ->
        conn
        |> put_flash(:error, dgettext("errors", "Branch not found or access denied."))
        |> redirect(to: ~p"/staff/branches/select")
    end
  end

  defp network_destination(%{"from" => source} = params) do
    case StaffBranchPath.transition(source, :network) do
      {:ok, %{path: path}} ->
        {:ok, path}

      {:choice, %{stay: stay, overview: path}} ->
        if params["fallback"] == "overview", do: {:ok, path}, else: {:choice, stay}

      _ ->
        :error
    end
  end

  defp network_destination(_), do: {:ok, "/staff/dashboard"}

  defp branch_destination(%{"selection" => "true", "from" => source}, branch, _staff) do
    case StaffBranchPath.selection_destination(source, branch.slug) do
      {:ok, path} -> {:ok, path}
      :error -> :error
    end
  end

  defp branch_destination(%{"from" => source} = params, branch, _staff) do
    case StaffBranchPath.transition(source, {:branch, branch.slug}) do
      {:ok, %{path: path}} ->
        {:ok, path}

      {:fallback, %{path: path}} ->
        if params["fallback"] == "overview", do: {:ok, path}, else: {:choice, source}

      _ ->
        :error
    end
  end

  defp branch_destination(%{"to" => to}, branch, _staff) do
    if StaffBranchPath.valid_section?(to),
      do: {:ok, "/staff/b/#{branch.slug}" <> to},
      else: :error
  end

  defp branch_destination(_params, branch, staff),
    do: {:ok, StaffHomeController.branch_home(staff, branch)}
end
