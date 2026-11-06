defmodule Delivest.InstanceBackupTest do
  use DelivestWeb.ConnCase, async: false

  import Delivest.Factory

  alias Delivest.InstanceBackup
  alias Delivest.InstanceBackup.Maintenance

  setup do
    dir = Path.join(System.tmp_dir!(), "instance-backup-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous = Application.get_env(:delivest, :instance_backup_dir)
    Application.put_env(:delivest, :instance_backup_dir, dir)

    on_exit(fn ->
      Application.put_env(:delivest, :instance_backup_dir, previous)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  test "rejects unauthorized and unavailable submissions without mutation", %{dir: dir} do
    staff = insert(:staff, role: insert(:role, permissions: ["franchise.update"]))
    assert {:error, :forbidden} = InstanceBackup.submit(staff, "export")
    assert File.ls!(dir) == []

    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    assert {:error, :agent_unavailable} = InstanceBackup.submit(admin, "export")
    assert File.ls!(dir) == []
  end

  test "submits a durable export and restricts download to its admin owner", %{
    dir: dir,
    conn: conn
  } do
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    other = insert(:staff, role: insert(:role, permissions: ["admin"]))

    :ok =
      InstanceBackup.write_json(Path.join(dir, "heartbeat.json"), %{
        protocol: 1,
        updated_at: DateTime.utc_now()
      })

    assert {:ok, id} = InstanceBackup.submit(admin, "export")

    assert %{"protocol" => 1, "id" => ^id} =
             InstanceBackup.read_json(Path.join(dir, "active.json"))

    assert %{"mode" => "external", "requested_by" => owner} = InstanceBackup.job(id).request
    assert owner == admin.id
    assert {:error, :busy} = InstanceBackup.submit(admin, "export")
    assert {:error, :not_found} = InstanceBackup.download(admin, id)

    path = Path.join(InstanceBackup.job_dir(id), "archive.tar")
    File.write!(path, "archive")

    :ok =
      InstanceBackup.write_json(Path.join(InstanceBackup.job_dir(id), "status.json"), %{
        id: id,
        action: "export",
        phase: "complete",
        safe_to_resume: true
      })

    assert {:ok, ^path} = InstanceBackup.download(admin, id)
    assert {:error, :not_found} = InstanceBackup.download(other, id)

    owner_conn = Plug.Test.init_test_session(conn, %{"staff_id" => admin.id})
    assert response(get(owner_conn, "/staff/franchise/instance-backup/#{id}"), 200) == "archive"

    other_conn = Plug.Test.init_test_session(conn, %{"staff_id" => other.id})
    assert response(get(other_conn, "/staff/franchise/instance-backup/#{id}"), 404)
  end

  test "import copies the archive into a private job directory", %{dir: dir} do
    admin = insert(:staff, role: insert(:role, permissions: ["admin"]))
    upload = Path.join(dir, "upload.tar")
    File.write!(upload, "tar payload")

    InstanceBackup.write_json(Path.join(dir, "heartbeat.json"), %{
      protocol: 1,
      updated_at: DateTime.utc_now()
    })

    assert {:ok, id} = InstanceBackup.submit(admin, "import", upload)
    archive = Path.join(InstanceBackup.job_dir(id), "archive.tar")
    assert File.read!(archive) == "tar payload"
    assert %{"id" => ^id, "action" => "import"} = InstanceBackup.job(id).request
    assert {:error, :not_found} = InstanceBackup.download(admin, id)
    assert Bitwise.band(File.stat!(InstanceBackup.job_dir(id)).mode, 0o777) == 0o700
    assert Bitwise.band(File.stat!(archive).mode, 0o777) == 0o600
  end

  test "unsafe status holds boot", %{dir: dir} do
    id = Ecto.UUID.generate()
    job_dir = Path.join([dir, "jobs", id])
    File.mkdir_p!(job_dir)
    InstanceBackup.write_json(Path.join(dir, "active.json"), %{protocol: 1, id: id})
    InstanceBackup.write_json(Path.join(job_dir, "request.json"), %{id: id, mode: "external"})

    InstanceBackup.write_json(Path.join(job_dir, "status.json"), %{
      phase: "interrupted",
      safe_to_resume: false
    })

    assert Maintenance.hold_boot?(dir)

    InstanceBackup.write_json(Path.join(job_dir, "status.json"), %{
      phase: "complete",
      safe_to_resume: true
    })

    refute Maintenance.hold_boot?(dir)
  end

  test "queued external jobs and malformed active status hold boot", %{dir: dir} do
    id = Ecto.UUID.generate()
    job_dir = Path.join([dir, "jobs", id])
    File.mkdir_p!(job_dir)
    InstanceBackup.write_json(Path.join(dir, "active.json"), %{protocol: 1, id: id})
    InstanceBackup.write_json(Path.join(job_dir, "request.json"), %{id: id, mode: "external"})

    InstanceBackup.write_json(Path.join(job_dir, "status.json"), %{
      id: id,
      phase: "queued",
      safe_to_resume: true
    })

    assert Maintenance.hold_boot?(dir)
    File.write!(Path.join(job_dir, "status.json"), "broken")
    assert Maintenance.hold_boot?(dir)
  end

  test "held boot restores a missing marker while siblings are absent", %{dir: dir} do
    id = Ecto.UUID.generate()
    job_dir = Path.join([dir, "jobs", id])
    File.mkdir_p!(job_dir)
    InstanceBackup.write_json(Path.join(dir, "active.json"), %{protocol: 1, id: id})

    InstanceBackup.write_json(Path.join(job_dir, "request.json"), %{
      id: id,
      mode: "external",
      action: "import"
    })

    InstanceBackup.write_json(Path.join(job_dir, "status.json"), %{
      id: id,
      phase: "queued",
      safe_to_resume: true
    })

    supervisor =
      start_supervised!(%{
        id: :held_backup_test_supervisor,
        start: {Supervisor, :start_link, [[], [strategy: :one_for_one]]}
      })

    maintenance =
      start_supervised!(
        {Maintenance,
         supervisor: supervisor,
         children: [],
         dir: dir,
         held: true,
         name: :held_backup_test_maintenance}
      )

    send(maintenance, :poll)
    _ = :sys.get_state(maintenance)
    assert %{"id" => ^id} = InstanceBackup.read_json(Path.join(job_dir, "quiesced.json"))
  end

  test "manager restart finishes a partial resume after completed job", %{dir: dir} do
    owner = self()

    children =
      for child_id <- [:repo, :endpoint] do
        Supervisor.child_spec(
          {Agent,
           fn ->
             send(owner, {:started, child_id})
             child_id
           end},
          id: child_id
        )
      end

    supervisor =
      start_supervised!(%{
        id: :partial_backup_test_supervisor,
        start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
      })

    assert_receive {:started, :repo}
    assert_receive {:started, :endpoint}
    :ok = Supervisor.terminate_child(supervisor, :endpoint)

    id = Ecto.UUID.generate()
    job_dir = Path.join([dir, "jobs", id])
    File.mkdir_p!(job_dir)
    InstanceBackup.write_json(Path.join(dir, "active.json"), %{protocol: 1, id: id})

    InstanceBackup.write_json(Path.join(job_dir, "request.json"), %{
      id: id,
      mode: "external",
      action: "import"
    })

    InstanceBackup.write_json(Path.join(job_dir, "status.json"), %{
      id: id,
      phase: "complete",
      safe_to_resume: true
    })

    InstanceBackup.write_json(Path.join(job_dir, "quiesced.json"), %{id: id})

    maintenance =
      start_supervised!(
        {Maintenance,
         supervisor: supervisor,
         children: children,
         dir: dir,
         name: :partial_backup_test_maintenance}
      )

    send(maintenance, :poll)
    _ = :sys.get_state(maintenance)
    assert_receive {:started, :endpoint}
    assert Enum.all?(Supervisor.which_children(supervisor), fn {_, pid, _, _} -> is_pid(pid) end)
  end

  test "external maintenance stops siblings before marker and restarts in startup order", %{
    dir: dir
  } do
    owner = self()

    children =
      for id <- [:repo, :endpoint] do
        Supervisor.child_spec(
          {Agent,
           fn ->
             send(owner, {:started, id})
             id
           end},
          id: id
        )
      end

    supervisor =
      start_supervised!(%{
        id: :backup_test_supervisor,
        start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
      })

    assert_receive {:started, :repo}
    assert_receive {:started, :endpoint}

    id = Ecto.UUID.generate()
    job_dir = Path.join([dir, "jobs", id])
    File.mkdir_p!(job_dir)
    InstanceBackup.write_json(Path.join(dir, "active.json"), %{protocol: 1, id: id})

    InstanceBackup.write_json(Path.join(job_dir, "request.json"), %{
      id: id,
      mode: "external",
      action: "import"
    })

    InstanceBackup.write_json(Path.join(job_dir, "status.json"), %{
      id: id,
      phase: "waiting",
      safe_to_resume: false
    })

    maintenance =
      start_supervised!(
        {Maintenance,
         supervisor: supervisor, children: children, dir: dir, name: :backup_test_maintenance}
      )

    send(maintenance, :poll)
    _ = :sys.get_state(maintenance)
    assert %{"id" => ^id} = InstanceBackup.read_json(Path.join(job_dir, "quiesced.json"))

    assert Enum.all?(Supervisor.which_children(supervisor), fn {_, pid, _, _} ->
             pid == :undefined
           end)

    InstanceBackup.write_json(Path.join(job_dir, "status.json"), %{
      id: id,
      phase: "complete",
      safe_to_resume: true
    })

    send(maintenance, :poll)
    _ = :sys.get_state(maintenance)
    assert_receive {:started, :repo}
    assert_receive {:started, :endpoint}
  end
end
