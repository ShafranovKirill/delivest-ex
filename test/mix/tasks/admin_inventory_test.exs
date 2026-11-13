defmodule Mix.Tasks.Admin.InventoryTest do
  use ExUnit.Case, async: true

  test "snapshot covers each source-backed staff element with a stable ID" do
    inventory = Mix.Tasks.Admin.Inventory.snapshot()

    for register <-
          ~w(screens fields actions features_integrations background schema_census service_routes) do
      entries = Map.fetch!(inventory, register)
      ids = Enum.map(entries, & &1["id"])

      assert entries != [], "empty #{register} register"
      assert length(ids) == length(Enum.uniq(ids)), "duplicate IDs in #{register}"
      assert Enum.all?(entries, &(is_binary(&1["source"]) and &1["source"] != ""))
    end

    assert Enum.all?(
             inventory["screens"],
             &(&1["page_type"] in ~w(work_queue list entity settings))
           )

    assert Enum.all?(
             inventory["fields"],
             &(&1["owner"] && &1["canonical_form"] && &1["target_section"])
           )
  end

  test "known nested, guarded and scheduled sources retain their ownership evidence" do
    inventory = Mix.Tasks.Admin.Inventory.snapshot()

    assert Enum.any?(inventory["fields"], fn field ->
             field["id"] ==
               "form:lib/delivest_web/live/staff/integration_live/frontpad.ex:frontpad:api_key" and
               field["owner"] == "lib/delivest/integrations/frontpad/settings.ex"
           end)

    assert Enum.any?(inventory["screens"], fn screen ->
             screen["route"] == "LIVE /staff/b/:branch_slug/kitchen" and
               Enum.any?(screen["rights"]["session_hooks"], &String.contains?(&1, "orders.cook"))
           end)

    assert Enum.any?(inventory["background"], fn job ->
             job["id"] == "worker:Delivest.Oms.Workers.CartCleanupWorker" and
               String.contains?(job["frequency"], "daily") and
               Enum.any?(
                 job["producer_scheduler"],
                 &String.contains?(&1, "maintenance/registry.ex")
               )
           end)

    assert Enum.any?(inventory["background"], fn job ->
             job["id"] == "poller:Delivest.Integrations.Crm.StopPoller" and
               String.contains?(job["external_call"], "StopSync.clear_frontpad") and
               String.contains?(job["external_call"], "StopSync.sync")
           end)

    assert Enum.any?(inventory["fields"], fn field ->
             field["name_template"] == "modifiers[<dynamic>][]" and
               String.contains?(field["source"], "order_live/order_form.ex")
           end)

    assert Enum.any?(inventory["actions"], fn action ->
             String.contains?(action["id"], "cancel_order_modal.ex") and
               action["event"] == "confirm_cancel" and
               Enum.any?(
                 action["handler_clauses"] || [],
                 &String.contains?(&1, "order_live/orders.ex")
               )
           end)
  end

  test "branch persisted owners, transient queries and page classification are assigned" do
    inventory = Mix.Tasks.Admin.Inventory.snapshot()
    fields = inventory["fields"]
    branch_form = "lib/delivest_web/live/staff/branch_live/branch_form_component.ex"

    assert Enum.any?(fields, fn field ->
             field["current_forms"] == [branch_form] and field["field"] == "name" and
               field["owner"] == "lib/delivest/identity/branch.ex" and
               String.contains?(field["required"], "validate_required") and
               "validate_length" in field["validation"]
           end)

    assert Enum.any?(fields, fn field ->
             field["current_forms"] == [branch_form] and field["field"] == "manual_rating" and
               field["owner"] == "lib/delivest/identity/branch/branch_info.ex" and
               "validate_number" in field["validation"]
           end)

    assert Enum.any?(fields, fn field ->
             field["current_forms"] == [branch_form] and field["field"] == "delivery" and
               field["owner"] ==
                 "lib/delivest/identity/branch/fulfillment_settings.ex" and
               field["default"] == "true"
           end)

    assert Enum.any?(fields, fn field ->
             field["current_forms"] == [branch_form] and field["field"] == "lead_minutes" and
               field["owner"] == "lib/delivest/identity/branch/kitchen_settings.ex" and
               field["default"] == "90"
           end)

    assert Enum.any?(fields, fn field ->
             field["field"] == "q" and
               String.contains?(field["source"], "integration_live/frontpad.ex") and
               String.starts_with?(field["owner"], "transient search/query operation") and
               field["schema_field"] == nil and
               String.starts_with?(field["default"], "not applicable")
           end)

    assert Enum.any?(inventory["screens"], fn screen ->
             screen["route"] == "LIVE /staff/b/:branch_slug/delivery" and
               screen["page_type"] == "settings" and screen["variant"] == "hub"
           end)

    assert Enum.any?(inventory["screens"], fn screen ->
             screen["route"] == "LIVE /staff/branches/new" and
               screen["page_type"] == "settings"
           end)
  end

  test "action identities survive comments and source line shifts" do
    task = Mix.Tasks.Admin.Inventory
    code = ~S|def handle_event("save", params, socket), do: {:noreply, socket}|
    with_comment = "# a comment before the clause\n\n" <> code

    assert task.stable_action_identity("staff/example.ex", "save", Code.string_to_quoted!(code)) ==
             task.stable_action_identity(
               "staff/example.ex",
               "save",
               Code.string_to_quoted!(with_comment)
             )

    opening = ~s(<button id="save-branch" phx-click="save">)
    wrapped = ~s(<button\n  id="save-branch" phx-click="save">)

    assert task.stable_control_identity("staff/example.ex", "save", opening, "Save") ==
             task.stable_control_identity("staff/example.ex", "save", wrapped, "Save")
  end
end
