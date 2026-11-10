defmodule Delivest.FeaturesTest do
  use Delivest.DataCase, async: false
  import Delivest.Factory

  alias Delivest.{Features, Repo}
  alias Delivest.Background.Schedule

  test "default off, unknown feature and branch fail closed" do
    branch = insert(:branch)
    refute Features.enabled?("segments", :franchise)
    refute Features.enabled?("segments", {:branch, branch.id})
    refute Features.enabled?("unknown", :franchise)

    assert {:error, :invalid_configuration} =
             Features.configure("segments", {:branch, Ecto.UUID.generate()}, true, actor: "host")

    assert Repo.aggregate(Schedule, :count) == 0
  end

  test "parent and branch gates, repeat configuration, and stale publish fence" do
    branch = insert(:branch)
    assert {:ok, parent} = Features.configure("segments", :franchise, true, actor: "host")
    assert {:ok, ^parent} = Features.configure("segments", :franchise, true, actor: "host")
    assert Repo.aggregate(Schedule, :count) == 1
    refute Features.enabled?("segments", {:branch, branch.id})
    assert {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "host")
    assert {:ok, token} = Features.snapshot("segments", {:branch, branch.id})

    assert {:ok, :published} =
             Features.with_enabled("segments", {:branch, branch.id}, token, fn -> :published end)

    assert {:ok, _} = Features.configure("segments", {:branch, branch.id}, false, actor: "host")
    assert {:ok, _} = Features.configure("segments", {:branch, branch.id}, true, actor: "host")

    assert {:error, :disabled} =
             Features.with_enabled("segments", {:branch, branch.id}, token, fn ->
               flunk("stale branch result")
             end)

    assert {:ok, _} = Features.configure("segments", :franchise, false, actor: "host")
    refute Features.enabled?("segments", {:branch, branch.id})
    assert Repo.aggregate(Schedule, :count) == 0
    assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "host")
    assert Features.enabled?("segments", {:branch, branch.id})

    assert {:error, :disabled} =
             Features.with_enabled("segments", {:branch, branch.id}, token, fn ->
               flunk("stale write")
             end)
  end

  test "union publication checks both immutable source and notification epochs" do
    branch = insert(:branch)
    assert {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "host")

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "host")

    assert {:ok, source} = Features.snapshot("marketing_policies", {:branch, branch.id})
    assert {:ok, notice} = Features.snapshot("notifications", {:branch, branch.id})

    locks = [
      {"marketing_policies", {:branch, branch.id}, source},
      {"notifications", {:branch, branch.id}, notice}
    ]

    assert {:ok, :ok} = Features.with_enabled_many(locks, fn -> :ok end)

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, branch.id}, false, actor: "host")

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "host")

    assert {:error, :disabled} =
             Features.with_enabled_many(locks, fn -> flunk("stale source") end)
  end

  test "publication and host revocation serialize on independent database connections" do
    unboxed(fn ->
      assert {:ok, _} = Features.configure("segments", :franchise, true, actor: "race")
    end)

    token =
      unboxed(fn ->
        {:ok, token} = Features.snapshot("segments", :franchise)
        token
      end)

    parent = self()

    publisher =
      Task.async(fn ->
        unboxed(fn ->
          Features.with_enabled("segments", :franchise, token, fn ->
            send(parent, {:publication_locked, self()})

            receive do
              :release_publication -> :published
            after
              5_000 -> raise "publication test barrier timed out"
            end
          end)
        end)
      end)

    assert_receive {:publication_locked, publishing_pid}

    revoker =
      Task.async(fn ->
        unboxed(fn ->
          result = Features.configure("segments", :franchise, false, actor: "race")
          send(parent, :revocation_done)
          result
        end)
      end)

    refute_receive :revocation_done, 100
    send(publishing_pid, :release_publication)
    assert {:ok, :published} = Task.await(publisher, 5_000)
    assert {:ok, _} = Task.await(revoker, 5_000)
    assert_receive :revocation_done

    assert {:error, :disabled} =
             unboxed(fn ->
               Features.with_enabled("segments", :franchise, token, fn ->
                 flunk("revoked write")
               end)
             end)
  end

  test "marketing enables dependency closure and dependent disable needs a current preview" do
    branch = insert(:branch)
    assert {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "host")
    assert Features.enabled?("segments", :franchise)
    assert Features.enabled?("notifications", :franchise)

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "host")

    assert Features.enabled?("segments", {:branch, branch.id})
    assert Features.enabled?("notifications", {:branch, branch.id})

    assert Features.enabled_branches("marketing_policies", [branch.id, Ecto.UUID.generate()]) ==
             MapSet.new([branch.id])

    assert {:ok, token} = Features.snapshot("marketing_policies", {:branch, branch.id})

    assert {:ok, preview} = Features.disable_preview("segments", {:branch, branch.id})
    assert preview.features == ["marketing_policies"]

    assert {:error, {:dependent_features, ^preview}} =
             Features.configure("segments", {:branch, branch.id}, false, actor: "host")

    # A dependent changed since review, even if the same dependent is still enabled.
    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, branch.id}, false, actor: "host")

    assert {:ok, _} =
             Features.configure("marketing_policies", {:branch, branch.id}, true, actor: "host")

    assert {:error, {:dependent_features, current}} =
             Features.configure("segments", {:branch, branch.id}, false,
               actor: "host",
               confirm_dependents: preview
             )

    assert current.features == preview.features
    refute current.fingerprint == preview.fingerprint

    assert {:ok, _} =
             Features.configure("segments", {:branch, branch.id}, false,
               actor: "host",
               confirm_dependents: current
             )

    refute Features.enabled?("marketing_policies", {:branch, branch.id})

    assert {:error, :disabled} =
             Features.with_enabled("marketing_policies", {:branch, branch.id}, token, fn ->
               flunk("stale dependency publish")
             end)
  end

  defp unboxed(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)
end
