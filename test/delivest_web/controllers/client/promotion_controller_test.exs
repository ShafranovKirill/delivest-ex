defmodule DelivestWeb.Client.PromotionControllerTest do
  use DelivestWeb.ConnCase, async: true

  import Delivest.Factory

  test "lists only running automatic promotions of the branch", %{conn: conn} do
    branch = insert(:branch, is_active: true)
    other = insert(:branch, is_active: true)
    past = DateTime.add(DateTime.utc_now(:second), -1, :day)
    future = DateTime.add(DateTime.utc_now(:second), 1, :day)

    insert_promotion(branch.id, name: "Running", description: "Every day", ends_at: future)
    insert_promotion(branch.id, name: "Disabled", enabled: false)
    insert_promotion(branch.id, name: "Finished", ends_at: past)
    insert_promotion(branch.id, name: "Upcoming", starts_at: future)
    insert_promotion(branch.id, name: "Deleted", deleted_at: past)
    insert_promotion(branch.id, name: "Coded", kind: :public_code)
    insert_promotion(other.id, name: "Elsewhere")

    assert [%{"name" => "Running", "description" => "Every day", "ends_at" => ends_at}] =
             conn
             |> get(~p"/client/#{branch.id}/promotions")
             |> json_response(200)
             |> Map.fetch!("data")

    assert ends_at == DateTime.to_iso8601(future)
  end

  test "an unknown branch has no promotions", %{conn: conn} do
    assert %{"data" => []} = conn |> get(~p"/client/nope/promotions") |> json_response(200)
  end
end
