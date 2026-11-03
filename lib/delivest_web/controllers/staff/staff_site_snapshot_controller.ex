defmodule DelivestWeb.Staff.StaffSiteSnapshotController do
  use DelivestWeb, :controller

  alias Delivest.Identity
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
      _ -> send_resp(conn, :unprocessable_entity, "Snapshot file is unavailable")
    end
  end

  def show(conn, _), do: send_resp(conn, :unauthorized, "")

  defp download(conn, staff, branch, path) do
    with {:ok, ^path} <- SiteSnapshot.export(staff, branch.id, path) do
      send_download(conn, {:file, path},
        filename: "site-#{branch.slug}.zip",
        content_type: "application/zip"
      )
    else
      {:error, {:missing_media, _bucket, key}} ->
        send_resp(conn, :unprocessable_entity, "Image is unavailable: #{key}")

      {:error, :archive_too_large} ->
        send_resp(conn, :unprocessable_entity, "Snapshot exceeds the size limit")

      _ ->
        send_resp(conn, :not_found, "")
    end
  end
end
