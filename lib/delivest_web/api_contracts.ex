defmodule DelivestWeb.ApiContracts do
  @moduledoc "Contracts for HTTP routes whose controllers do not use ControllerSpecs."

  alias OpenApiSpex.{Header, Operation, Schema}
  alias DelivestWeb.Schemas.{CartSchemas, OrderSchemas}

  @json "application/json"
  @yandex_security [%{"yandexEdaBearer" => []}]

  def operation(controller, action) do
    case {controller, action} do
      {DelivestWeb.HealthController, :show} ->
        health(false)

      {DelivestWeb.HealthController, :ready} ->
        health(true)

      {DelivestWeb.Client.Storefront.BootstrapController, :show} ->
        storefront_bootstrap()

      {DelivestWeb.Client.Storefront.BootstrapController, :manifest} ->
        storefront_manifest()

      {DelivestWeb.Client.Storefront.SectionController, :show} ->
        storefront_section()

      {DelivestWeb.Client.Session.BootstrapController, :show} ->
        session_bootstrap()

      {DelivestWeb.Integrations.CrmWebhookController, :create} ->
        crm_webhook()

      {DelivestWeb.Integrations.FiscalCallbackController, :create} ->
        fiscal_webhook()

      {DelivestWeb.Integrations.YookassaWebhookController, :create} ->
        yookassa_webhook()

      {DelivestWeb.Integrations.ZvonokWebhookController, :create} ->
        zvonok_webhook()

      {DelivestWeb.Integrations.YandexEda.TokenController, :create} ->
        yandex_token()

      {DelivestWeb.Integrations.YandexEda.RestaurantController, :index} ->
        yandex_restaurant(:index)

      {DelivestWeb.Integrations.YandexEda.RestaurantController, :availability} ->
        yandex_restaurant(:availability)

      {DelivestWeb.Integrations.YandexEda.RestaurantController, :schedule} ->
        yandex_schedule()

      {DelivestWeb.Integrations.YandexEda.RestaurantController, :zones} ->
        yandex_zones()

      {DelivestWeb.Integrations.YandexEda.RestaurantController, :zone_meta} ->
        yandex_zone_meta()

      {DelivestWeb.Integrations.YandexEda.MenuController, name}
      when name in [:composition, :availability] ->
        yandex_menu(name)

      {DelivestWeb.Integrations.YandexEda.OrderController, :status} ->
        yandex_order_status()

      {DelivestWeb.Integrations.YandexEda.OrderController, name}
      when name in [:create, :show, :update, :delete, :update_status, :courier, :feedback] ->
        yandex_order(name)

      {DelivestWeb.Integrations.YandexEda.MenuController, _} ->
        nil

      {DelivestWeb.Integrations.YandexEda.RestaurantController, _} ->
        nil

      _ ->
        nil
    end
  end

  defp s(type, attrs), do: struct(Schema, Keyword.put(attrs, :type, type))

  defp obj(properties, required \\ [], attrs \\ []),
    do: s(:object, Keyword.merge([properties: properties, required: required], attrs))

  defp array(item, attrs \\ []), do: s(:array, Keyword.put(attrs, :items, item))
  defp text(attrs \\ []), do: s(:string, attrs)
  defp integer(attrs \\ []), do: s(:integer, attrs)
  defp number(attrs \\ []), do: s(:number, attrs)
  defp boolean(attrs \\ []), do: s(:boolean, attrs)

  defp response(description, schema, media \\ @json),
    do: Operation.response(description, media, schema)

  defp no_content(description), do: Operation.response(description, nil, nil)

  defp body(description, schema, required \\ true),
    do: Operation.request_body(description, @json, schema, required: required)

  defp parameter(name, location, schema, description, opts \\ []),
    do: Operation.parameter(name, location, schema, description, opts)

  defp path(name, description, schema \\ text()),
    do: parameter(name, :path, schema, description)

  defp query(name, description, schema \\ text(), opts \\ []),
    do: parameter(name, :query, schema, description, opts)

  defp operation(id, summary, responses, opts) do
    struct!(
      Operation,
      [operationId: id, summary: summary, responses: responses, security: []] ++ opts
    )
  end

  defp error(code), do: response("Ошибка", obj(%{error: text(enum: [code])}, [:error]))
  defp webhook_error, do: response("Ошибка", obj(%{result: text(enum: ["error"])}, [:result]))
  defp webhook_token, do: path(:token, "Секретный токен вебхука", text(format: :password))

  defp health(false) do
    operation(
      "Health.show",
      "Проверка жизни приложения",
      %{
        200 => response("Приложение отвечает", health_response("ok", false))
      },
      tags: ["Health"]
    )
  end

  defp health(true) do
    operation(
      "Health.ready",
      "Готовность БД и миграций",
      %{
        200 => response("Готово", health_response("ok", true)),
        503 => response("Не готово", health_response("unavailable", true))
      },
      tags: ["Health"]
    )
  end

  defp health_response(status, checks?) do
    base = %{status: text(enum: [status]), app: text(enum: ["delivest"]), version: text()}

    props =
      if checks?,
        do:
          Map.put(
            base,
            :checks,
            obj(%{database: text(enum: ["ok", "error"]), migrations: text(enum: ["ok", "error"])})
          ),
        else: base

    obj(props, Map.keys(base) ++ if(checks?, do: [:checks], else: []))
  end

  defp revisions do
    obj(
      %{
        franchise: text(),
        branches: text(),
        menu: text(nullable: true),
        stories: text(nullable: true),
        advertising: text(nullable: true)
      },
      [:franchise, :branches, :menu, :stories, :advertising]
    )
  end

  defp storefront_common_params do
    [
      query(:branch_id, "UUID выбранного филиала", text(format: :uuid)),
      query(:locale, "Язык меню", text(enum: ["ru", "en"]))
    ]
  end

  defp storefront_bootstrap do
    schema =
      obj(
        %{
          schema_version: integer(enum: [1]),
          locale: text(enum: ["ru", "en"]),
          revisions: revisions(),
          valid_until: text(format: :date_time),
          franchise: franchise_data(),
          branches: array(branch_compact()),
          selected_branch: branch_data(nullable: true),
          menu: menu_data(nullable: true),
          stories: stories_data(nullable: true),
          advertising: advertising_data(nullable: true)
        },
        ~w(schema_version locale revisions valid_until franchise branches selected_branch menu stories advertising)a
      )

    operation(
      "Storefront.bootstrap",
      "Начальные публичные данные витрины",
      %{
        200 => response("Снимок витрины", schema),
        404 => error("branch_not_found"),
        503 => error("storefront_unavailable")
      },
      tags: ["Client storefront"],
      parameters: [query(:slug, "Slug филиала") | storefront_common_params()]
    )
  end

  defp storefront_manifest do
    operation(
      "Storefront.manifest",
      "Ревизии и реклама филиала",
      %{
        200 =>
          response(
            "Манифест",
            obj(
              %{
                revisions: revisions(),
                advertising: advertising_data(),
                valid_until: text(format: :date_time)
              },
              [:revisions, :advertising, :valid_until]
            )
          ),
        400 => error("branch_id_required"),
        404 => error("branch_not_found"),
        503 => error("storefront_unavailable")
      },
      tags: ["Client storefront"],
      parameters: [query(:branch_id, "UUID филиала", text(format: :uuid), required: true)]
    )
  end

  defp storefront_section do
    section =
      path(
        :section,
        "Раздел витрины",
        text(enum: ~w(franchise branches menu stories advertising))
      )

    data = %Schema{
      anyOf: [
        franchise_data(),
        array(branch_data()),
        menu_data(),
        stories_data(),
        advertising_data()
      ]
    }

    schema =
      obj(%{data: data, revision: text(), valid_until: text(format: :date_time)}, [
        :data,
        :revision,
        :valid_until
      ])

    operation(
      "Storefront.section",
      "Раздел витрины с ETag",
      %{
        200 => %{
          response("Данные раздела", schema)
          | headers: %{
              "ETag" => %Header{description: "Ревизия раздела", schema: text()},
              "X-Storefront-Valid-Until" => %Header{
                description: "Срок актуальности",
                schema: text(format: :date_time)
              }
            }
        },
        304 => no_content("ETag совпал"),
        400 => error("invalid_branch_id"),
        404 =>
          response(
            "Филиал или раздел не найден",
            obj(%{error: text(enum: ["branch_not_found", "section_not_found"])}, [:error])
          ),
        503 => error("storefront_unavailable")
      },
      tags: ["Client storefront"],
      parameters:
        [section | storefront_common_params()] ++
          [parameter(:"If-None-Match", :header, text(), "Для условного GET")]
    )
  end

  defp session_bootstrap do
    cart = CartSchemas.CartResponse.schema().properties.data
    orders = OrderSchemas.ActiveOrdersResponse.schema().properties.data

    schema =
      obj(%{cart: %{cart | nullable: true}, active_orders: orders, socket_token: text()}, [
        :cart,
        :active_orders,
        :socket_token
      ])

    operation(
      "ClientSession.bootstrap",
      "Текущая корзина и заказы сессии",
      %{
        200 => response("Состояние сессии", schema),
        400 => error("branch_id_required"),
        401 =>
          response(
            "Недействительный bearer токен",
            DelivestWeb.Schemas.ErrorSchemas.ErrorResponse
          ),
        403 => error("cart_owner_mismatch"),
        404 => error("branch_not_found")
      },
      tags: ["Client session"],
      security: [%{}, %{"bearer" => []}],
      description:
        "Может привязать существующую корзину к клиенту. Cookie session_id задаёт гостевую сессию; bearer необязателен.",
      parameters: [
        query(:branch_id, "UUID активного филиала", text(format: :uuid), required: true)
      ],
      extensions: %{"x-delivest-state-changing" => true}
    )
  end

  defp franchise_data do
    DelivestWeb.Schemas.FranchiseSchemas.FranchiseResponse.schema().properties.data
  end

  defp branch_data(attrs \\ []),
    do: DelivestWeb.Schemas.BranchSchemas.Branch.schema() |> struct(attrs)

  defp branch_compact do
    info = DelivestWeb.Schemas.BranchSchemas.BranchInfoResponse.schema()

    fields =
      ~w(address city phone_number manual_rating latitude longitude timezone working_hours special_hours intake maintenance fulfillment_methods)a

    compact_info = obj(Map.take(info.properties, fields), [], nullable: true)

    obj(
      %{
        id: text(format: :uuid),
        slug: text(),
        name: text(),
        is_active: boolean(),
        branch_info: compact_info
      },
      [:id, :slug, :name, :is_active, :branch_info]
    )
  end

  defp menu_data(attrs \\ []) do
    base = DelivestWeb.Schemas.MenuSchemas.MenuResponse.schema().properties.data
    struct(base, attrs)
  end

  defp stories_data(attrs \\ []) do
    base = DelivestWeb.Schemas.StockSchemas.StocksListResponse.schema().properties.data
    struct(base, attrs)
  end

  defp advertising_data(attrs \\ []) do
    obj(
      %{
        enabled: boolean(),
        counter_id: text(nullable: true),
        generation: integer(),
        feature_version: text(),
        ecommerce: boolean(),
        capture: boolean(),
        collection_basis: text(enum: ["admin_approved", "disabled"]),
        webvisor: boolean(enum: [false])
      },
      ~w(enabled counter_id generation feature_version ecommerce capture collection_basis webvisor)a,
      attrs
    )
  end

  defp crm_webhook do
    operation(
      "Integrations.crm",
      "Webhook CRM",
      %{
        200 =>
          response(
            "Ответ провайдера; Frontpad может вернуть ignored",
            obj(%{result: text()}, [], additionalProperties: true)
          ),
        404 => webhook_error(),
        422 => webhook_error()
      },
      tags: ["Integrations"],
      description:
        "Тело и успешный ответ зависят от провайдера; для Frontpad известен action. Токен в пути является секретом.",
      parameters: [path(:provider, "Идентификатор CRM"), webhook_token()],
      requestBody:
        body("Payload провайдера", obj(%{action: text()}, [], additionalProperties: true))
    )
  end

  defp fiscal_webhook do
    operation(
      "Integrations.fiscal",
      "Callback фискализации",
      %{
        200 => response("Принято", obj(%{result: text(enum: ["ok"])}, [:result])),
        404 => webhook_error(),
        422 => webhook_error()
      },
      tags: ["Integrations"],
      description: "Тело зависит от провайдера; ATOL передаёт uuid и status.",
      parameters: [path(:provider, "Провайдер фискализации"), webhook_token()],
      requestBody:
        body(
          "Payload провайдера",
          obj(%{uuid: text(), status: text()}, [], additionalProperties: true)
        )
    )
  end

  defp yookassa_webhook do
    event =
      obj(%{event: text(), object: obj(%{id: text()}, [], additionalProperties: true)}, [],
        additionalProperties: true
      )

    operation(
      "Integrations.yookassa",
      "Webhook ЮKassa",
      %{
        200 =>
          response(
            "Принято, включая неизвестное событие",
            obj(%{result: text(enum: ["ok"])}, [:result])
          ),
        404 => webhook_error()
      },
      tags: ["Integrations"],
      parameters: [webhook_token()],
      requestBody: body("Событие ЮKassa", event)
    )
  end

  defp zvonok_webhook do
    operation(
      "Integrations.zvonok",
      "Подтверждение звонка Zvonok",
      %{
        200 =>
          response(
            "Подтверждено или пропущено",
            obj(%{result: text(enum: ["success", "ignored"])}, [:result])
          ),
        404 => webhook_error()
      },
      tags: ["Integrations"],
      description:
        "GET изменяет состояние подтверждения клиента; не включать в автоматический smoke.",
      parameters: [
        webhook_token(),
        query(:call_id, "ID звонка"),
        query(:phone, "Телефон"),
        query(:ct_call_id, "Альтернативное имя ID звонка"),
        query(:ct_phone, "Альтернативное имя телефона")
      ],
      extensions: %{"x-delivest-state-changing" => true}
    )
  end

  defp yandex_error do
    array(obj(%{code: integer(), description: text()}, [:code, :description]))
  end

  defp yandex_errors(statuses) do
    Map.new(statuses, fn status -> {status, response("Ошибка Яндекс Еды", yandex_error())} end)
    |> Map.put(401, response("Токен отсутствует или истёк", obj(%{reason: text()}, [:reason])))
  end

  defp yandex_operation(id, summary, success, opts \\ []) do
    errors = yandex_errors(Keyword.get(opts, :errors, [400, 404, 500]))

    attrs =
      opts
      |> Keyword.delete(:errors)
      |> Keyword.merge(tags: ["Integrations: yandex-eda"], security: @yandex_security)

    operation(id, summary, Map.merge(errors, success), attrs)
  end

  defp restaurant_id, do: path(:restaurant_id, "UUID ресторана", text(format: :uuid))
  defp order_id, do: path(:id, "ID заказа Яндекс Еды")

  defp yandex_token do
    token_request =
      obj(
        %{
          client_id: text(),
          client_secret: text(format: :password),
          grant_type: text(enum: ["client_credentials"])
        },
        [:client_id, :client_secret, :grant_type]
      )

    operation(
      "YandexEda.token",
      "Выдать OAuth токен",
      %{
        200 =>
          response(
            "Токен",
            obj(
              %{
                access_token: text(),
                token_type: text(enum: ["bearer"]),
                expires_in: integer()
              },
              [:access_token, :token_type, :expires_in]
            )
          ),
        400 => response("Неверные параметры или секрет", yandex_error())
      },
      tags: ["Integrations: yandex-eda"],
      requestBody: body("OAuth client credentials", token_request)
    )
  end

  defp yandex_restaurant(:index) do
    place =
      obj(%{id: text(format: :uuid), title: text(), address: text()}, [:id, :title, :address])

    yandex_operation("YandexEda.restaurants", "Список ресторанов", %{
      200 => response("Рестораны", obj(%{places: array(place)}, [:places]))
    })
  end

  defp yandex_restaurant(:availability) do
    place = obj(%{id: text(format: :uuid), enabled: boolean()}, [:id, :enabled])

    yandex_operation("YandexEda.restaurantsAvailability", "Доступность ресторанов", %{
      200 => response("Доступность", obj(%{places: array(place)}, [:places]))
    })
  end

  defp interval, do: obj(%{start: text(), end: text()}, [:start, :end])

  defp schedule do
    days = ~w(mon tue wed thu fri sat sun)a
    obj(Map.new(days, &{&1, array(interval())}), days)
  end

  defp yandex_schedule do
    yandex_operation(
      "YandexEda.schedule",
      "Расписание ресторана",
      %{
        200 => response("Недельное расписание", schedule())
      },
      parameters: [restaurant_id()]
    )
  end

  defp money, do: obj(%{currency: text(enum: ["RUB"]), value: number()}, [:currency, :value])

  defp threshold,
    do: obj(%{orderCost: money(), deliveryCost: money()}, [:orderCost, :deliveryCost])

  defp zone_meta do
    obj(
      %{
        zoneId: text(),
        enabled: boolean(),
        intervals: schedule(),
        averageDeliveryTime: integer(),
        thresholds: array(threshold())
      },
      [:zoneId, :enabled, :intervals, :averageDeliveryTime, :thresholds]
    )
  end

  defp yandex_zones do
    coordinate = obj(%{lt: number(), lg: number()}, [:lt, :lg])

    zone =
      obj(%{name: text(), coordinates: array(coordinate), meta: zone_meta()}, [
        :name,
        :coordinates,
        :meta
      ])

    yandex_operation(
      "YandexEda.zones",
      "Зоны доставки",
      %{
        200 => response("Зоны", array(zone))
      },
      parameters: [restaurant_id()]
    )
  end

  defp yandex_zone_meta do
    yandex_operation(
      "YandexEda.zoneMeta",
      "Версии зон доставки",
      %{
        200 => response("Метаданные зон", array(zone_meta()))
      },
      parameters: [restaurant_id()]
    )
  end

  defp yandex_menu(:composition) do
    category = obj(%{id: text(), name: text(), sortOrder: integer()}, [:id, :name, :sortOrder])

    modifier =
      obj(
        %{id: text(), name: text(), price: number(), minAmount: integer(), maxAmount: integer()},
        ~w(id name price minAmount maxAmount)a
      )

    group =
      obj(
        %{
          id: text(),
          name: text(),
          minSelectedModifiers: integer(),
          maxSelectedModifiers: integer(),
          sortOrder: integer(),
          modifiers: array(modifier)
        },
        ~w(id name minSelectedModifiers maxSelectedModifiers sortOrder modifiers)a
      )

    image = obj(%{hash: text(), url: text(format: :uri)}, [:hash, :url])

    item =
      obj(
        %{
          id: text(),
          categoryId: text(),
          name: text(),
          price: number(),
          measure: number(),
          measureUnit: text(enum: ["г", "мл"]),
          sortOrder: integer(),
          modifierGroups: array(group),
          description: text(),
          images: array(image),
          nutrients:
            obj(
              %{
                calories: number(),
                proteins: number(),
                fats: number(),
                carbohydrates: number()
              },
              ~w(calories proteins fats carbohydrates)a
            ),
          excise: text(),
          vat: number()
        },
        ~w(id categoryId name price measure measureUnit sortOrder modifierGroups)a
      )

    schema =
      obj(%{categories: array(category), items: array(item), lastChange: text()}, [
        :categories,
        :items,
        :lastChange
      ])

    yandex_operation(
      "YandexEda.menuComposition",
      "Меню ресторана",
      %{
        200 =>
          response("Композиция меню", schema, "application/vnd.eats.menu.composition.v2+json")
      },
      parameters: [restaurant_id()]
    )
  end

  defp yandex_menu(:availability) do
    item = obj(%{itemId: text(), stock: integer()}, [:itemId, :stock])
    modifier = obj(%{modifierId: text(), stock: integer()}, [:modifierId, :stock])
    schema = obj(%{items: array(item), modifiers: array(modifier)}, [:items, :modifiers])

    yandex_operation(
      "YandexEda.menuAvailability",
      "Стоп-лист ресторана",
      %{
        200 => response("Доступность", schema, "application/vnd.eats.menu.availability.v2+json")
      },
      parameters: [restaurant_id()]
    )
  end

  defp yandex_order_item do
    modification =
      obj(%{id: text(), name: text(), price: number(minimum: 0), quantity: number(minimum: 0)})

    obj(
      %{
        id: text(),
        quantity: number(minimum: 0, exclusiveMinimum: true),
        price: number(minimum: 0),
        name: text(),
        modifications: array(modification)
      },
      [:id, :quantity, :price]
    )
  end

  defp payment_info do
    obj(
      %{
        paymentType: text(enum: ["CARD", "CASH"]),
        itemsCost: number(minimum: 0),
        deliveryFee: number(minimum: 0),
        change: number(minimum: 0)
      },
      [:paymentType, :itemsCost]
    )
  end

  defp delivery_info do
    coordinate = %Schema{anyOf: [number(), text()]}

    address =
      obj(%{full: text(), latitude: coordinate, longitude: coordinate}, [
        :full,
        :latitude,
        :longitude
      ])

    obj(
      %{
        courierArrivementDate: text(format: :date_time),
        deliveryDate: text(format: :date_time),
        clientArrivementDate: text(format: :date_time),
        deliveryAddress: address,
        clientName: text(),
        realPhoneNumber: text(),
        phoneNumber: text(),
        pickupCode: text()
      },
      []
    )
  end

  defp yandex_order_request do
    base = %{
      eatsId: text(minLength: 1),
      restaurantId: text(minLength: 1),
      items: array(yandex_order_item(), minItems: 1),
      paymentInfo: payment_info(),
      platform: text(),
      comment: text(),
      persons: integer(minimum: 0, maximum: 99)
    }

    required = [:discriminator, :eatsId, :restaurantId, :items, :paymentInfo, :deliveryInfo]

    variants =
      Enum.map(
        [
          {"yandex", [:courierArrivementDate]},
          {"marketplace", [:deliveryDate, :deliveryAddress]},
          {"pickup", [:clientArrivementDate]}
        ],
        fn {discriminator, delivery_required} ->
          delivery = %{delivery_info() | required: delivery_required}

          obj(
            Map.merge(base, %{
              discriminator: text(enum: [discriminator]),
              deliveryInfo: delivery
            }),
            required
          )
        end
      )

    %Schema{oneOf: variants}
  end

  defp order_status do
    text(enum: ~w(NEW ACCEPTED_BY_RESTAURANT COOKING READY TAKEN_BY_COURIER DELIVERED CANCELLED))
  end

  defp yandex_order(:create) do
    success = obj(%{result: text(enum: ["OK"]), orderId: text()}, [:result, :orderId])

    unavailable =
      obj(
        %{
          type: text(enum: ["unavailable_goods"]),
          message: text(),
          goods: obj(%{}, [], additionalProperties: text())
        },
        [
          :type,
          :message,
          :goods
        ]
      )

    yandex_operation(
      "YandexEda.createOrder",
      "Создать заказ",
      %{
        200 => response("Создан или найден идемпотентный заказ", success),
        406 => response("Недоступные товары", unavailable)
      },
      requestBody: body("Заказ Яндекс Еды", yandex_order_request()),
      errors: [400, 404, 500]
    )
  end

  defp yandex_order(:show) do
    yandex_operation(
      "YandexEda.showOrder",
      "Получить исходный заказ",
      %{
        200 =>
          response(
            "Исходный запрос заказа",
            yandex_order_request(),
            "application/vnd.eats.order.v2+json"
          )
      },
      parameters: [order_id()]
    )
  end

  defp yandex_order(:update) do
    yandex_operation(
      "YandexEda.updateOrder",
      "Изменение заказа не поддерживается",
      %{
        422 => response("Операция не поддерживается (код 105)", yandex_error())
      },
      parameters: [order_id()],
      errors: []
    )
  end

  defp yandex_order(:delete) do
    yandex_operation(
      "YandexEda.deleteOrder",
      "Отменить заказ",
      %{
        200 => no_content("Заказ отменён")
      },
      parameters: [order_id()],
      requestBody: body("Необязательный комментарий", obj(%{comment: text()}), false)
    )
  end

  defp yandex_order(:update_status) do
    request =
      obj(
        %{
          status: text(enum: ~w(TAKEN_BY_COURIER DELIVERED CANCELLED)),
          comment: text(),
          reason: text()
        },
        [:status]
      )

    yandex_operation(
      "YandexEda.updateStatus",
      "Обновить статус заказа",
      %{
        204 => no_content("Статус принят")
      },
      parameters: [order_id()],
      requestBody: body("Статус", request)
    )
  end

  defp yandex_order(:courier) do
    request =
      obj(
        %{
          courier: %Schema{description: "Произвольные данные курьера"},
          location: %Schema{description: "Произвольная геопозиция"},
          maxPlaceArrivalTime: %Schema{description: "Произвольное время прибытия провайдера"}
        },
        [],
        additionalProperties: true
      )

    yandex_operation(
      "YandexEda.courier",
      "Сохранить данные курьера",
      %{
        204 => no_content("Данные приняты")
      },
      parameters: [order_id()],
      requestBody: body("Данные курьера (произвольные поля провайдера сохраняются)", request)
    )
  end

  defp yandex_order(:feedback) do
    feedback =
      obj(
        %{
          id: text(),
          eatsId: text(),
          restaurantId: text(),
          rating: integer(minimum: 1, maximum: 5),
          comment: text(),
          predefinedComment: text(),
          createdAt: text()
        },
        [:rating]
      )

    request = obj(%{orderId: text(), eatsId: text(), feedback: feedback}, [:feedback])

    yandex_operation(
      "YandexEda.feedback",
      "Оценка заказа",
      %{
        200 => response("Принято", obj(%{result: text(enum: ["OK"])}, [:result]))
      },
      requestBody: body("Оценка заказа", request)
    )
  end

  defp yandex_order_status do
    schema =
      obj(%{status: order_status(), comment: text(), updatedAt: text()}, [
        :status,
        :comment,
        :updatedAt
      ])

    yandex_operation(
      "YandexEda.orderStatus",
      "Текущий статус заказа",
      %{
        200 => response("Статус", schema)
      },
      parameters: [order_id()],
      description: "Чтение может согласовать сохранённый статус заказа.",
      extensions: %{"x-delivest-state-changing" => true}
    )
  end
end
