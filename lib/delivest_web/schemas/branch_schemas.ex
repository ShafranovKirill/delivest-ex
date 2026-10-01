defmodule DelivestWeb.Schemas.BranchSchemas do
  alias OpenApiSpex.Schema

  defmodule BranchInfoResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "BranchInfoResponse",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, example: "8f3b2c10-91ab-4cd2-81e2-123456789abc"},
        address: %Schema{type: :string, example: "ул. Пушкина, д. 10", nullable: true},
        phone_number: %Schema{type: :string, example: "+79990000000", nullable: true},
        delivery_time: %Schema{type: :integer, example: "30", nullable: true},
        vk_url: %Schema{type: :string, example: "https://vk.com/group_name", nullable: true},
        whatsapp_url: %Schema{type: :string, example: "https://wa.me/79990000000", nullable: true},
        instagram_url: %Schema{
          type: :string,
          example: "https://instagram.com/profile_name",
          nullable: true
        },
        frontpad_api_key: %Schema{
          type: :string,
          example: "frontpad-secret-key",
          nullable: true
        },
        frontpad_enabled: %Schema{type: :boolean, example: true, nullable: true},
        frontpad_settings: %Schema{
          type: :object,
          additionalProperties: true,
          example: %{mode: "live", webhook: "https://example.com/hook"},
          nullable: true
        },
        ycart_settings: %Schema{
          type: :object,
          properties: %{
            yandex_org_id: %Schema{type: :string, example: "123456789", nullable: true},
            latitude: %Schema{type: :number, example: 55.7558, nullable: true},
            longitude: %Schema{type: :number, example: 37.6173, nullable: true},
            address: %Schema{type: :string, example: "Москва, Красная площадь", nullable: true}
          },
          additionalProperties: true,
          nullable: true
        }
      },
      required: [:id]
    })
  end

  defmodule Branch do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Branch",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, example: "c4a3b8e0-1234-5678-9abc-def012345678"},
        name: %Schema{type: :string, example: "Центральный филиал"},
        slug: %Schema{type: :string, example: "central"},
        is_active: %Schema{type: :boolean, example: true},
        branch_info: %Schema{anyOf: [BranchInfoResponse, %Schema{type: :null}]}
      },
      required: [:id, :name, :slug, :is_active, :stocks]
    })
  end

  defmodule BranchResponse do
    require OpenApiSpex
    alias DelivestWeb.Schemas.BranchSchemas.Branch

    OpenApiSpex.schema(%{
      title: "BranchResponse",
      type: :object,
      properties: %{
        data: Branch
      },
      required: [:data]
    })
  end

  defmodule BranchListResponse do
    require OpenApiSpex
    alias DelivestWeb.Schemas.BranchSchemas.Branch

    OpenApiSpex.schema(%{
      title: "BranchListResponse",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: Branch}
      },
      required: [:data]
    })
  end
end
