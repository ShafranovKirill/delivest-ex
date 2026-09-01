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
        phone_number: %Schema{type: :string, example: "+79990000000", nullable: true}
      }
    })
  end

  defmodule Branch do
    require OpenApiSpex
    alias DelivestWeb.Schemas.BranchSchemas.BranchInfoResponse

    OpenApiSpex.schema(%{
      title: "Branch",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, example: "c4a3b8e0-1234-5678-9abc-def012345678"},
        name: %Schema{type: :string, example: "Центральный филиал"},
        slug: %Schema{type: :string, example: "central"},
        is_active: %Schema{type: :boolean, example: true},
        branch_info: %Schema{anyOf: [BranchInfoResponse, %Schema{type: :null}]}
      }
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
      }
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
      }
    })
  end
end
