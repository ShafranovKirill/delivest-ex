defmodule Delivest.Integrations.TestCrm do
  @behaviour Delivest.Integrations.Crm.Provider

  defmodule Settings do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :token, :string
    end

    def changeset(settings, attrs, _required?), do: cast(settings, attrs, [:token])
  end

  @impl true
  def key, do: :test_crm

  @impl true
  def name, do: "Test CRM"

  @impl true
  def settings_schema, do: Settings

  @impl true
  def configured?(settings), do: not is_nil(settings)

  @impl true
  def idempotent?, do: Application.get_env(:delivest, :test_crm_idempotent, true)

  @impl true
  def capabilities, do: [:cancel, :update_comment, :update_address]

  @impl true
  def status_map(_settings), do: %{"1" => :preparing, "9" => :cancelled}

  @impl true
  def deliver_order(order, _settings),
    do: reply(:deliver, {:deliver, order.id}, {:ok, %{external_id: "t-1"}})

  @impl true
  def cancel_order(order, reason, _settings), do: reply(:cancel, {:cancel, order.id, reason}, :ok)

  @impl true
  def update_order(order, changes, _settings),
    do: reply(:update, {:update, order.id, changes}, :ok)

  @impl true
  def dictionaries(_settings), do: {:ok, %{payment_types: [%{id: "cash", name: "Наличные"}]}}

  @impl true
  def classify_error(:timeout), do: :retry
  def classify_error(_reason), do: :permanent

  @impl true
  def health_check(_settings), do: :ok

  @impl true
  def rate_limit(_settings), do: nil

  defp reply(action, message, default) do
    send(self(), message)

    if owner = Application.get_env(:delivest, :test_crm_observer),
      do: send(owner, {:crm_call, action, message})

    case Application.get_env(:delivest, :test_crm_barrier) do
      %{owner: owner, action: ^action} ->
        send(owner, {:crm_remote_success, self(), action, message})

        receive do
          {:crm_remote_release, ^action} -> :ok
        end

      _ ->
        :ok
    end

    Process.get({__MODULE__, action}, default)
  end
end
