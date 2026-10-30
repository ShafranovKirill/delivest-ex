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
        longitude: %Schema{type: :number, format: :float, nullable: true, example: 65.534},
        formatted: %Schema{
          type: :string,
          nullable: true,
          example: "г Тюмень, ул Республики, д 10"
        },
        fias_id: %Schema{type: :string, nullable: true, description: "ФИАС дома"},
        postal_code: %Schema{type: :string, nullable: true, example: "625000"},
        district: %Schema{type: :string, nullable: true, example: "Центральный р-н"},
        geo_precision: %Schema{type: :integer, nullable: true, minimum: 0, maximum: 5}
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
        persons: %Schema{
          type: :integer,
          minimum: 0,
          maximum: 99,
          example: 2,
          nullable: true,
          description: "Количество приборов"
        },
        cash_given: %Schema{
          type: :integer,
          minimum: 1,
          example: 500_000,
          nullable: true,
          description: "Сдача с какой суммы, в копейках. Только для наличных"
        },
        fulfillment_type: %Schema{
          type: :string,
          enum: ["dine_in", "delivery", "pickup"],
          example: "delivery",
          nullable: true
        },
        payment_method: %Schema{
          type: :string,
          enum: ["cash", "card_offline", "online"],
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
        spend_points: %Schema{
          type: :integer,
          nullable: true,
          example: 100,
          description:
            "Сколько звёзд списать с суммы заказа (1 звезда = 1 ₽). Только для вошедшего клиента в филиале с включённым списанием"
        },
        address: AddressRequest,
        expected_total: %Schema{
          type: :integer,
          nullable: true,
          example: 150_000,
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
          example: 53_100,
          description: "Цена за единицу с учётом скидок"
        },
        base_price: %Schema{
          type: :integer,
          example: 59_000,
          description: "Цена за единицу по меню"
        },
        gift: %Schema{type: :boolean, example: false},
        quantity: %Schema{type: :integer, example: 2},
        modifiers: %Schema{type: :array, items: DelivestWeb.Schemas.CartSchemas.ItemModifier}
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
        discount: %Schema{type: :integer, example: 15_000}
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
            number: %Schema{type: :string, example: "261029-MSK1-042"},
            short_number: %Schema{type: :string, example: "42"},
            status: %Schema{
              type: :string,
              enum: [
                "created",
                "accepted",
                "preparing",
                "ready",
                "delivering",
                "completed",
                "cancelled"
              ],
              example: "created"
            },
            fulfillment_type: %Schema{type: :string, enum: ["dine_in", "delivery", "pickup"]},
            payment_method: %Schema{type: :string, enum: ["cash", "card_offline", "online"]},
            awaiting_payment: %Schema{
              type: :boolean,
              description: "Заказ ждёт онлайн-оплаты и ещё не принят в работу"
            },
            payment: %Schema{
              type: :object,
              nullable: true,
              description: "Только в ответе на создание онлайн-заказа",
              properties: %{confirmation_url: %Schema{type: :string, format: :uri}}
            },
            total_amount: %Schema{type: :integer, example: 118_000},
            subtotal_amount: %Schema{
              type: :integer,
              example: 133_000,
              description: "Сумма без скидок"
            },
            discount_amount: %Schema{type: :integer, example: 15_000},
            delivery_amount: %Schema{
              type: :integer,
              example: 20_000,
              description: "Стоимость доставки, входит в total_amount"
            },
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
            customer_phone_ext: %Schema{type: :string, nullable: true, example: "1234"},
            customer_name: %Schema{type: :string, nullable: true, example: "Иван"},
            persons: %Schema{type: :integer, nullable: true, example: 2},
            address: %Schema{type: :object, nullable: true, additionalProperties: true},
            items: %Schema{type: :array, items: OrderItemResponse}
          },
          required: [
            :id,
            :number,
            :short_number,
            :status,
            :fulfillment_type,
            :payment_method,
            :total_amount,
            :subtotal_amount,
            :discount_amount,
            :delivery_amount,
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

  defmodule OrderCourier do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "OrderCourier",
      type: :object,
      nullable: true,
      description: "Курьер, который взял заказ. Есть с назначения курьера до вручения",
      properties: %{
        name: %Schema{type: :string, nullable: true, example: "Иван"},
        phone: %Schema{
          type: :string,
          nullable: true,
          example: "+79001112233",
          description: "У курьера Яндекса подменный номер, добавочный после ,,"
        },
        tracking_url: %Schema{
          type: :string,
          nullable: true,
          description: "Ссылка отслеживания Яндекс Доставки"
        }
      },
      required: [:name, :phone, :tracking_url]
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
        number: %Schema{type: :string, example: "261029-MSK1-042"},
        short_number: %Schema{type: :string, example: "42"},
        status: %Schema{
          type: :string,
          enum: [
            "created",
            "accepted",
            "preparing",
            "ready",
            "delivering",
            "completed",
            "cancelled"
          ],
          example: "preparing"
        },
        fulfillment_type: %Schema{type: :string, enum: ["dine_in", "delivery", "pickup"]},
        payment_method: %Schema{type: :string, enum: ["cash", "card_offline", "online"]},
        total_amount: %Schema{type: :integer, example: 118_000},
        subtotal_amount: %Schema{
          type: :integer,
          example: 133_000,
          description: "Сумма без скидок"
        },
        discount_amount: %Schema{type: :integer, example: 15_000},
        delivery_amount: %Schema{
          type: :integer,
          example: 20_000,
          description: "Стоимость доставки, входит в total_amount"
        },
        promotions: %Schema{type: :array, items: DelivestWeb.Schemas.OrderSchemas.OrderPromotion},
        branch_id: %Schema{type: :string, format: :uuid},
        cook_by: %Schema{type: :string, format: :date_time, nullable: true},
        comment: %Schema{type: :string, nullable: true},
        address: %Schema{type: :object, nullable: true, additionalProperties: true},
        inserted_at: %Schema{type: :string, format: :date_time},
        courier: DelivestWeb.Schemas.OrderSchemas.OrderCourier,
        can_cancel: %Schema{
          type: :boolean,
          description: "Клиент ещё может отменить заказ сам"
        },
        items: %Schema{type: :array, items: OrderItemResponse}
      },
      required: [
        :id,
        :number,
        :short_number,
        :status,
        :fulfillment_type,
        :payment_method,
        :total_amount,
        :subtotal_amount,
        :discount_amount,
        :delivery_amount,
        :promotions,
        :branch_id,
        :inserted_at,
        :courier,
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

  defmodule PaymentLinkResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PaymentLinkResponse",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{confirmation_url: %Schema{type: :string, format: :uri}},
          required: [:confirmation_url]
        }
      },
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
