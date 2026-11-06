defmodule Delivest.InstanceBackup do
  @moduledoc "Durable filesystem protocol shared with the instance backup agent."

  alias Delivest.Identity

  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @terminal ~w(complete failed interrupted)

  def enabled?, do: is_binary(dir()) and dir() != ""
  def dir, do: Application.get_env(:delivest, :instance_backup_dir)
  def managed?, do: Application.get_env(:delivest, :instance_backup_managed, false)

  def max_archive,
    do: Application.get_env(:delivest, :instance_backup_max_archive, 20 * 1024 * 1024 * 1024)

  def authorized?(staff), do: Identity.can?(staff, "admin")
  def valid_id?(id), do: is_binary(id) and Regex.match?(@uuid, id)
  def job_dir(id) when is_binary(id), do: if(valid_id?(id), do: Path.join([dir(), "jobs", id]))

  def heartbeat? do
    with %{"protocol" => 1, "updated_at" => time} <-
           read_json(Path.join(dir() || "", "heartbeat.json")),
         {:ok, updated, _} <- DateTime.from_iso8601(time) do
      DateTime.diff(DateTime.utc_now(), updated, :second) in 0..29
    else
      _ -> false
    end
  end

  def active(backup_dir \\ dir()) do
    case read_json(Path.join(backup_dir || "", "active.json")) do
      %{"id" => id} when is_binary(id) ->
        if valid_id?(id), do: job(id, backup_dir), else: nil

      _ ->
        nil
    end
  end

  def job(id, backup_dir \\ dir()) do
    if valid_id?(id) and is_binary(backup_dir) and backup_dir != "" do
      path = Path.join([backup_dir, "jobs", id])
      request = read_json(Path.join(path, "request.json"))
      status = read_json(Path.join(path, "status.json"))

      if is_map(request) and is_map(status) and request["id"] == id and status["id"] == id,
        do: %{request: request, status: status, id: id},
        else: nil
    end
  end

  def terminal?(%{status: %{"phase" => phase}}), do: phase in @terminal
  def terminal?(_), do: false
  def safe?(%{status: %{"safe_to_resume" => true}}), do: true
  def safe?(_), do: false

  def submit(staff, action, upload_path \\ nil) when action in ["export", "import"] do
    cond do
      not authorized?(staff) -> {:error, :forbidden}
      not enabled?() -> {:error, :disabled}
      not heartbeat?() -> {:error, :agent_unavailable}
      true -> with_lock(fn -> submit_locked(staff, action, upload_path) end)
    end
  end

  def download(staff, id) do
    with true <- authorized?(staff),
         %{
           request: %{"action" => "export", "requested_by" => owner},
           status: %{"phase" => "complete"}
         } <- job(id),
         true <- owner == staff.id,
         path <- Path.join(job_dir(id), "archive.tar"),
         {:ok, %File.Stat{type: :regular}} <- File.stat(path) do
      {:ok, path}
    else
      _ -> {:error, :not_found}
    end
  end

  def read_json(path) do
    with {:ok, %File.Stat{type: :regular, size: size}} when size <= 1_048_576 <- File.stat(path),
         {:ok, bytes} <- File.read(path),
         {:ok, value} when is_map(value) <- Jason.decode(bytes) do
      value
    else
      _ -> nil
    end
  end

  def write_json(path, value) do
    tmp = path <> ".#{System.unique_integer([:positive])}.tmp"

    with :ok <- File.write(tmp, Jason.encode!(value), [:exclusive]),
         :ok <- File.chmod(tmp, 0o600),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      error ->
        File.rm(tmp)
        error
    end
  end

  defp submit_locked(staff, action, upload_path) do
    current = active()

    cond do
      current && (not terminal?(current) or not safe?(current)) ->
        {:error, :busy}

      File.exists?(Path.join(dir(), "active.json")) and is_nil(current) ->
        {:error, :busy}

      action == "import" and (not is_binary(upload_path) or not File.regular?(upload_path)) ->
        {:error, :invalid_archive}

      true ->
        create_job(staff, action, upload_path)
    end
  end

  defp create_job(staff, action, upload_path) do
    id = Ecto.UUID.generate()
    path = job_dir(id)
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    mode = if managed?(), do: "compose", else: "external"

    request = %{
      version: 1,
      id: id,
      action: action,
      mode: mode,
      requested_by: staff.id,
      created_at: now
    }

    status = %{
      id: id,
      action: action,
      phase: "queued",
      message: "Queued",
      safe_to_resume: true,
      updated_at: now
    }

    with :ok <- File.mkdir_p(path),
         :ok <- File.chmod(path, 0o700),
         :ok <- maybe_copy(upload_path, action, path),
         :ok <- write_json(Path.join(path, "request.json"), request),
         :ok <- write_json(Path.join(path, "status.json"), status),
         :ok <- write_json(Path.join(dir(), "active.json"), %{protocol: 1, id: id}) do
      {:ok, id}
    else
      error ->
        File.rm_rf(path)
        {:error, error}
    end
  end

  defp maybe_copy(_source, "export", _path), do: :ok

  defp maybe_copy(source, "import", path) do
    case File.stat(source) do
      {:ok, %File.Stat{size: size}} ->
        if size > 0 and size <= max_archive(),
          do: copy_private(source, Path.join(path, "archive.tar")),
          else: {:error, :invalid_archive}

      _ ->
        {:error, :invalid_archive}
    end
  end

  defp copy_private(source, target) do
    with :ok <- File.cp(source, target), do: File.chmod(target, 0o600)
  end

  defp with_lock(fun) do
    lock = Path.join(dir(), ".submit-lock")
    File.mkdir_p!(dir())

    case File.mkdir(lock) do
      :ok ->
        try do
          fun.()
        after
          File.rmdir(lock)
        end

      _ ->
        {:error, :busy}
    end
  end
end
