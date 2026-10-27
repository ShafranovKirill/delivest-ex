defmodule Delivest.Integrations.Frontpad.StatusCodes do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:accepted, :preparing, :ready, :delivering, :completed, :cancelled]
  @hook_priority [:cancelled, :completed, :delivering, :ready, :preparing, :accepted]
  @hook_limit 5

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    for status <- @statuses, do: field(status, :string)
  end

  def statuses, do: @statuses

  def changeset(codes, attrs), do: cast(codes, attrs, @statuses)

  def codes(nil), do: []

  def codes(%__MODULE__{} = codes) do
    @hook_priority
    |> Enum.map(&Map.get(codes, &1))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.take(@hook_limit)
  end

  def hook_limit, do: @hook_limit

  def status_for(nil, _code), do: nil

  def status_for(%__MODULE__{} = codes, code) do
    code = to_string(code)
    Enum.find(@statuses, &(Map.get(codes, &1) == code))
  end
end
