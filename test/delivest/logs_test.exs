defmodule Delivest.LogsTest do
  use Delivest.DataCase, async: true

  alias Delivest.Logs
  alias Delivest.Logs.{Entry, Formatter}

  defp insert_entry(level, message, at \\ DateTime.utc_now()) do
    Repo.insert!(%Entry{level: level, message: message, inserted_at: at})
  end

  test "scopes split errors, hints and raw logs" do
    insert_entry("error", "boom")
    insert_entry("warning", "careful")
    insert_entry("info", "hello")

    assert {:ok, {[%{message: "boom"}], _}} = Logs.list_entries(:errors)
    assert {:ok, {[%{message: "careful"}], _}} = Logs.list_entries(:hints)
    assert {:ok, {raw, _}} = Logs.list_entries(:raw)
    assert length(raw) == 3
  end

  test "prune removes entries older than the retention window" do
    insert_entry("info", "old", DateTime.add(DateTime.utc_now(), -20, :day))
    insert_entry("info", "fresh")

    assert {1, _} = Logs.prune(14)
    assert [%{message: "fresh"}] = Repo.all(Entry)
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
