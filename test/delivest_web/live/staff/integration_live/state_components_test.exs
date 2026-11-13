defmodule DelivestWeb.Staff.IntegrationLive.StateComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias DelivestWeb.Staff.IntegrationLive.StateComponents

  test "unsent, uncertain and accepted CRM obligations have separate counts" do
    state = %{
      scope: {:branch, "North"},
      main: :finishing,
      credentials: %{state: :complete, text: "Filled in"},
      connection: %{state: :unchecked, text: "Connection not checked", checked_at: nil},
      activity: nil,
      usage: [],
      provider: :frontpad,
      capabilities: [],
      warnings: [],
      obligations: %{unsent: 1, uncertain: 2, accepted: 3}
    }

    document =
      render_component(&StateComponents.summary/1, id: "crm-state", state: state)
      |> LazyHTML.from_fragment()

    assert document |> LazyHTML.query("#crm-state-unsent") |> LazyHTML.text() =~ "1"
    assert document |> LazyHTML.query("#crm-state-uncertain") |> LazyHTML.text() =~ "2"
    assert document |> LazyHTML.query("#crm-state-accepted") |> LazyHTML.text() =~ "3"
  end
end
