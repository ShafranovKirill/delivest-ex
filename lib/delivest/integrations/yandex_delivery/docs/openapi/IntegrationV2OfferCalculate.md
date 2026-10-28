---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2OfferCalculate.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2OfferCalculate.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2OfferCalculate.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Получение вариантов доставки (для РФ)

<!-- markdownlint-disable-file -->

- Метод возвращает доступные варианты доставки.
- Каждый вариант содержит цену, временной интервал забора заказа на точке А, временной интервал доставки на точку B.
- После получения вариантов доставки можно выбрать оптимальный и создать заказ с использованием выбранного варианта.
- Получить варианты доставки можно только в России.


## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/offers/calculate
```

</div>

Адрес сервиса

</div>

</div>

### Headers

#|
|| **Name** | **Description** ||
||

_Accept-Language_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Предпочитаемый язык ответа

Например:
`ru` — русский
`en` — английский


_Example:_{.json-schema-reset .json-schema-example} `ru`
{.table-cell}
||
|#{.json-schema-properties}

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "items": [
    {
      "size": {
        "length": 0.1,
        "width": 0.2,
        "height": 0.3
      },
      "weight": 2.105,
      "quantity": 1,
      "pickup_point": 1,
      "dropoff_point": 2,
      "age_restricted": false
    }
  ],
  "route_points": [
    {
      "id": 1,
      "coordinates": [
        0.1,
        0.1
      ],
      "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
      "country": "Россия",
      "city": "Санкт-Петербург",
      "street": "Большая Монетная улица",
      "building": "23к1А",
      "porch": "A",
      "sfloor": "1",
      "sflat": "1"
    },
    {
      "id": 1,
      "coordinates": [
        0.1,
        0.1
      ],
      "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
      "country": "Россия",
      "city": "Санкт-Петербург",
      "street": "Большая Монетная улица",
      "building": "23к1А",
      "porch": "A",
      "sfloor": "1",
      "sflat": "1"
    }
  ],
  "referral_source": "bitrix",
  "requirements": {
    "taxi_classes": [
      "cargo"
    ],
    "cargo_type": "lcv_m",
    "cargo_loaders": 1,
    "pro_courier": false,
    "cargo_options": [
      "thermobag"
    ],
    "skip_door_to_door": false,
    "due": "2020-01-01T00:00:00+00:00",
    "rental_duration": 0
  }
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_items_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [Item](#entity-Item)[]

Параметры товаров

_Min items:_{.json-schema-reset .json-schema-assertion} `1`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "size": {
      "length": 0.1,
      "width": 0.2,
      "height": 0.3
    },
    "weight": 2.105,
    "quantity": 1,
    "pickup_point": 1,
    "dropoff_point": 2,
    "age_restricted": false
  }
]
```

{% endcut %}
{.table-cell}
||
||

_route_points_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [RoutePointWithAddress](#entity-RoutePointWithAddress)[]

Точки маршрута. Отсортированы в порядке посещения А-Б1....БN

_Min items:_{.json-schema-reset .json-schema-assertion} `2`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "id": 1,
    "coordinates": [
      0.1,
      0.1
    ],
    "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
    "country": "Россия",
    "city": "Санкт-Петербург",
    "street": "Большая Монетная улица",
    "building": "23к1А",
    "porch": "A",
    "sfloor": "1",
    "sflat": "1"
  },
  {
    "id": 1,
    "coordinates": [
      0.1,
      0.1
    ],
    "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
    "country": "Россия",
    "city": "Санкт-Петербург",
    "street": "Большая Монетная улица",
    "building": "23к1А",
    "porch": "A",
    "sfloor": "1",
    "sflat": "1"
  }
]
```

{% endcut %}
{.table-cell}
||
||

_referral_source_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Источник заявки (например, наименование CMS или интеграционного модуля).
Учитывается при расчёте стоимости доставки. При создании заявки через claims/create
передавайте то же значение referral_source, которое использовали при расчёте оффера.
Для LandPro используйте module_berid, для прямой интеграции с Wildberries — wildberries.


_Example:_{.json-schema-reset .json-schema-example} `bitrix`
{.table-cell}
||
||

_requirements_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [OfferRequirements](#entity-OfferRequirements)

Требования к доставке

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "taxi_classes": [
    "cargo"
  ],
  "cargo_type": "lcv_m",
  "cargo_loaders": 1,
  "pro_courier": false,
  "cargo_options": [
    "thermobag"
  ],
  "skip_door_to_door": false,
  "due": "2020-01-01T00:00:00+00:00",
  "rental_duration": 0
}
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### CargoItemSizes {#entity-CargoItemSizes}

Габариты товара в метрах. В полях следует передавать актуальные значения.

Если габариты не были переданы, заказ оформляется с учетом
максимально допустимых габаритов для выбранного тарифа.

Если фактические характеристики товара превысят допустимые,
курьер вправе отказаться от выполнения такого заказа на месте.
В этом случае будет удержана стоимость подачи.

Курьер (courier): до 0.80 м × 0.50 м × 0.50 м
Экспресс (express): до 1.00 м × 0.60 м × 0.50 м
Грузовой (cargo):
- Маленький кузов: до 1.70 м × 0.96 м × 0.90 м
- Средний кузов: до 2.60 м × 1.30 м × 1.50 м
- Большой кузов: до 3.80 м × 1.80 м × 1.80 м


#|
|| **Name** | **Description** ||
||

_height_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: number

Высота в метрах

_Min value:_{.json-schema-reset .json-schema-assertion} `0`

_Max value:_{.json-schema-reset .json-schema-assertion} `500`
{.table-cell}
||
||

_length_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: number

Длина в метрах

_Min value:_{.json-schema-reset .json-schema-assertion} `0`

_Max value:_{.json-schema-reset .json-schema-assertion} `500`
{.table-cell}
||
||

_width_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: number

Ширина в метрах

_Min value:_{.json-schema-reset .json-schema-assertion} `0`

_Max value:_{.json-schema-reset .json-schema-assertion} `500`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "length": 0.1,
  "width": 0.2,
  "height": 0.3
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### Item {#entity-Item}

#|
|| **Name** | **Description** ||
||

_quantity_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Количество единиц товара

_Min value:_{.json-schema-reset .json-schema-assertion} `1`
{.table-cell}
||
||

_age_restricted_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Нужно ли проверить возраст клиента при выдаче товара.
Проверка возраста недоступна для заказов роботом доставщиком.


_Default:_{.json-schema-reset .json-schema-value} `false`
{.table-cell}
||
||

_dropoff_point_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: integer

Идентификатор точки (int64), куда нужно доставить товар.
Может быть любым числом. Должен соответствовать значению route_points[].id у точки назначения.
Параметр обязательный, если в заказе несколько точек доставки.

{.table-cell}
||
||

_pickup_point_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: integer

Идентификатор точки (int64), откуда нужно забрать товар.
Может быть любым числом. Должен соответствовать значению route_points[].id у точки отправки.
Параметр обязательный, если в заказе несколько точек доставки.

{.table-cell}
||
||

_size_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CargoItemSizes](#entity-CargoItemSizes)

Габариты товара в метрах. В полях следует передавать актуальные значения.

Если габариты не были переданы, заказ оформляется с учетом
максимально допустимых габаритов для выбранного тарифа.

Если фактические характеристики товара превысят допустимые,
курьер вправе отказаться от выполнения такого заказа на месте.
В этом случае будет удержана стоимость подачи.

Курьер (courier): до 0.80 м × 0.50 м × 0.50 м
Экспресс (express): до 1.00 м × 0.60 м × 0.50 м
Грузовой (cargo):
- Маленький кузов: до 1.70 м × 0.96 м × 0.90 м
- Средний кузов: до 2.60 м × 1.30 м × 1.50 м
- Большой кузов: до 3.80 м × 1.80 м × 1.80 м


{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "length": 0.1,
  "width": 0.2,
  "height": 0.3
}
```

{% endcut %}
{.table-cell}
||
||

_weight_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: number

Вес товара в килограммах.
Пример: 2.105

{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "size": {
    "length": 0.1,
    "width": 0.2,
    "height": 0.3
  },
  "weight": 2.105,
  "quantity": 1,
  "pickup_point": 1,
  "dropoff_point": 2,
  "age_restricted": false
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### Point {#entity-Point}

Координаты точек в виде массива из двух вещественных чисел: долгота, широта — именно в таком порядке.


**Type**: number[]

_Min items:_{.json-schema-reset .json-schema-assertion} `2`

_Max items:_{.json-schema-reset .json-schema-assertion} `2`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  0.1,
  0.1
]
```

{% endcut %}

</div>

<div class="openapi-entity">

### AddressFullname {#entity-AddressFullname}

Полный адрес с указанием города, улицы и номера дома.
Номер квартиры, подъезда и этаж указывать не нужно.


**Type**: string

_Example:_{.json-schema-reset .json-schema-example} `Санкт-Петербург, Большая Монетная улица, 1к1А`

</div>

<div class="openapi-entity">

### RoutePointWithAddress {#entity-RoutePointWithAddress}

#|
|| **Name** | **Description** ||
||

_building_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Строение

_Example:_{.json-schema-reset .json-schema-example} `23к1А`
{.table-cell}
||
||

_city_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Город

_Example:_{.json-schema-reset .json-schema-example} `Санкт-Петербург`
{.table-cell}
||
||

_coordinates_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Point](#entity-Point)

Координаты точек в виде массива из двух вещественных чисел: долгота, широта — именно в таком порядке.


_Min items:_{.json-schema-reset .json-schema-assertion} `2`

_Max items:_{.json-schema-reset .json-schema-assertion} `2`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  0.1,
  0.1
]
```

{% endcut %}
{.table-cell}
||
||

_country_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Страна

_Example:_{.json-schema-reset .json-schema-example} `Россия`
{.table-cell}
||
||

_fullname_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [AddressFullname](#entity-AddressFullname)

Полный адрес с указанием города, улицы и номера дома.
Номер квартиры, подъезда и этаж указывать не нужно.


_Example:_{.json-schema-reset .json-schema-example} `Санкт-Петербург, Большая Монетная улица, 1к1А`
{.table-cell}
||
||

_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: integer

Числовой id точки(int64). Параметр обязательный, если в заказе несколько точек доставки

{.table-cell}
||
||

_porch_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Подъезд (может быть A)

_Example:_{.json-schema-reset .json-schema-example} `A`
{.table-cell}
||
||

_sflat_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Квартира

_Example:_{.json-schema-reset .json-schema-example} `1`
{.table-cell}
||
||

_sfloor_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Этаж

_Example:_{.json-schema-reset .json-schema-example} `1`
{.table-cell}
||
||

_street_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Улица

_Example:_{.json-schema-reset .json-schema-example} `Большая Монетная улица`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "id": 1,
  "coordinates": [
    0.1,
    0.1
  ],
  "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
  "country": "Россия",
  "city": "Санкт-Петербург",
  "street": "Большая Монетная улица",
  "building": "23к1А",
  "porch": "A",
  "sfloor": "1",
  "sflat": "1"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### CargoType {#entity-CargoType}

Тип (размер) кузова для грузового тарифа.
Возможные значения:
- van ("Маленький кузов")
- lcv_m ("Средний кузов")
- lcv_l ("Большой кузов")
- lcv_xl ("Кузов XL")
Точный список возможных значений для конкретной геоточки уточняйте с помощью метода получения тарифов [tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md)


**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `van`, `lcv_m`, `lcv_l`, `lcv_xl`

</div>

<div class="openapi-entity">

### CargoOptions {#entity-CargoOptions}

Список дополнительных опций тарифа.

Возможные отдельные опции:
  - auto_courier (курьер только на автомобиле)
  - thermobag (курьер с термосумкой)

Пример списка опций: ["auto_courier"].

Точный список возможных значений для конкретной геоточки
уточните с помощью метода получения тарифов [tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md)


**Type**: string[]

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  "thermobag"
]
```

{% endcut %}

</div>

<div class="openapi-entity">

### OfferRequirements {#entity-OfferRequirements}

Требования к доставке

#|
|| **Name** | **Description** ||
||

_cargo_loaders_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: integer

Число грузчиков для грузового тарифа.
Возможные значения: 0, 1, 2.

Точный список возможных значений для конкретной геоточки
уточните с помощью метода получения тарифов [tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md)

{.table-cell}
||
||

_cargo_options_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CargoOptions](#entity-CargoOptions)

Список дополнительных опций тарифа.

Возможные отдельные опции:
  - auto_courier (курьер только на автомобиле)
  - thermobag (курьер с термосумкой)

Пример списка опций: ["auto_courier"].

Точный список возможных значений для конкретной геоточки
уточните с помощью метода получения тарифов [tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md)


{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  "thermobag"
]
```

{% endcut %}
{.table-cell}
||
||

_cargo_type_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CargoType](#entity-CargoType)

Тип (размер) кузова для грузового тарифа.
Возможные значения:
- van ("Маленький кузов")
- lcv_m ("Средний кузов")
- lcv_l ("Большой кузов")
- lcv_xl ("Кузов XL")
Точный список возможных значений для конкретной геоточки уточняйте с помощью метода получения тарифов [tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md)


_Enum:_{.json-schema-reset .json-schema-value} `van`, `lcv_m`, `lcv_l`, `lcv_xl`
{.table-cell}
||
||

_due_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Желаемое время прибытия исполнителя на точку А (source).
В РФ отложить расчетное время прибытия исполнителя можно:
    - на 30-240 минут от текущего момента – для тарифа `express`;
    - на пять суток от текущего момента – для тарифа `cargo`.

Параметр не совместим с опциями замедления в тарифе `express` на территории РФ.
Если этот параметр не задан, то запустится поиск исполнителя на ближайшее время.


_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T00:00:00+00:00`
{.table-cell}
||
||

_pro_courier_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Включить опцию "Профи" для тарифов "Экспресс" и "Курьер".
Поиск исполнителя будет происходить только среди опытных курьеров.

{.table-cell}
||
||

_rental_duration_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: integer

Время аренды, которое планирует клиент. Указывается в минутах.
Указывайте этот параметр только для почасового тарифа

{.table-cell}
||
||

_skip_door_to_door_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Отключить доставку до двери (выключить опцию "От двери до двери").

Возможные значения:
- true (курьер доставит заказ только на улицу, до подъезда)
- false (курьер доставит заказ до двери)


_Default:_{.json-schema-reset .json-schema-value} `false`
{.table-cell}
||
||

_taxi_classes_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string[]

Класс автомобиля для доставки.
Возможные значения: courier, express, cargo, sdd_multislot

Точный список возможных значений для конкретной геоточки
уточните с помощью метода получения тарифов [tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md)


_Min items:_{.json-schema-reset .json-schema-assertion} `1`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  "cargo"
]
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "taxi_classes": [
    "cargo"
  ],
  "cargo_type": "lcv_m",
  "cargo_loaders": 1,
  "pro_courier": false,
  "cargo_options": [
    "thermobag"
  ],
  "skip_door_to_door": false,
  "due": "2020-01-01T00:00:00+00:00",
  "rental_duration": 0
}
```

{% endcut %}

</div>

## Responses

<div class="openapi__response__code__200">

## 200 OK

OK

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "offers": [
    {
      "price": {
        "total_price": "673.0",
        "total_price_with_vat": "807.6",
        "base_price": "611.8",
        "surge_ratio": 1.1,
        "currency": "RUB"
      },
      "taxi_class": "express",
      "pickup_interval": {
        "from": "2023-07-17T08:02:26.607358+00:00",
        "to": "2023-07-17T08:42:26.607358+00:00"
      },
      "delivery_interval": {
        "from": "2023-07-17T08:02:26.607358+00:00",
        "to": "2023-07-17T09:15:43.607358+00:00"
      },
      "description": "express_30min_longer",
      "payload": "5e2TPP5f7Yqyv19yRZ+QVas4JK+lhwa17ncxA3VCGI8hvnFS+CIySbmfHQlR6vhC2S4XsW+M7TbEV0EQl1/1Z0PO3QQX8KbGb6rtKay",
      "offer_ttl": "2020-01-02T00:00:00+00:00"
    }
  ]
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_offers_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [CalculatedOffer](#entity-CalculatedOffer)[]

Массив предложений доставки

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "price": {
      "total_price": "673.0",
      "total_price_with_vat": "807.6",
      "base_price": "611.8",
      "surge_ratio": 1.1,
      "currency": "RUB"
    },
    "taxi_class": "express",
    "pickup_interval": {
      "from": "2023-07-17T08:02:26.607358+00:00",
      "to": "2023-07-17T08:42:26.607358+00:00"
    },
    "delivery_interval": {
      "from": "2023-07-17T08:02:26.607358+00:00",
      "to": "2023-07-17T09:15:43.607358+00:00"
    },
    "description": "express_30min_longer",
    "payload": "5e2TPP5f7Yqyv19yRZ+QVas4JK+lhwa17ncxA3VCGI8hvnFS+CIySbmfHQlR6vhC2S4XsW+M7TbEV0EQl1/1Z0PO3QQX8KbGb6rtKay",
    "offer_ttl": "2020-01-02T00:00:00+00:00"
  }
]
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### Currency {#entity-Currency}

Трехзначный код валюты, в которой ведется расчет

**Type**: string

_Min length:_{.json-schema-reset .json-schema-assertion} `3`

_Max length:_{.json-schema-reset .json-schema-assertion} `3`

_Example:_{.json-schema-reset .json-schema-example} `RUB`

</div>

<div class="openapi-entity">

### CalculatedOfferPrice {#entity-CalculatedOfferPrice}

Стоимость доставки

#|
|| **Name** | **Description** ||
||

_currency_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [Currency](#entity-Currency)

Трехзначный код валюты, в которой ведется расчет

_Min length:_{.json-schema-reset .json-schema-assertion} `3`

_Max length:_{.json-schema-reset .json-schema-assertion} `3`

_Example:_{.json-schema-reset .json-schema-example} `RUB`
{.table-cell}
||
||

_surge_ratio_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: number

Коэффициент роста стоимости заказа (в зависимости от нагрузки на систему)
{.table-cell}
||
||

_total_price_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Цена c учетом коэффициента роста стоимости заказа (без НДС)

_Pattern:_{.json-schema-reset .json-schema-assertion} `^-?[0-9]{1,14}(\.[0-9]{0,4})?$`

_Example:_{.json-schema-reset .json-schema-example} `673.0`
{.table-cell}
||
||

_total_price_with_vat_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Цена с учетом коэффициента роста стоимости заказа (с НДС)

_Pattern:_{.json-schema-reset .json-schema-assertion} `^-?[0-9]{1,14}(\.[0-9]{0,4})?$`

_Example:_{.json-schema-reset .json-schema-example} `807.6`
{.table-cell}
||
||

_base_price_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Базовая цена доставки

_Pattern:_{.json-schema-reset .json-schema-assertion} `^-?[0-9]{1,14}(\.[0-9]{0,4})?$`

_Example:_{.json-schema-reset .json-schema-example} `611.8`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "total_price": "673.0",
  "total_price_with_vat": "807.6",
  "base_price": "611.8",
  "surge_ratio": 1.1,
  "currency": "RUB"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### PickupTimeInterval {#entity-PickupTimeInterval}

Временной интервал забора (по точке A)

#|
|| **Name** | **Description** ||
||

_from_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Начало интервала (UTC)

_Example:_{.json-schema-reset .json-schema-example} `2023-07-17T08:02:26.607358+00:00`
{.table-cell}
||
||

_to_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Окончание интервала (дата и время)

_Example:_{.json-schema-reset .json-schema-example} `2023-07-17T08:42:26.607358+00:00`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "from": "2023-07-17T08:02:26.607358+00:00",
  "to": "2023-07-17T08:42:26.607358+00:00"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### DeliveryTimeInterval {#entity-DeliveryTimeInterval}

Временной интервал доставки (по точке B)

#|
|| **Name** | **Description** ||
||

_from_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Начало интервала (UTC)

_Example:_{.json-schema-reset .json-schema-example} `2023-07-17T08:02:26.607358+00:00`
{.table-cell}
||
||

_to_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Окончание интервала (дата и время)

_Example:_{.json-schema-reset .json-schema-example} `2023-07-17T09:15:43.607358+00:00`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "from": "2023-07-17T08:02:26.607358+00:00",
  "to": "2023-07-17T09:15:43.607358+00:00"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### CalculatedOffer {#entity-CalculatedOffer}

Варианты доставки

#|
|| **Name** | **Description** ||
||

_delivery_interval_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [DeliveryTimeInterval](#entity-DeliveryTimeInterval)

Временной интервал доставки (по точке B)

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "from": "2023-07-17T08:02:26.607358+00:00",
  "to": "2023-07-17T09:15:43.607358+00:00"
}
```

{% endcut %}
{.table-cell}
||
||

_payload_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

payload оффера доставки. Чтобы заказать доставку по выбранному офферу, нужно передать payload в методе [claims/create](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCreate.md).

_Example:_{.json-schema-reset .json-schema-example} `5e2TPP5f7Yqyv19yRZ+QVas4JK+lhwa17ncxA3VCGI8hvnFS+CIySbmfHQlR6vhC2S4XsW+M7TbEV0EQl1/1Z0PO3QQX8KbGb6rtKay`
{.table-cell}
||
||

_pickup_interval_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [PickupTimeInterval](#entity-PickupTimeInterval)

Временной интервал забора (по точке A)

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "from": "2023-07-17T08:02:26.607358+00:00",
  "to": "2023-07-17T08:42:26.607358+00:00"
}
```

{% endcut %}
{.table-cell}
||
||

_price_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [CalculatedOfferPrice](#entity-CalculatedOfferPrice)

Стоимость доставки

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "total_price": "673.0",
  "total_price_with_vat": "807.6",
  "base_price": "611.8",
  "surge_ratio": 1.1,
  "currency": "RUB"
}
```

{% endcut %}
{.table-cell}
||
||

_taxi_class_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тарифный класс

_Example:_{.json-schema-reset .json-schema-example} `express`
{.table-cell}
||
||

_description_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Описание варианта доставки. Пример: express_30min_longer (экспресс с замедлением на 30 минут)


_Example:_{.json-schema-reset .json-schema-example} `express_30min_longer`
{.table-cell}
||
||

_offer_ttl_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Время, до которого оффер можно использовать для создания заявки. Если
создать заявку после этого момента, то заявка перейдет в
статус 'estimating_failed'


_Example:_{.json-schema-reset .json-schema-example} `2020-01-02T00:00:00+00:00`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "price": {
    "total_price": "673.0",
    "total_price_with_vat": "807.6",
    "base_price": "611.8",
    "surge_ratio": 1.1,
    "currency": "RUB"
  },
  "taxi_class": "express",
  "pickup_interval": {
    "from": "2023-07-17T08:02:26.607358+00:00",
    "to": "2023-07-17T08:42:26.607358+00:00"
  },
  "delivery_interval": {
    "from": "2023-07-17T08:02:26.607358+00:00",
    "to": "2023-07-17T09:15:43.607358+00:00"
  },
  "description": "express_30min_longer",
  "payload": "5e2TPP5f7Yqyv19yRZ+QVas4JK+lhwa17ncxA3VCGI8hvnFS+CIySbmfHQlR6vhC2S4XsW+M7TbEV0EQl1/1Z0PO3QQX8KbGb6rtKay",
  "offer_ttl": "2020-01-02T00:00:00+00:00"
}
```

{% endcut %}

</div>

</div>

<div class="openapi__response__code__400">

## 400 Bad Request

Неверный запрос

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "bad_request",
  "message": "bad request"
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_code_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Код ошибки

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `bad_request`, `address_not_found`, `validation_error`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание ошибки

_Example:_{.json-schema-reset .json-schema-example} `bad request`
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

<div class="openapi__response__code__409">

## 409 Conflict

Не удалось рассчитать офферы

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "estimating.requirement_unavailable",
  "message": "requirement unavailable"
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_code_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Код ошибки

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `errors.suitable_offer_not_found`, `estimating.cargocorp_payment_failure`, `estimating.limited_by_claims_creation_overflow`, `estimating.no_pickup_point`, `estimating.payment_method_cant_order`, `estimating.payment_method_forbidden`, `estimating.permitted_tariffs_not_enough`, `estimating.requirement_unavailable`, `estimating.route_too_long`, `estimating.route_too_short`, `estimating.tariff.not_available_in_zone`, `estimating.tariff.not_present_in_tariff_line_strategy`, `estimating.tariff.no_sdd_tariff`, `estimating.too_large_linear_size`, `estimating.too_many_loaders`, `estimating.cargo_type_unavailable`, `estimating.warning.too_heavy_item`, `estimating.warning.too_large_item`, `estimating.zone_unavailable`, `estimating.swapped_coordinates`, `estimating.payment_method_zone_unavailable`, `estimating.route_is_prohibited`, `estimating.robot.no_route`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание ошибки

_Example:_{.json-schema-reset .json-schema-example} `requirement unavailable`
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

<div class="openapi__response__code__429">

## 429 Too Many Requests

Слишком много запросов

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "too_many_requests",
  "message": "Слишком много запросов"
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_code_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Код ошибки

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `too_many_requests`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание ошибки

_Example:_{.json-schema-reset .json-schema-example} `Слишком много запросов`
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

</div>

[*Deprecated]: No longer supported, please use an alternative and newer version.