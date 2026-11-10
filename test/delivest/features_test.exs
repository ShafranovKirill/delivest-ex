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
end
