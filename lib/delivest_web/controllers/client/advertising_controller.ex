defmodule DelivestWeb.Client.AdvertisingController do
  use DelivestWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias OpenApiSpex.Schema
  alias Delivest.Integrations.YandexAds
  alias DelivestWeb.AnalyticsIdentity

  operation(:config,
    summary: "Public advertising capabilities for a branch",
    tags: ["Analytics"],
    parameters: [
      branch_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok:
        {"Enabled streams and receiver generation; never credentials", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{
                 enabled: %Schema{type: :boolean},
                 counter_id: %Schema{type: :string, nullable: true},
                 generation: %Schema{type: :integer},
                 feature_version: %Schema{type: :string, minLength: 43, maxLength: 43},
                 ecommerce: %Schema{type: :boolean},
                 capture: %Schema{type: :boolean},
                 collection_basis: %Schema{type: :string, enum: ["disabled", "admin_approved"]},
                 webvisor: %Schema{type: :boolean}
               }
             }
           }
         }}
    ]
  )

  operation(:identity,
    summary: "Capture unverified external click identifiers under a signed browser identity",
    tags: ["Analytics"],
    parameters: [
      branch_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body:
      {"External identifiers; identity and money cannot be supplied", "application/json",
       %Schema{
         type: :object,
         additionalProperties: false,
         required: [:generation, :feature_version],
         properties: %{
           generation: %Schema{type: :integer},
           feature_version: %Schema{type: :string, minLength: 43, maxLength: 43},
           client_id: %Schema{type: :string, maxLength: 128},
           yclid: %Schema{type: :string, maxLength: 128},
           campaign_id: %Schema{type: :string, maxLength: 128},
           ad_id: %Schema{type: :string, maxLength: 128}
         }
       }, required: true},
    responses: [accepted: {"Identifiers accepted", "application/json", %Schema{type: :object}}]
  )

  def config(conn, %{"branch_id" => branch_id}) do
    case Ecto.UUID.cast(branch_id) do
      {:ok, id} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> json(%{data: YandexAds.public_config(id)})

      _ ->
        send_resp(conn, 404, "")
    end
  end

  def identity(conn, %{"branch_id" => branch_id} = attrs) do
    {owner, new_guest} = AnalyticsIdentity.owner(conn)

    {owner, new_guest} =
      if String.starts_with?(owner, "guest:") and YandexAds.rotate_guest?(owner) do
        guest = Ecto.UUID.generate()
        {"guest:" <> guest, guest}
      else
        {owner, new_guest}
      end

    case Ecto.UUID.cast(branch_id) do
      {:ok, id} ->
        case YandexAds.capture_identity(id, owner, Map.delete(attrs, "branch_id")) do
          {:ok, :ok} ->
            conn =
              if new_guest, do: AnalyticsIdentity.put_guest_cookie(conn, new_guest), else: conn

            conn |> put_status(:accepted) |> json(%{data: %{accepted: true}})

          _ ->
            conn |> put_status(:not_found) |> json(%{error: "advertising_unavailable"})
        end

      _ ->
        send_resp(conn, 404, "")
    end
  end
end
