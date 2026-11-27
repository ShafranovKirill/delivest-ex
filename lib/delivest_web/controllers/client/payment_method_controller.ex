defmodule DelivestWeb.Client.PaymentMethodController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Payments.SavedMethods
  alias DelivestWeb.Helpers.ApiError

  operation(:index,
    summary: "Сохранённые способы оплаты текущего клиента",
    tags: ["Payments"],
    responses: [
      ok:
        {"Способы оплаты", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{
             data: %OpenApiSpex.Schema{
               type: :array,
               items: %OpenApiSpex.Schema{
                 type: :object,
                 properties: %{
                   id: %OpenApiSpex.Schema{type: :string, format: :uuid},
                   type: %OpenApiSpex.Schema{type: :string, nullable: true},
                   title: %OpenApiSpex.Schema{type: :string},
                   last4: %OpenApiSpex.Schema{type: :string, nullable: true}
                 },
                 required: [:id, :title]
               }
             }
           },
           required: [:data]
         }}
    ]
  )

  def index(conn, _params) do
    methods =
      conn.assigns.current_client.id
      |> SavedMethods.list()
      |> Enum.map(&%{id: &1.id, type: &1.type, title: &1.title, last4: &1.last4})

    json(conn, %{data: methods})
  end

  operation(:delete,
    summary: "Локально удалить сохранённый способ оплаты",
    tags: ["Payments"],
    parameters: [id: [in: :path, type: :string, description: "Локальный UUID способа оплаты"]],
    responses: [no_content: "Способ удалён", not_found: "Способ не найден"]
  )

  def delete(conn, %{"id" => id}) do
    case SavedMethods.delete(conn.assigns.current_client.id, id) do
      {:ok, _method} ->
        send_resp(conn, :no_content, "")

      {:error, _reason} ->
        ApiError.send_error(
          conn,
          :not_found,
          :saved_payment_method_not_found,
          "Payment method not found"
        )
    end
  end
end
