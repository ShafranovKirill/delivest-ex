defmodule Delivest.Integrations.Error do
  @type kind :: :permanent | :retry | {:snooze, pos_integer()} | :auth | :unknown_outcome

  @spec classify(term()) :: kind()
  def classify({:http_error, status, _body}) when status in [401, 403], do: :auth
  def classify({:http_error, 429, _body}), do: {:snooze, 60}
  def classify({:http_error, status, _body}) when status >= 500, do: :retry
  def classify({:http_error, _status, _body}), do: :permanent
  def classify({:connection_error, _message, _reason}), do: :retry
  def classify(_reason), do: :retry
end
