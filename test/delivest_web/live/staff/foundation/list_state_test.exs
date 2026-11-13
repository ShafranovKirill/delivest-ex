defmodule DelivestWeb.Staff.Foundation.ListStateTest do
  use ExUnit.Case, async: true
  alias DelivestWeb.Staff.Foundation.ListState

  test "URL parsing is bounded and preserves server query state" do
    params = %{
      "q" => "  pizza  ",
      "sort" => "price",
      "direction" => "desc",
      "page" => "3",
      "per_page" => "50",
      "status" => "Active",
      "ignored" => "x"
    }

    state =
      ListState.from_params(params,
        sorts: ["name", "price"],
        filters: ["status"],
        scope: "b1"
      )

    assert ListState.query(state) == %{
             q: "pizza",
             filters: %{"status" => "Active"},
             sort: "price",
             direction: "desc",
             page: 3,
             per_page: 50,
             scope: "b1"
           }

    assert ListState.params(state)["page"] == 3
  end

  test "malformed inputs cannot enter query and page size is allowlisted" do
    params = %{
      "q" => ["x"],
      "status" => %{"x" => "y"},
      "page" => "-2",
      "per_page" => "999",
      "sort" => "evil"
    }

    state = ListState.from_params(params, sorts: ["name"], filters: ["status"])

    assert ListState.query(state) == %{
             q: "",
             filters: %{},
             sort: "name",
             direction: "asc",
             page: 1,
             per_page: 25,
             scope: "all"
           }
  end

  test "filter and scope changes reset page and page-only selection" do
    state =
      ListState.from_params(%{"page" => "4"}) |> ListState.select(["a", "hidden"], ["a", "b"])

    assert ListState.selected_count(state) == 1
    assert ListState.change(state, %{query: "new"}).page == 1
    assert ListState.selected_count(ListState.change(state, %{scope: "b2"})) == 0
    assert ListState.selected_count(ListState.change(state, %{page: 5})) == 0
  end

  test "empty data and no results are distinct" do
    assert ListState.empty_kind(0, ListState.from_params(%{})) == :empty
    assert ListState.empty_kind(0, ListState.from_params(%{"q" => "x"})) == :no_results
  end
end
