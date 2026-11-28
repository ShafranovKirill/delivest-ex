defmodule Delivest.ManagedStorageBadHttpProbe do
  def request(options) do
    url = URI.parse(Keyword.fetch!(options, :url))

    if String.contains?(url.path, "delivest-private") and is_nil(url.query),
      do: {:ok, %{status: 403, body: "denied"}},
      else: {:ok, %{status: 200, body: "wrong data"}}
  end
end
