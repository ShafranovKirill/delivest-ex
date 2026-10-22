defmodule Delivest.S3Stub do
  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, body, headers, _opts) do
    [method: method, url: url, body: body, headers: headers]
    |> Keyword.merge(plug: {Req.Test, __MODULE__}, retry: false, decode_body: false)
    |> Req.request()
    |> case do
      {:ok, response} ->
        {:ok,
         %{
           status_code: response.status,
           headers:
             Enum.map(response.headers, fn {name, values} -> {name, Enum.join(values, ",")} end),
           body: response.body
         }}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  def record(test_pid) do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: 20_000_000)
      send(test_pid, {:s3, conn.method, conn.request_path, body})
      Plug.Conn.send_resp(conn, 200, "")
    end)
  end

  def png(width, height) do
    {:ok, image} = Vix.Vips.Operation.black(width, height, bands: 3)
    {:ok, png} = Vix.Vips.Image.write_to_buffer(image, ".png")
    png
  end
end
