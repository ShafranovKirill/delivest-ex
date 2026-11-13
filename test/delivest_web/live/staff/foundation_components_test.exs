defmodule DelivestWeb.Staff.FoundationComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias DelivestWeb.Staff.FoundationComponents

  test "event controls accept a LiveComponent target" do
    filter =
      render_component(&FoundationComponents.filter_bar/1,
        id: "target-filter",
        reset_path: "/staff/foundation-gallery",
        target: "#owner"
      )

    assert filter =~ ~s(phx-target="#owner")

    dialog =
      render_component(&FoundationComponents.confirm_dialog/1,
        id: "target-dialog",
        title: "Confirm",
        message: "Continue?",
        action: "Continue",
        target: "#owner"
      )

    assert dialog =~ ~s(data-target="component")
    assert dialog =~ ~s(phx-target="#owner")
  end

  test "money, phone and address fields keep domain presentation while using form fields" do
    types = %{price: :integer, phone: :string, address: :string}

    changeset =
      {%{}, types}
      |> Ecto.Changeset.cast(
        %{"price" => 12_345, "phone" => "+79991234567", "address" => "Main Street"},
        Map.keys(types)
      )

    form = Phoenix.Component.to_form(changeset, as: :fixture)

    money =
      render_component(&FoundationComponents.domain_field/1,
        field: form[:price],
        label: "Price",
        kind: :money
      )
      |> LazyHTML.from_fragment()

    assert money
           |> LazyHTML.query("input[inputmode='decimal'][value='123,45']")
           |> LazyHTML.to_tree()
           |> Enum.any?()

    phone =
      render_component(&FoundationComponents.domain_field/1,
        field: form[:phone],
        label: "Phone",
        kind: :phone
      )
      |> LazyHTML.from_fragment()

    assert phone |> LazyHTML.query("input[type='tel']") |> LazyHTML.to_tree() |> Enum.any?()

    address =
      render_component(&FoundationComponents.domain_field/1,
        field: form[:address],
        label: "Address",
        kind: :address
      )
      |> LazyHTML.from_fragment()

    assert address
           |> LazyHTML.query("input[autocomplete='street-address']")
           |> LazyHTML.to_tree()
           |> Enum.any?()
  end

  test "branch address adapter delegates established location fields without external calls" do
    changeset =
      DelivestWeb.Staff.BranchLive.BranchForm.changeset(
        %DelivestWeb.Staff.BranchLive.BranchForm{},
        %{"city" => "Tyumen", "address" => "Main Street"}
      )

    form = Phoenix.Component.to_form(changeset, as: :branch_form)

    document =
      render_component(&FoundationComponents.address_field/1, form: form, map: false)
      |> LazyHTML.from_fragment()

    assert document
           |> LazyHTML.query("input[name='branch_form[city]']")
           |> LazyHTML.to_tree()
           |> Enum.any?()

    assert document
           |> LazyHTML.query("input[name='branch_form[address]']")
           |> LazyHTML.to_tree()
           |> Enum.any?()
  end

  test "schedule editor adapter accepts branch working hours" do
    html =
      render_component(&FoundationComponents.schedule_editor/1,
        id: "fixture-hours",
        working_hours: %{"monday" => %{"open" => "09:00", "close" => "18:00", "enabled" => true}}
      )

    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.query(
             "input[name='branch_form[working_hours][monday][open]'][value='09:00']"
           )
           |> LazyHTML.to_tree()
           |> Enum.any?()
  end
end
