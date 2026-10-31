defmodule DelivestWeb.Schemas.AuthSchemas do
  alias OpenApiSpex.Schema

  defmodule ClientProfile do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ClientProfile",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        phone: %Schema{type: :string, example: "+79990000000"},
        name: %Schema{type: :string, nullable: true, example: "Иван"}
      },
      required: [:id, :phone]
    })
  end

  defmodule ProfileResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ProfileResponse",
      type: :object,
      properties: %{data: ClientProfile},
      required: [:data]
    })
  end

  defmodule StartCallRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "StartCallRequest",
      type: :object,
      properties: %{phone: %Schema{type: :string, example: "+79990000000"}},
      required: [:phone]
    })
  end

  defmodule ConfirmCodeRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ConfirmCodeRequest",
      type: :object,
      properties: %{
        code: %Schema{type: :string, example: "1234", description: "Последние 4 цифры номера"}
      },
      required: [:code]
    })
  end

  defmodule StartCallResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "StartCallResponse",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            confirmation_id: %Schema{type: :string, format: :uuid},
            mode: %Schema{type: :string, enum: ["inbound", "flash"]},
            call_number: %Schema{
              type: :string,
              nullable: true,
              example: "+78000000000",
              description:
                "Режим inbound: номер, на который нужно позвонить. Режим flash: null, клиенту позвонят сами"
            },
            expires_in: %Schema{type: :integer, example: 600, description: "Секунды"}
          },
          required: [:confirmation_id, :mode, :call_number, :expires_in]
        }
      },
      required: [:data]
    })
  end

  defmodule Session do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ClientSession",
      type: :object,
      properties: %{
        status: %Schema{type: :string, enum: ["pending", "confirmed"]},
        access_token: %Schema{type: :string},
        refresh_token: %Schema{type: :string},
        expires_in: %Schema{type: :integer, example: 900, description: "Секунды"},
        client: ClientProfile
      },
      required: [:status]
    })
  end

  defmodule SessionResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ClientSessionResponse",
      type: :object,
      properties: %{data: Session},
      required: [:data]
    })
  end

  defmodule RefreshRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RefreshRequest",
      type: :object,
      properties: %{refresh_token: %Schema{type: :string}},
      required: [:refresh_token]
    })
  end
end
