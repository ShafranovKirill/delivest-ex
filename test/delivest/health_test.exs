defmodule Delivest.HealthTest do
  use ExUnit.Case, async: true

  alias Delivest.Health

  test "reports shipped migrations that the database has not applied" do
    assert Health.pending_migrations([1, 2, 3], [1, 3]) == [2]
    assert Health.pending_migrations([1, 2], [1, 2, 3]) == []
  end
end
