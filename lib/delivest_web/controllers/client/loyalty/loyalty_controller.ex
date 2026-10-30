defmodule DelivestWeb.Client.Loyalty.LoyaltyController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Loyalty
  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
  alias DelivestWeb.Schemas.LoyaltySchemas.LoyaltyResponse

  operation(:show,
    summary: "Бонусы клиента",
    description:
      "Баланс звёзд и последние движения. В филиале без бонусной системы `enabled` равен false.",
    tags: ["Loyalty"],
    security: [%{"bearer" => []}],
    parameters: [branch_id: [in: :query, type: :string, description: "UUID филиала"]],
    responses: [
      ok: {"Бонусы", "application/json", LoyaltyResponse},
      unauthorized: {"Нужна авторизация", "application/json", ErrorResponse}
    ]
  )

  def show(conn, params) do
    client = conn.assigns.current_client
    enabled = enabled?(params["branch_id"])

    render(conn, :show,
      enabled: enabled,
      balance: Loyalty.balance(client.id),
      history: if(enabled, do: Loyalty.history(client.id, 30), else: [])
    )
  end

  defp enabled?(branch_id) when is_binary(branch_id) do
    match?({:ok, _uuid}, Ecto.UUID.cast(branch_id)) and Loyalty.enabled?(branch_id)
  end

  defp enabled?(_branch_id), do: false
end
