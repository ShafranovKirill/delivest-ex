defmodule DelivestWeb.Schemas.MenuSchemas do
  alias OpenApiSpex.Schema

  defmodule ProductResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ProductResponse",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, example: "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"},
        name: %Schema{type: :string, example: "Пипперони"},
        old_price: %Schema{
          type: :string,
          nullable: true,
          example: "690",
          description: "Старая цена до скидки"
        },
        price: %Schema{
          type: :integer,
          example: 590,
          description: "Цена в копейках/минимальных единицах"
        },
        description: %Schema{type: :string, nullable: true, example: "Сочная пицца с колбасками"},
        quantity: %Schema{
          type: :integer,
          nullable: true,
          example: 10,
          description: "Количество товара на складе (в шт)"
        },
        weight: %Schema{
          type: :integer,
          nullable: true,
          example: 450,
          description: "Вес товара (в граммах)"
        },
        is_active: %Schema{type: :boolean, example: true},
        photo_url: %Schema{
          type: :string,
          format: :uri,
          nullable: true,
          example: "https://storage.example.com/images/pepperoni.jpg",
          description: "Ссылка на изображение товара"
        },
        external_id: %Schema{type: :string, nullable: true}
      }
    })
  end

  defmodule CategoryResponse do
    require OpenApiSpex
    alias DelivestWeb.Schemas.MenuSchemas.ProductResponse

    OpenApiSpex.schema(%{
      title: "CategoryResponse",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, example: "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"},
        name: %Schema{type: :string, example: "Пиццы"},
        order: %Schema{type: :number, format: :float, example: 1.0},
        is_active: %Schema{type: :boolean, example: true},
        products: %Schema{type: :array, items: ProductResponse}
      }
    })
  end

  defmodule MenuResponse do
    require OpenApiSpex
    alias DelivestWeb.Schemas.MenuSchemas.CategoryResponse

    OpenApiSpex.schema(%{
      title: "MenuResponse",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: CategoryResponse}
      }
    })
  end
end
