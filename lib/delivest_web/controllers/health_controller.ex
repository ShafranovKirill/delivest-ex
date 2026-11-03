defmodule DelivestWeb.HealthController do
  use DelivestWeb, :controller

  alias Delivest.Health

  def show(conn, _params), do: json(conn, Health.live())

  def ready(conn, _params) do
    case Health.ready() do
      %{status: "ok"} = body -> json(conn, body)
      {:error, body} -> conn |> put_status(:service_unavailable) |> json(body)
    end
  end
end
