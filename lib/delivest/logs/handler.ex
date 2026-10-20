defmodule Delivest.Logs.Handler do
  alias Delivest.Logs.{Buffer, Formatter}

  def log(%{meta: meta} = event, _config) do
    unless meta[:pid] == Process.whereis(Buffer) do
      Buffer.push(Formatter.to_entry(event))
    end
  rescue
    _error -> :ok
  end
end
