defmodule DelivestWeb.Dev.AtolStubController do
  use DelivestWeb, :controller

  def token(conn, _params), do: json(conn, %{token: "dev-atol", error: nil})

  def register(conn, _params) do
    uuid = Ecto.UUID.generate()
    json(conn, %{uuid: uuid, status: "done", payload: payload(uuid), error: nil})
  end

  def report(conn, %{"uuid" => uuid}),
    do: json(conn, %{uuid: uuid, status: "done", payload: payload(uuid), error: nil})

  defp payload(uuid) do
    %{
      fn_number: "9999078900000001",
      fiscal_document_number: 1,
      fiscal_document_attribute: 1_234_567_890,
      ofd_receipt_url: "https://ofd.example/receipt/#{uuid}"
    }
  end
end
