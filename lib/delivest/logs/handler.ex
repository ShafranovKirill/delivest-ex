defmodule Delivest.Logs.Handler do
  alias Delivest.Logs.{Buffer, Formatter}

  @request_loggers [Phoenix.Logger, Phoenix.LiveView.Logger]

  def log(%{meta: meta} = event, _config) do
    unless own?(meta) or request?(meta) do
      Buffer.push(Formatter.to_entry(event))
    end
  rescue
    _error -> :ok
  end

  defp own?(meta), do: meta[:pid] == Process.whereis(Buffer)

  defp request?(%{mfa: {module, _function, _arity}}), do: module in @request_loggers
  defp request?(_meta), do: false
end
