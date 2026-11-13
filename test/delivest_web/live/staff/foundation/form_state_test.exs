defmodule DelivestWeb.Staff.Foundation.FormStateTest do
  use ExUnit.Case, async: true
  alias DelivestWeb.Staff.Foundation.FormState

  test "save is single flight and dirty clears only on confirmed persistence" do
    state = FormState.new(%{"name" => "before"}) |> FormState.edit(%{"name" => "after"})
    assert FormState.dirty?(state)
    assert {:ok, pending} = FormState.begin_save(state)
    assert {:error, ^pending} = FormState.begin_save(pending)
    assert FormState.dirty?(FormState.failed(pending, %{"name" => "server error"}))
    assert %{status: :success} = saved = FormState.saved(pending, %{"name" => "after"})
    refute FormState.dirty?(saved)
  end

  test "cancel requires confirmation and stay preserves draft" do
    state = FormState.new(%{"name" => "before"}) |> FormState.edit(%{"name" => "after"})
    assert FormState.request_cancel(state).confirmation == :cancel
    assert FormState.stay(FormState.request_cancel(state)).draft == state.draft
    refute FormState.dirty?(state |> FormState.request_cancel() |> FormState.discard())
  end

  test "pending and read-only never accept edits or discard" do
    state = FormState.new(%{"name" => "before"}) |> FormState.edit(%{"name" => "after"})
    {:ok, pending} = FormState.begin_save(state)
    assert FormState.discard(pending) == pending
    assert FormState.request_cancel(pending) == pending
    read_only = FormState.read_only(state)
    assert FormState.edit(read_only, %{"name" => "other"}) == read_only
    assert {:error, ^read_only} = FormState.begin_save(read_only)
  end

  test "conflict and server failure retain the draft for retry" do
    state = FormState.new(%{"name" => "saved"}) |> FormState.edit(%{"name" => "draft"})
    conflict = FormState.conflict(state)
    assert conflict.draft == %{"name" => "draft"}
    assert {:error, ^conflict} = FormState.begin_save(conflict)
    assert FormState.edit(conflict, %{"name" => "other"}) == conflict
    recovered = FormState.resolve_conflict(conflict, %{"name" => "latest"}, :retry)
    assert recovered.saved == %{"name" => "latest"}
    assert recovered.draft == state.draft
    assert {:ok, %{status: :pending}} = FormState.begin_save(recovered)

    reloaded =
      conflict |> FormState.request_reload() |> FormState.reload_latest(%{"name" => "latest"})

    assert reloaded.draft == %{"name" => "latest"}
    failed = FormState.failed(state, %{"name" => "Server unavailable"})
    assert failed.errors["name"] == "Server unavailable"
    assert failed.draft == state.draft
    assert {:ok, %{status: :pending}} = FormState.begin_save(failed)
  end

  test "read-only access survives error and cancel transitions" do
    state =
      FormState.new(%{"name" => "before"})
      |> FormState.edit(%{"name" => "draft"})
      |> FormState.read_only()

    for transformed <- [
          FormState.failed(state, %{"name" => "error"}),
          FormState.conflict(state),
          state |> FormState.request_cancel() |> FormState.discard()
        ] do
      refute transformed.writable?
      assert FormState.edit(transformed, %{"name" => "other"}) == transformed
      assert {:error, ^transformed} = FormState.begin_save(transformed)
    end
  end

  test "leave confirmation never changes the draft before explicit navigation" do
    state = FormState.new(%{"name" => "saved"}) |> FormState.edit(%{"name" => "draft"})
    leaving = FormState.request_leave(state)
    assert leaving.confirmation == :leave
    assert FormState.stay(leaving).draft == state.draft
    assert FormState.discard(leaving).draft == state.saved
  end
end
