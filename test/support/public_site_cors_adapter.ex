defmodule Delivest.PublicSiteCorsAdapter do
  def put(config) do
    send(self(), {:cors, config})
    if Process.get(:fail_cors), do: {:error, :s3_down}, else: :ok
  end
end
