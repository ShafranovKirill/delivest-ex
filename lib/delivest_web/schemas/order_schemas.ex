defmodule DelivestWeb.Schemas.OrderSchemas do
  alias OpenApiSpex.Schema

  defmodule AddressRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AddressRequest",
      type: :object,
      properties: %{
        city: %Schema{type: :string, example: "Москва", nullable: true},
        street: %Schema{type: :string, example: "Ленина", nullable: true},
        house: %Schema{type: :string, example: "10", nullable: true},
        apartment: %Schema{type: :string, example: "12", nullable: true},
        floor: %Schema{type: :string, example: "3", nullable: true},
        entrance: %Schema{type: :string, example: "2", nullable: true},
        intercom: %Schema{type: :string, example: "42", nullable: true},
        comment: %Schema{type: :string, nullable: true, example: "Вход со двора"},
        latitude: %Schema{type: :number, format: :float, nullable: true, example: 57.153},
        longitude: %Schema{type: :number, format: :float, nullable: true, example: 65.534}
      }
    })
  end

  defmodule CreateOrderRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CreateOrderRequest",
      type: :object,
      properties: %{
        cart_id: %Schema{
          type: :string,
          format: :uuid,
          example: "8f3b2c10-91ab-4cd2-81e2-123456789abc",
          description: "UUID корзины"
        },
        branch_id: %Schema{
          type: :string,
          format: :uuid,
          example: "7b45ded3-881e-4270-bc93-0ad6a904ec53",
          description: "UUID филиала"
        },
        customer_phone: %Schema{
          type: :string,
          example: "+79990000000",
          nullable: true,
          description: "Телефон клиента для поиска/создания клиента"
        },
        customer_name: %Schema{
          type: :string,
          example: "Иван",
          nullable: true,
          description: "Имя клиента"
        },
        fulfillment_type: %Schema{
          type: :string,
          enum: ["dine_in", "delivery", "pickup"],
          example: "delivery",
          nullable: true
        },
        payment_method: %Schema{
          type: :string,
          enum: ["cash", "card_offline"],
          example: "cash",
          nullable: true
        },
        cook_by: %Schema{
          type: :string,
          format: :date_time,
          example: "2026-10-05T18:30:00",
          nullable: true,
          description:
            "Желаемое время приготовления. Если пусто — как можно скорее. Не более 30 дней от текущей даты"
        },
        comment: %Schema{
          type: :string,
          example: "Без лука",
          nullable: true
        },
        address: AddressRequest,
        expected_total: %Schema{
          type: :integer,
          nullable: true,
          example: 1500,
          description:
            "Сумма, которую видел клиент. Если итог после пересчёта акций окажется больше — вернётся `price_changed`"
        }
      },
      required: [:cart_id, :branch_id]
    })
  end

  defmodule OrderItemResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "OrderItemResponse",
      type: :object,
      properties: %{
        product_id: %Schema{
          type: :string,
          format: :uuid,
          example: "c4a3b8e0-1234-5678-9abc-def012345678"
        },
        title: %Schema{type: :string, example: "Пицца Маргарита"},
        price: %Schema{
          type: :integer,
          example: 531,
          description: "Цена за единицу с учётом скидок"
        },
        base_price: %Schema{type: :integer, example: 590, description: "Цена за единицу по меню"},
        gift: %Schema{type: :boolean, example: false},
        quantity: %Schema{type: :integer, example: 2}
      },
      required: [:product_id, :title, :price, :base_price, :gift, :quantity]
    })
  end

  defmodule OrderPromotion do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "OrderPromotion",
      type: :object,
      properties: %{
        name: %Schema{type: :string, example: "Летняя скидка"},
        code: %Schema{type: :string, nullable: true, example: "SUMMER2025"},
        discount: %Schema{type: :integer, example: 150}
      },
      required: [:name, :discount]
    })
  end

  defmodule OrderResponse do
    require OpenApiSpex
    alias DelivestWeb.Schemas.OrderSchemas.OrderItemResponse

    OpenApiSpex.schema(%{
      title: "OrderResponse",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            id: %Schema{
              type: :string,
              format: :uuid,
              example: "8f3b2c10-91ab-4cd2-81e2-123456789abc"
            },
            number: %Schema{type: :string, example: "ORD-1001"},
            status: %Schema{
              type: :string,
              enum: ["created", "preparing", "ready", "delivering", "completed", "cancelled"],
              example: "created"
            },
            fulfillment_type: %Schema{type: :string, enum: ["dine_in", "delivery", "pickup"]},
            payment_method: %Schema{type: :string, enum: ["cash", "card_offline"]},
            total_amount: %Schema{type: :integer, example: 1180},
            subtotal_amount: %Schema{
              type: :integer,
              example: 1330,
              description: "Сумма без скидок"
            },
            discount_amount: %Schema{type: :integer, example: 150},
            promotions: %Schema{
              type: :array,
              items: DelivestWeb.Schemas.OrderSchemas.OrderPromotion
            },
            branch_id: %Schema{
              type: :string,
              format: :uuid,
              example: "7b45ded3-881e-4270-bc93-0ad6a904ec53"
            },
            cart_id: %Schema{
              type: :string,
              format: :uuid,
              example: "8f3b2c10-91ab-4cd2-81e2-123456789abc"
            },
            client_id: %Schema{
              type: :string,
              format: :uuid,
              nullable: true,
              example: "c4a3b8e0-1234-5678-9abc-def012345678"
            },
            cook_by: %Schema{
              type: :string,
              format: :date_time,
              nullable: true,
              example: "2026-10-05T18:30:00"
            },
            comment: %Schema{type: :string, nullable: true, example: "Без лука"},
            customer_phone: %Schema{type: :string, nullable: true, example: "+79990000000"},
            customer_name: %Schema{type: :string, nullable: true, example: "Иван"},
            address: %Schema{type: :object, nullable: true, additionalProperties: true},
            items: %Schema{type: :array, items: OrderItemResponse}
          },
          required: [
            :id,
            :number,
            :status,
            :fulfillment_type,
            :payment_method,
            :total_amount,
            :subtotal_amount,
            :discount_amount,
            :promotions,
            :branch_id,
            :cart_id,
            :items
          ]
        }
      },
      required: [:data]
    })
  end

  defmodule ActiveOrder do
    require OpenApiSpex
    alias DelivestWeb.Schemas.OrderSchemas.OrderItemResponse

    OpenApiSpex.schema(%{
      title: "ActiveOrder",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        number: %Schema{type: :string, example: "A042"},
        status: %Schema{
          type: :string,
          enum: ["created", "preparing", "ready", "delivering", "completed", "cancelled"],
          example: "preparing"
        },
        fulfillment_type: %Schema{type: :string, enum: ["dine_in", "delivery", "pickup"]},
        payment_method: %Schema{type: :string, enum: ["cash", "card_offline"]},
        total_amount: %Schema{type: :integer, example: 1180},
        subtotal_amount: %Schema{type: :integer, example: 1330, description: "Сумма без скидок"},
        discount_amount: %Schema{type: :integer, example: 150},
        promotions: %Schema{type: :array, items: DelivestWeb.Schemas.OrderSchemas.OrderPromotion},
        branch_id: %Schema{type: :string, format: :uuid},
        cook_by: %Schema{type: :string, format: :date_time, nullable: true},
        comment: %Schema{type: :string, nullable: true},
        address: %Schema{type: :object, nullable: true, additionalProperties: true},
        inserted_at: %Schema{type: :string, format: :date_time},
        items: %Schema{type: :array, items: OrderItemResponse}
      },
      required: [
        :id,
        :number,
        :status,
        :fulfillment_type,
        :payment_method,
        :total_amount,
        :subtotal_amount,
        :discount_amount,
        :promotions,
        :branch_id,
        :inserted_at,
        :items
      ]
    })
  end

  defmodule ActiveOrdersResponse do
    require OpenApiSpex
    alias DelivestWeb.Schemas.OrderSchemas.ActiveOrder

    OpenApiSpex.schema(%{
      title: "ActiveOrdersResponse",
      type: :object,
      properties: %{data: %Schema{type: :array, items: ActiveOrder}},
      required: [:data]
    })
  end

  defmodule ClientOrdersResponse do
    require OpenApiSpex
    alias DelivestWeb.Schemas.OrderSchemas.ActiveOrder

    OpenApiSpex.schema(%{
      title: "ClientOrdersResponse",
      type: :object,
      properties: %{data: %Schema{type: :array, items: ActiveOrder}},
      required: [:data]
    })
  end
end
