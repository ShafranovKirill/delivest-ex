defmodule DelivestWeb.Staff.StaffSiteSnapshotController do
  use DelivestWeb, :controller

  alias Delivest.Identity
  alias Delivest.InstanceBackup
  alias Delivest.SiteSnapshot

  def show(%{assigns: %{current_staff: %{} = staff}} = conn, %{"branch_slug" => slug}) do
    with {:ok, branch} <- Identity.get_branch_by_slug(slug),
         {:ok, path} <- Plug.Upload.random_file("site-snapshot") do
      try do
        download(conn, staff, branch, path)
      after
        Plug.Upload.delete(path)
      end
    else
      {:error, :not_found} -> send_resp(conn, :not_found, "")
      _ -> send_resp(conn, :unprocessable_entity, gettext("Snapshot file is unavailable"))
    end
  end

  def show(conn, _), do: send_resp(conn, :unauthorized, "")

  def show_franchise(%{assigns: %{current_staff: %{} = staff}} = conn, params) do
    sections = List.wrap(params["sections"])

    case Plug.Upload.random_file("site-snapshot") do
      {:ok, path} ->
        try do
          download_franchise(conn, staff, sections, path)
        after
          Plug.Upload.delete(path)
        end

      _ ->
        send_resp(conn, :unprocessable_entity, gettext("Snapshot file is unavailable"))
    end
  end

  def show_franchise(conn, _), do: send_resp(conn, :unauthorized, "")

  def download_instance(%{assigns: %{current_staff: %{} = staff}} = conn, %{"id" => id}) do
    case InstanceBackup.download(staff, id) do
      {:ok, path} ->
        send_download(conn, {:file, path},
          filename: "delivest-instance-#{id}.tar",
          content_type: "application/x-tar"
        )

      _ ->
        send_resp(conn, :not_found, "")
    end
  end

  def download_instance(conn, _), do: send_resp(conn, :unauthorized, "")

  defp download_franchise(conn, staff, sections, path) do
    case SiteSnapshot.export_franchise(staff, sections, path) do
      {:ok, ^path} ->
        send_download(conn, {:file, path},
          filename: "franchise-#{Date.utc_today()}.zip",
          content_type: "application/zip"
        )

      {:error, :forbidden} ->
        conn
        |> put_flash(:error, gettext("You do not have permission to export the franchise."))
        |> redirect(to: ~p"/staff/franchise")
        |> halt()

      {:error, :invalid_sections} ->
        conn
        |> put_flash(:error, gettext("Choose at least one section to export."))
        |> redirect(to: ~p"/staff/franchise/snapshot")
        |> halt()

      {:error, {:missing_media, _bucket, key}} ->
        send_resp(conn, :unprocessable_entity, gettext("Image is unavailable: %{key}", key: key))

      {:error, :archive_too_large} ->
        send_resp(conn, :unprocessable_entity, gettext("Snapshot exceeds the size limit"))

      _ ->
        send_resp(conn, :unprocessable_entity, gettext("Snapshot file is unavailable"))
    end
  end

  defp download(conn, staff, branch, path) do
    with {:ok, ^path} <- SiteSnapshot.export(staff, branch.id, path) do
      send_download(conn, {:file, path},
        filename: "site-#{branch.slug}.zip",
        content_type: "application/zip"
      )
    else
      {:error, {:missing_media, _bucket, key}} ->
        send_resp(conn, :unprocessable_entity, gettext("Image is unavailable: %{key}", key: key))

      {:error, :archive_too_large} ->
        send_resp(conn, :unprocessable_entity, gettext("Snapshot exceeds the size limit"))

      _ ->
        send_resp(conn, :not_found, "")
    end
  end
end
