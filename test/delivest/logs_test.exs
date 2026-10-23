defmodule Delivest.LogsTest do
  use Delivest.DataCase, async: true

  alias Delivest.Logs
  alias Delivest.Logs.{Entry, Formatter}

  defp insert_entry(level, message, at \\ DateTime.utc_now(), metadata \\ %{}) do
    Repo.insert!(%Entry{level: level, message: message, inserted_at: at, metadata: metadata})
  end

  test "scopes split errors and raw logs" do
    insert_entry("error", "boom")
    insert_entry("warning", "order.created failed")
    insert_entry("info", "hello")

    assert {:ok, {[%{message: "boom"}], _}} = Logs.list_entries(:errors)
    assert {:ok, {raw, _}} = Logs.list_entries(:raw)
    assert length(raw) == 3
  end

  test "prune keeps errors longer than raw logs" do
    days_ago = &DateTime.add(DateTime.utc_now(), -&1, :day)
    insert_entry("info", "old info", days_ago.(10))
    insert_entry("info", "fresh info")
    insert_entry("error", "recent error", days_ago.(10))
    insert_entry("error", "old error", days_ago.(40))

    assert Logs.prune(7, 30) == 2

    assert ["fresh info", "recent error"] =
             Entry |> Repo.all() |> Enum.map(& &1.message) |> Enum.sort()
  end

  describe "formatter" do
    test "formats string, format and report messages" do
      meta = %{time: 0, mfa: {Delivest.Logs, :prune, 1}, line: 10, request_id: "req"}

      assert %{message: "plain", source: "Delivest.Logs.prune/1:10", level: "info"} =
               Formatter.to_entry(%{level: :info, msg: {:string, ["pl", "ain"]}, meta: meta})

      assert %{message: "a 1"} =
               Formatter.to_entry(%{level: :info, msg: {~c"a ~p", [1]}, meta: meta})

      assert %{message: "%{a: 1}", metadata: %{request_id: "req"}} =
               Formatter.to_entry(%{level: :info, msg: {:report, %{a: 1}}, meta: meta})
    end
  end
end
