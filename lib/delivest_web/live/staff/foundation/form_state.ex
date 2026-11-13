defmodule DelivestWeb.Staff.Foundation.FormState do
  @moduledoc "Small form transition contract; persistence and validation remain with the caller."

  defstruct saved: %{},
            draft: %{},
            status: :saved,
            errors: %{},
            confirmation: nil,
            writable?: true

  def new(saved), do: %__MODULE__{saved: saved, draft: saved}
  def dirty?(%__MODULE__{saved: saved, draft: draft}), do: saved != draft

  def edit(%__MODULE__{status: :pending} = state, _draft), do: state
  def edit(%__MODULE__{writable?: false} = state, _draft), do: state
  def edit(%__MODULE__{status: :conflict} = state, _draft), do: state

  def edit(%__MODULE__{} = state, draft),
    do: %{state | draft: draft, status: :editing, errors: %{}}

  def begin_save(%__MODULE__{} = state) do
    if dirty?(state) and state.writable? and state.status not in [:pending, :conflict],
      do: {:ok, %{state | status: :pending, confirmation: nil}},
      else: {:error, state}
  end

  def saved(%__MODULE__{status: :pending} = state, persisted),
    do: %{state | saved: persisted, draft: persisted, status: :success, errors: %{}}

  def failed(%__MODULE__{} = state, errors),
    do: %{state | status: :error, errors: errors}

  def conflict(%__MODULE__{} = state), do: %{state | status: :conflict}
  def read_only(%__MODULE__{} = state), do: %{state | status: :read_only, writable?: false}

  def resolve_conflict(%__MODULE__{status: :conflict, writable?: true} = state, latest, :retry),
    do: %{state | saved: latest, status: :editing, errors: %{}, confirmation: nil}

  def resolve_conflict(%__MODULE__{} = state, _latest, _mode), do: state

  def request_reload(%__MODULE__{status: :conflict} = state), do: %{state | confirmation: :reload}
  def request_reload(%__MODULE__{} = state), do: state

  def reload_latest(%__MODULE__{confirmation: :reload} = state, latest),
    do: %{state | saved: latest, draft: latest, status: :saved, errors: %{}, confirmation: nil}

  def reload_latest(%__MODULE__{} = state, _latest), do: state

  def request_cancel(%__MODULE__{} = state) do
    if dirty?(state) and state.status != :pending,
      do: %{state | confirmation: :cancel},
      else: state
  end

  def request_leave(%__MODULE__{} = state) do
    if dirty?(state), do: %{state | confirmation: :leave}, else: state
  end

  def stay(%__MODULE__{} = state), do: %{state | confirmation: nil}
  def discard(%__MODULE__{status: :pending} = state), do: state

  def discard(%__MODULE__{confirmation: :cancel} = state),
    do: %{state | draft: state.saved, status: :saved, errors: %{}, confirmation: nil}

  def discard(%__MODULE__{confirmation: :leave} = state),
    do: %{state | draft: state.saved, status: :saved, errors: %{}, confirmation: nil}

  def discard(%__MODULE__{} = state), do: state
end
