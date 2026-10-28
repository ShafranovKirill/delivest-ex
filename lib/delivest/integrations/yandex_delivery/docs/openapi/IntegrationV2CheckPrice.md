---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2CheckPrice.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2CheckPrice.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2CheckPrice.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Предварительная оценка без создания заявки

<!-- markdownlint-disable-file -->

## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/check-price
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
    }
  ],
  "requirements": {
    "taxi_class": "cargo",
    "cargo_type": "lcv_m",
    "cargo_loaders": 1,
    "pro_courier": false,
    "cargo_options": [
      "thermobag"
    ],
    "same_day_data": {
      "delivery_interval": {
        "from": "2020-01-01T00:00:00+00:00",
        "to": "2020-01-02T00:00:00+00:00"
      }
    }
  },
  "skip_door_to_door": false
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_route_points_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [RoutePointWithAddress](#entity-RoutePointWithAddress)[]

Точки маршрута. Отсортированы в порядке посещения А-Б1....БN

_Min items:_{.json-schema-reset .json-schema-assertion} `1`

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
  }
]
```

{% endcut %}
{.table-cell}
||
||

_items_{.json-schema-reset .json-schema-property}
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

_requirements_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Requirements](#entity-Requirements)

Требования к доставке (класс авто, опции)

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "taxi_class": "cargo",
  "cargo_type": "lcv_m",
  "cargo_loaders": 1,
  "pro_courier": false,
  "cargo_options": [
    "thermobag"
  ],
  "same_day_data": {
    "delivery_interval": {
      "from": "2020-01-01T00:00:00+00:00",
      "to": "2020-01-02T00:00:00+00:00"
    }
  }
}
```

{% endcut %}
{.table-cell}
||
||

_skip_door_to_door_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Отключить доставку до двери (выключить опцию "От двери до двери").

Возможные значения:
- true (курьер доставит заказ только на улицу, до подъезда)
- false (курьер доставит заказ до двери) — значение по умолчанию.


_Default:_{.json-schema-reset .json-schema-value} `false`
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

### TimeInterval {#entity-TimeInterval}

Временной интервал

#|
|| **Name** | **Description** ||
||

_from_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Начало интервала

_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T00:00:00+00:00`
{.table-cell}
||
||

_to_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Окончание интервала (дата и время)

_Example:_{.json-schema-reset .json-schema-example} `2020-01-02T00:00:00+00:00`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "from": "2020-01-01T00:00:00+00:00",
  "to": "2020-01-02T00:00:00+00:00"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### Requirements {#entity-Requirements}

Требования к доставке (класс авто, опции)

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

_pro_courier_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Включить опцию "Профи" для тарифов "Экспресс" и "Курьер".
Поиск исполнителя будет происходить только среди опытных курьеров.

{.table-cell}
||
||

_same_day_data_{.json-schema-reset .json-schema-property}
{.table-cell}|
{% cut "**Type**: object" %}

#|
||

_delivery_interval_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [TimeInterval](#entity-TimeInterval)

Временной интервал

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "from": "2020-01-01T00:00:00+00:00",
  "to": "2020-01-02T00:00:00+00:00"
}
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

{% endcut %}

Опции доставки "В течение дня"


{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "delivery_interval": {
    "from": "2020-01-01T00:00:00+00:00",
    "to": "2020-01-02T00:00:00+00:00"
  }
}
```

{% endcut %}
{.table-cell}
||
||

_taxi_class_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Класс автомобиля для доставки.
Возможные значения: courier, express, cargo.

Точный список возможных значений для конкретной геоточки
уточните с помощью метода получения тарифов [tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md)


_Example:_{.json-schema-reset .json-schema-example} `cargo`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "taxi_class": "cargo",
  "cargo_type": "lcv_m",
  "cargo_loaders": 1,
  "pro_courier": false,
  "cargo_options": [
    "thermobag"
  ],
  "same_day_data": {
    "delivery_interval": {
      "from": "2020-01-01T00:00:00+00:00",
      "to": "2020-01-02T00:00:00+00:00"
    }
  }
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
  "price": "12.50",
  "currency_rules": {
    "code": "RUB",
    "text": "руб.",
    "template": "$VALUE$ $SIGN$$CURRENCY$",
    "sign": "₽"
  },
  "requirements": {
    "taxi_class": "cargo",
    "cargo_type": "lcv_m",
    "cargo_loaders": 1,
    "pro_courier": false,
    "cargo_options": [
      "thermobag"
    ],
    "same_day_data": {
      "delivery_interval": {
        "from": "2020-01-01T00:00:00+00:00",
        "to": "2020-01-02T00:00:00+00:00"
      }
    }
  },
  "distance_meters": 10,
  "eta": 10,
  "zone_id": "moscow"
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_price_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [Money](#entity-Money)

Стоимость доставки в формате десятичной дроби Decimal(18, 4)

_Pattern:_{.json-schema-reset .json-schema-assertion} `^-?[0-9]{1,14}(\.[0-9]{0,4})?$`

_Example:_{.json-schema-reset .json-schema-example} `12.50`
{.table-cell}
||
||

_requirements_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [Requirements](#entity-Requirements)

Требования к доставке (класс авто, опции)

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "taxi_class": "cargo",
  "cargo_type": "lcv_m",
  "cargo_loaders": 1,
  "pro_courier": false,
  "cargo_options": [
    "thermobag"
  ],
  "same_day_data": {
    "delivery_interval": {
      "from": "2020-01-01T00:00:00+00:00",
      "to": "2020-01-02T00:00:00+00:00"
    }
  }
}
```

{% endcut %}
{.table-cell}
||
||

_currency_rules_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CurrencyRules](#entity-CurrencyRules)

Правила отображения валюты

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "code": "RUB",
  "text": "руб.",
  "template": "$VALUE$ $SIGN$$CURRENCY$",
  "sign": "₽"
}
```

{% endcut %}
{.table-cell}
||
||

_distance_meters_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [RouteDistance](#entity-RouteDistance)

Расстояние в метрах для указанного маршрута, от первой точки до последней точки

_Example:_{.json-schema-reset .json-schema-example} `10`
{.table-cell}
||
||

_eta_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: number

Расчетное врем прибытия в минутах
{.table-cell}
||
||

_zone_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Идентификатор (ID) зоны доставки

_Example:_{.json-schema-reset .json-schema-example} `moscow`
{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### Money {#entity-Money}

Стоимость доставки в формате десятичной дроби Decimal(18, 4)

**Type**: string

_Pattern:_{.json-schema-reset .json-schema-assertion} `^-?[0-9]{1,14}(\.[0-9]{0,4})?$`

_Example:_{.json-schema-reset .json-schema-example} `12.50`

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

### CurrencyRules {#entity-CurrencyRules}

Правила отображения валюты

#|
|| **Name** | **Description** ||
||

_code_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [Currency](#entity-Currency)

Трехзначный код валюты, в которой ведется расчет

_Min length:_{.json-schema-reset .json-schema-assertion} `3`

_Max length:_{.json-schema-reset .json-schema-assertion} `3`

_Example:_{.json-schema-reset .json-schema-example} `RUB`
{.table-cell}
||
||

_template_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Шаблон для отображения валюты

_Example:_{.json-schema-reset .json-schema-example} `$VALUE$ $SIGN$$CURRENCY$`
{.table-cell}
||
||

_text_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Сокращенное наименование валюты

_Example:_{.json-schema-reset .json-schema-example} `руб.`
{.table-cell}
||
||

_sign_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Символ валюты

_Example:_{.json-schema-reset .json-schema-example} `₽`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "code": "RUB",
  "text": "руб.",
  "template": "$VALUE$ $SIGN$$CURRENCY$",
  "sign": "₽"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### RouteDistance {#entity-RouteDistance}

Расстояние в метрах для указанного маршрута, от первой точки до последней точки

**Type**: number

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

_Enum:_{.json-schema-reset .json-schema-value} `bad_request`, `address_not_found`
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

Нет подходящих машин | Не удалось построить маршрут

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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `errors.suitable_offer_not_found`, `estimating.cant_construct_route`, `estimating.cargocorp_payment_failure`, `estimating.claim.no_zone_id`, `estimating.limited_by_claims_creation_overflow`, `estimating.no_pickup_point`, `estimating.payment_method_cant_order`, `estimating.swapped_coordinates`, `estimating.payment_method_zone_unavailable`, `estimating.payment_method_forbidden`, `estimating.permitted_tariffs_not_enough`, `estimating.requirement_unavailable`, `estimating.route_too_long`, `estimating.route_too_short`, `estimating.tariff.no_categories`, `estimating.tariff.not_available_in_zone`, `estimating.tariff.not_present_in_tariff_line_strategy`, `estimating.tariff.no_sdd_tariff`, `estimating.tariff.no_tariff_plan`, `estimating.too_large_linear_size`, `estimating.too_many_loaders`, `estimating.cargo_type_unavailable`, `estimating.warning.too_heavy_item`, `estimating.warning.too_large_item`, `estimating.route_is_prohibited`
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