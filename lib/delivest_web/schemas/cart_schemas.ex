defmodule DelivestWeb.Schemas.CartSchemas do
  alias OpenApiSpex.Schema

  defmodule ModifierChoice do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ModifierChoice",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        quantity: %Schema{type: :integer, minimum: 1, default: 1}
      },
      required: [:id]
    })
  end

  defmodule AddItemRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AddItemRequest",
      type: :object,
      properties: %{
        stars: %Schema{type: :boolean, description: "Купить за звёзды"},
        quantity: %Schema{type: :integer, minimum: 1, default: 1},
        modifiers: %Schema{
          type: :array,
          items: ModifierChoice,
          nullable: true,
          description:
            "Выбранные модификаторы. Пусто — модификаторы по умолчанию. Тот же товар с другими модификаторами — отдельная строка"
        }
      }
    })
  end

  defmodule ItemModifier do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ItemModifier",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, nullable: true},
        group_name: %Schema{type: :string, nullable: true, example: "Размер"},
        name: %Schema{type: :string, example: "35 см"},
        price: %Schema{type: :integer, example: 20_000, description: "Цена за единицу, копейки"},
        quantity: %Schema{type: :integer, example: 1}
      },
      required: [:name, :price, :quantity]
    })
  end

  defmodule PromoCodeRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PromoCodeRequest",
      type: :object,
      properties: %{
        code: %Schema{type: :string, example: "SUMMER2025", maxLength: 32}
      },
      required: [:code]
    })
  end

  defmodule CartContextRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CartContextRequest",
      description: "Контекст корзины, от которого зависят условия акций.",
      type: :object,
      properties: %{
        fulfillment_type: %Schema{
          type: :string,
          enum: ["dine_in", "delivery", "pickup"],
          nullable: true,
          example: "delivery"
        }
      }
    })
  end

  defmodule PromoReason do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PromoReason",
      description:
        "Почему акция пока не применилась. `subtotal`/`quantity` — сколько не хватает (`missing`, для `subtotal` в копейках), " <>
          "`product` — какого товара не хватает, `fulfillment` — допустимые способы получения, " <>
          "`time`/`weekday` — когда действует, `requires_client` — нужна авторизация.",
      type: :object,
      properties: %{
        type: %Schema{
          type: :string,
          enum: [
            "subtotal",
            "quantity",
            "product",
            "fulfillment",
            "time",
            "weekday",
            "requires_client"
          ]
        },
        missing: %Schema{type: :integer, nullable: true, example: 30_000},
        product_id: %Schema{type: :string, format: :uuid, nullable: true},
        name: %Schema{type: :string, nullable: true, example: "Кола 0.5"},
        allowed: %Schema{
          type: :array,
          nullable: true,
          items: %Schema{type: :string, enum: ["dine_in", "delivery", "pickup"]}
        },
        from: %Schema{type: :string, nullable: true, example: "11:00"},
        to: %Schema{type: :string, nullable: true, example: "16:00"},
        days: %Schema{
          type: :array,
          nullable: true,
          items: %Schema{type: :integer},
          example: [1, 2]
        }
      },
      required: [:type]
    })
  end

  defmodule PromoCodeState do
    require OpenApiSpex
    alias DelivestWeb.Schemas.CartSchemas.PromoReason

    OpenApiSpex.schema(%{
      title: "PromoCodeState",
      description:
        "Введённый промокод: `applied` — применён, `pending` — условия пока не выполнены (см. `reasons`), " <>
          "`rejected` — не может быть применён (см. `reason`).",
      type: :object,
      nullable: true,
      properties: %{
        code: %Schema{type: :string, example: "SUMMER2025"},
        status: %Schema{type: :string, enum: ["applied", "pending", "rejected"]},
        reason: %Schema{
          type: :string,
          nullable: true,
          enum: [
            "not_found",
            "inactive",
            "not_started",
            "expired",
            "exhausted",
            "requires_client",
            "client_limit",
            "not_owner",
            "code_used",
            "code_required"
          ]
        },
        name: %Schema{type: :string, nullable: true, example: "Летняя скидка"},
        reasons: %Schema{type: :array, items: PromoReason}
      },
      required: [:code, :status, :reasons]
    })
  end

  defmodule PromoGift do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PromoGift",
      type: :object,
      properties: %{
        product_id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string, example: "Кола 0.5"},
        quantity: %Schema{type: :integer, example: 1}
      },
      required: [:product_id, :name, :quantity]
    })
  end

  defmodule AppliedPromotion do
    require OpenApiSpex
    alias DelivestWeb.Schemas.CartSchemas.PromoGift

    OpenApiSpex.schema(%{
      title: "AppliedPromotion",
      type: :object,
      properties: %{
        promotion_id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string, example: "Летняя скидка"},
        description: %Schema{type: :string, nullable: true},
        code: %Schema{type: :string, nullable: true, example: "SUMMER2025"},
        discount: %Schema{type: :integer, example: 15_000, description: "Скидка в копейках"},
        gifts: %Schema{type: :array, items: PromoGift}
      },
      required: [:promotion_id, :name, :discount, :gifts]
    })
  end

  defmodule PromoHint do
    require OpenApiSpex
    alias DelivestWeb.Schemas.CartSchemas.PromoReason

    OpenApiSpex.schema(%{
      title: "PromoHint",
      description: "Автоматическая акция, которая сработает при выполнении условий.",
      type: :object,
      properties: %{
        promotion_id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string, example: "Кола в подарок"},
        description: %Schema{type: :string, nullable: true},
        reasons: %Schema{type: :array, items: PromoReason}
      },
      required: [:promotion_id, :name, :reasons]
    })
  end

  defmodule CartItemResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CartItemResponse",
      type: :object,
      properties: %{
        stars: %Schema{type: :boolean},
        stars_price: %Schema{type: :integer, nullable: true},
        key: %Schema{
          type: :string,
          description:
            "Уникальный ключ строки: подарок, платный товар и товар с другими модификаторами — разные строки. Им же удаляется строка"
        },
        product_id: %Schema{
          type: :string,
          format: :uuid,
          example: "c4a3b8e0-1234-5678-9abc-def012345678"
        },
        name: %Schema{type: :string, example: "Пицца Маргарита"},
        image_url: %Schema{
          type: :string,
          example: "https://example.com/images/pizza.jpg",
          nullable: true
        },
        price: %Schema{type: :integer, example: 59_000, description: "Цена за единицу по меню"},
        quantity: %Schema{type: :integer, example: 2},
        total_price: %Schema{
          type: :integer,
          example: 106_200,
          description: "Итог по строке с учётом скидок"
        },
        base_total: %Schema{
          type: :integer,
          example: 118_000,
          description: "Итог по строке без скидок"
        },
        gift: %Schema{
          type: :boolean,
          example: false,
          description: "Подарок по акции: количество менять нельзя"
        },
        promotion_ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}},
        stopped: %Schema{type: :boolean, description: "Товар в стоп-листе: заказать нельзя"},
        modifiers: %Schema{type: :array, items: ItemModifier}
      },
      required: [
        :key,
        :product_id,
        :name,
        :price,
        :quantity,
        :total_price,
        :base_total,
        :gift,
        :promotion_ids
      ]
    })
  end

  defmodule CartResponse do
    require OpenApiSpex

    alias DelivestWeb.Schemas.CartSchemas.{
      AppliedPromotion,
      CartItemResponse,
      PromoCodeState,
      PromoHint
    }

    OpenApiSpex.schema(%{
      title: "CartResponse",
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
            session_id: %Schema{
              type: :string,
              example: "eceaec3d-dd25-4e19-8afc-f1d0f1412c9c",
              nullable: true
            },
            branch_id: %Schema{
              type: :string,
              format: :uuid,
              example: "7b45ded3-881e-4270-bc93-0ad6a904ec53",
              nullable: true
            },
            fulfillment_type: %Schema{
              type: :string,
              enum: ["dine_in", "delivery", "pickup"],
              nullable: true
            },
            items: %Schema{type: :array, items: CartItemResponse},
            total_quantity: %Schema{type: :integer, example: 3},
            subtotal_amount: %Schema{
              type: :integer,
              example: 170_000,
              description: "Сумма без скидок"
            },
            discount_amount: %Schema{type: :integer, example: 20_000},
            total_amount: %Schema{type: :integer, example: 150_000, description: "К оплате"},
            promo_code: PromoCodeState,
            promotions: %Schema{type: :array, items: AppliedPromotion},
            hints: %Schema{type: :array, items: PromoHint}
          },
          required: [
            :id,
            :items,
            :total_quantity,
            :subtotal_amount,
            :discount_amount,
            :total_amount,
            :promotions,
            :hints
          ]
        }
      },
      required: [:data]
    })
  end
end
