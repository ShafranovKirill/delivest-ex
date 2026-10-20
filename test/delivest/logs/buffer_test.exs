defmodule Delivest.Logs.BufferTest do
  use Delivest.DataCase, async: false

  require Logger

  alias Delivest.Logs.{Buffer, Entry}

  test "application logs are written to the database" do
    pid = start_supervised!({Buffer, level: :warning})
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)

    Logger.error("buffer test failure")
    Buffer.flush()

    assert [%Entry{level: "error", message: "buffer test failure"}] = Repo.all(Entry)
  end
end
