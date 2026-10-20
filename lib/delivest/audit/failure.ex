defmodule Delivest.Audit.Failure do
  def reason({:error, _step, reason, _changes}), do: summarize(reason)
  def reason({:error, _step, reason}), do: summarize(reason)
  def reason({:error, reason}), do: summarize(reason)
  def reason(other), do: summarize(other)

  defp summarize(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> inspect()
  end

  defp summarize(reason), do: inspect(reason)
end
