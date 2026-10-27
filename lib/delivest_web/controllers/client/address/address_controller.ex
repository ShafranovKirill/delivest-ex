defmodule DelivestWeb.Client.Address.AddressController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Delivest.Identity
  alias DelivestWeb.Helpers.ApiError

  alias DelivestWeb.Schemas.AddressSchemas.{
    AddressListResponse,
    AddressResponse,
    ClientAddressRequest
  }

  alias DelivestWeb.Schemas.ErrorSchemas.ErrorResponse

  @id_param [id: [in: :path, type: :string, description: "UUID адреса"]]

  operation(:index,
    summary: "Адреса доставки клиента",
    tags: ["Addresses"],
    security: [%{"bearer" => []}],
    responses: [
      ok: {"Адреса", "application/json", AddressListResponse},
      unauthorized: {"Нужна авторизация", "application/json", ErrorResponse}
    ]
  )

  def index(conn, _params) do
    render(conn, :index, addresses: Identity.list_client_addresses(client_id(conn)))
  end

  operation(:create,
    summary: "Добавить адрес",
    tags: ["Addresses"],
    security: [%{"bearer" => []}],
    request_body: {"Адрес", "application/json", ClientAddressRequest},
    responses: [
      ok: {"Адрес", "application/json", AddressResponse},
      unprocessable_entity: {"Ошибка валидации", "application/json", ErrorResponse}
    ]
  )

  def create(conn, params) do
    conn |> client_id() |> Identity.create_client_address(params) |> respond(conn)
  end

  operation(:update,
    summary: "Изменить адрес",
    tags: ["Addresses"],
    security: [%{"bearer" => []}],
    parameters: @id_param,
    request_body: {"Адрес", "application/json", ClientAddressRequest},
    responses: [
      ok: {"Адрес", "application/json", AddressResponse},
      not_found: {"Адрес не найден", "application/json", ErrorResponse},
      unprocessable_entity: {"Ошибка валидации", "application/json", ErrorResponse}
    ]
  )

  def update(conn, %{"id" => id} = params) do
    with {:ok, address} <- Identity.get_client_address(client_id(conn), id) do
      address |> Identity.update_client_address(params) |> respond(conn)
    else
      error -> respond(error, conn)
    end
  end

  operation(:delete,
    summary: "Удалить адрес",
    tags: ["Addresses"],
    security: [%{"bearer" => []}],
    parameters: @id_param,
    responses: [
      no_content: "Удалён",
      not_found: {"Адрес не найден", "application/json", ErrorResponse}
    ]
  )

  def delete(conn, %{"id" => id}) do
    with {:ok, address} <- Identity.get_client_address(client_id(conn), id),
         {:ok, _address} <- Identity.delete_client_address(address) do
      send_resp(conn, :no_content, "")
    else
      error -> respond(error, conn)
    end
  end

  defp client_id(conn), do: conn.assigns.current_client.id

  defp respond({:ok, address}, conn), do: render(conn, :show, address: address)

  defp respond({:error, :not_found}, conn),
    do: ApiError.send_error(conn, :not_found, :address_not_found, "Address not found")

  defp respond({:error, %Ecto.Changeset{} = changeset}, conn) do
    ApiError.send_error(
      conn,
      :unprocessable_entity,
      :validation_failed,
      "Validation failed",
      ApiError.changeset_errors(changeset)
    )
  end
end
