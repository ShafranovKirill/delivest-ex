defmodule Delivest.FeaturesSnapshotsTest do
  use Delivest.DataCase, async: false
  import Delivest.Factory

  alias Delivest.Features

  @features ~w(yandex_browser yandex_conversions yandex_ecommerce unknown)

  test "batch snapshots match single snapshots through gates, dependencies and generations" do
    branch = insert(:branch, is_active: true)
    scope = {:branch, branch.id}
    assert_parity(scope)

    for feature <- ~w(yandex_browser yandex_conversions yandex_ecommerce) do
      assert {:ok, _} =
               Features.configure(feature, :franchise, true,
                 actor: "test",
                 selected_integration_branches: true
               )

      assert {:ok, _} = Features.configure(feature, scope, true, actor: "test")
      assert_parity(scope)
    end

    before = Features.snapshots(@features, scope)
    assert {:ok, _} = Features.configure("yandex_browser", scope, false, actor: "test")
    assert_parity(scope)
    assert before["yandex_browser"] != Features.snapshots(@features, scope)["yandex_browser"]
    assert {:ok, _} = Features.configure("yandex_browser", scope, true, actor: "test")
    assert_parity(scope)
    assert before["yandex_browser"] != Features.snapshots(@features, scope)["yandex_browser"]
    assert_parity(:franchise)

    parent =
      Repo.get_by!(Delivest.Features.Gate,
        feature: "yandex_ads",
        scope_key: "branch:" <> branch.id
      )

    Repo.update!(Ecto.Changeset.change(parent, enabled: false, generation: parent.generation + 1))
    assert_parity(scope)

    assert Enum.all?(~w(yandex_browser yandex_conversions yandex_ecommerce), fn feature ->
             Features.snapshots(@features, scope)[feature] == {:error, :disabled}
           end)
  end

  test "invalid, missing and deleted scopes fail exactly like single snapshots" do
    branch = insert(:branch, is_active: true)

    for scope <- [{:branch, "bad"}, {:branch, Ecto.UUID.generate()}, :invalid] do
      assert_parity(scope)
    end

    branch
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update!()

    assert_parity({:branch, branch.id})
  end

  test "batch uses one branch check and one union gate query" do
    branch = insert(:branch, is_active: true)
    scope = {:branch, branch.id}
    assert count_queries(fn -> Features.snapshots(@features, scope) end) == 2
    assert count_queries(fn -> Enum.map(@features, &Features.snapshot(&1, scope)) end) == 6
    assert count_queries(fn -> Features.snapshots(@features, :franchise) end) == 1
  end

  defp assert_parity(scope) do
    many = Features.snapshots(@features, scope)
    for feature <- @features, do: assert(many[feature] == Features.snapshot(feature, scope))
  end

  defp count_queries(fun) do
    handler = "features-snapshots-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:delivest, :repo, :query],
      fn _, _, metadata, owner ->
        if self() == owner and not String.contains?(metadata[:query] || "", "schema_migrations"),
          do: send(owner, :sql_query)
      end,
      self()
    )

    try do
      fun.()
      collect_queries(0)
    after
      :telemetry.detach(handler)
    end
  end

  defp collect_queries(count) do
    receive do
      :sql_query -> collect_queries(count + 1)
    after
      0 -> count
    end
  end
end
