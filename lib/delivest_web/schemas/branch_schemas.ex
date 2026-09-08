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
        vk_url: %Schema{type: :string, example: "https://vk.com/group_name", nullable: true},
        whatsapp_url: %Schema{type: :string, example: "https://wa.me/79990000000", nullable: true},
        instagram_url: %Schema{
          type: :string,
          example: "https://instagram.com/profile_name",
          nullable: true
        }
      },
      required: [:id]
    })
  end

  defmodule StockResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "StockResponse",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, example: "a1b2c3d4-5678-90ab-cdef-1234567890ab"},
        description: %Schema{
          type: :string,
          example: "Скидка 20% на сет пицц по будням",
          nullable: true
        },
        photo_url: %Schema{type: :string, example: "https://cdn.delivest.com/stocks/promo1.jpg"},
        is_active: %Schema{type: :boolean, example: true}
      },
      required: [:id, :photo_url, :is_active]
    })
  end

  defmodule Branch do
    require OpenApiSpex
    alias DelivestWeb.Schemas.BranchSchemas.{BranchInfoResponse, StockResponse}

    OpenApiSpex.schema(%{
      title: "Branch",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, example: "c4a3b8e0-1234-5678-9abc-def012345678"},
        name: %Schema{type: :string, example: "Центральный филиал"},
        slug: %Schema{type: :string, example: "central"},
        is_active: %Schema{type: :boolean, example: true},
        branch_info: %Schema{anyOf: [BranchInfoResponse, %Schema{type: :null}]},
        stocks: %Schema{
          type: :array,
          items: StockResponse,
          description: "Список активных акций филиала"
        }
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
