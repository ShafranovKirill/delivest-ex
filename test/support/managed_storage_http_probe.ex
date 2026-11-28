defmodule Delivest.ManagedStorageHttpProbe do
  def request(options) do
    url = Keyword.fetch!(options, :url)
    method = Keyword.fetch!(options, :method)
    uri = URI.parse(url)
    send(self(), {:public_request, method, uri.host, uri.path, uri.query})

    cond do
      method == :put ->
        {:ok, %{status: 200, body: ""}}

      String.contains?(uri.path, "delivest-private") and is_nil(uri.query) ->
        {:ok, %{status: 403, body: "denied"}}

      String.contains?(uri.path, "delivest-private") ->
        {:ok, %{status: 200, body: "delivest-storage-probe"}}

      true ->
        {:ok, %{status: 200, body: "delivest-public-upload-probe"}}
    end
  end
end
