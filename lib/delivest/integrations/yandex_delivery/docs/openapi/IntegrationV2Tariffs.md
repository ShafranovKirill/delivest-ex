---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2Tariffs.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Доступные тарифы

<!-- markdownlint-disable-file -->

В ответе в поле supported_requirements возвращаются возможные дополнительные требования.
Доступные значения требований:
1)cargo_type, возможные варианты габаритов
2)cargo_loaders возможные варианты грузчиков
3)cargo_options возможные дополнительные опции: автокурьер - auto_courier, термосумка - thermobag
У каждого требования есть поле options, в котором определен список возможных значений,
для cargo_type/cargo_loaders можно выбрать только одно значение,
для cargo_options — несколько значений.
Данные требования можно передавать при создании заявки в поле client_requirements.name,
где в name передается имя дополнительного требования,
в value передается один из вариантов для cargo_type, cargo_loaders
или массив вариантов для cargo_options.


## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/tariffs
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
  "start_point": [
    0.1,
    0.1
  ],
  "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А"
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
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

_start_point_{.json-schema-reset .json-schema-property}
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
|#{.json-schema-properties}

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

## Responses

<div class="openapi__response__code__200">

## 200 OK

OK

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "available_tariffs": [
    {
      "name": "cargo",
      "title": "Экспресс",
      "text": "Тариф экспресс",
      "minimal_price": 213,
      "supported_requirements": [
        {}
      ],
      "delivery_options": [
        {
          "description": "example"
        }
      ]
    }
  ]
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_available_tariffs_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [B2BTariff](#entity-B2BTariff)[]

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "name": "cargo",
    "title": "Экспресс",
    "text": "Тариф экспресс",
    "minimal_price": 213,
    "supported_requirements": [
      {
        "name": "cargo_type",
        "title": "Тип кузова",
        "text": "Требование габаритов транспортного средства",
        "type": "select",
        "required": false,
        "options": [
          null
        ]
      }
    ],
    "delivery_options": [
      {
        "description": "example"
      }
    ]
  }
]
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### Tariff {#entity-Tariff}

Тариф

**Type**: string

_Example:_{.json-schema-reset .json-schema-example} `cargo`

</div>

<div class="openapi-entity">

### SelectType {#entity-SelectType}

Тип выбора: одиночный или множественный


**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `select`, `multi_select`

</div>

<div class="openapi-entity">

### CargoRequirementChoice {#entity-CargoRequirementChoice}

#|
|| **Name** | **Description** ||
||

_text_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Локализованое описание требования

_Example:_{.json-schema-reset .json-schema-example} `170 см в длину, 100 в ширину, 90 в высоту`
{.table-cell}
||
||

_title_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Локализованное название требования

_Example:_{.json-schema-reset .json-schema-example} `Маленький кузов`
{.table-cell}
||
||

_value_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
{% cut "**One of 2 types**" %}{.json-schema-combinators data-marker=or}

- **Type**: string

  _Example:_{.json-schema-reset .json-schema-example} `example`

- **Type**: integer

{% endcut %}

Значение, которое необходимо передать для учета требования при создании заказа

_Example:_{.json-schema-reset .json-schema-example} `van`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "title": "Маленький кузов",
  "text": "170 см в длину, 100 в ширину, 90 в высоту",
  "value": "van"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### SelectRequirement {#entity-SelectRequirement}

Требование с выбором из нескольких вариантов

#|
|| **Name** | **Description** ||
||

_name_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тип требования

_Example:_{.json-schema-reset .json-schema-example} `cargo_type`
{.table-cell}
||
||

_options_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [CargoRequirementChoice](#entity-CargoRequirementChoice)[]

Возможные варианты выбора

_Min items:_{.json-schema-reset .json-schema-assertion} `1`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "title": "Маленький кузов",
    "text": "170 см в длину, 100 в ширину, 90 в высоту",
    "value": "van"
  }
]
```

{% endcut %}
{.table-cell}
||
||

_required_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: boolean

Требование обязательно для создания заказа
{.table-cell}
||
||

_text_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Локализованное описание типа требования

_Example:_{.json-schema-reset .json-schema-example} `Требование габаритов транспортного средства`
{.table-cell}
||
||

_title_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Локализованное название требования

_Example:_{.json-schema-reset .json-schema-example} `Тип кузова`
{.table-cell}
||
||

_type_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [SelectType](#entity-SelectType)

Тип выбора: одиночный или множественный


_Enum:_{.json-schema-reset .json-schema-value} `select`, `multi_select`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "name": "cargo_type",
  "title": "Тип кузова",
  "text": "Требование габаритов транспортного средства",
  "type": "select",
  "required": false,
  "options": [
    {
      "title": "Маленький кузов",
      "text": "170 см в длину, 100 в ширину, 90 в высоту",
      "value": "van"
    }
  ]
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### BoolRequirement {#entity-BoolRequirement}

Требование формата "да/нет"

#|
|| **Name** | **Description** ||
||

_default_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: boolean

Значение по умолчанию
{.table-cell}
||
||

_name_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тип требования

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_required_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: boolean

Поле обязательно выбрать
{.table-cell}
||
||

_text_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Локализованое описание типа требования

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_title_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Локализованое название типа требования

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_type_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тип выбора: да или нет


_Const:_{.json-schema-reset .json-schema-value} `bool`

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "name": "example",
  "title": "example",
  "text": "example",
  "type": "bool",
  "default": true,
  "required": true
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### TariffRequirement {#entity-TariffRequirement}

{% cut "**One of 2 types**" %}{.json-schema-combinators data-marker=or}

- **Type**: [SelectRequirement](#entity-SelectRequirement)

  Требование с выбором из нескольких вариантов

  {% cut "**Example**" %}{.json-schema-example}

  ```json translate=no
  {
    "name": "cargo_type",
    "title": "Тип кузова",
    "text": "Требование габаритов транспортного средства",
    "type": "select",
    "required": false,
    "options": [
      {
        "title": "Маленький кузов",
        "text": "170 см в длину, 100 в ширину, 90 в высоту",
        "value": "van"
      }
    ]
  }
  ```

  {% endcut %}

- **Type**: [BoolRequirement](#entity-BoolRequirement)

  Требование формата "да/нет"

  {% cut "**Example**" %}{.json-schema-example}

  ```json translate=no
  {
    "name": "example",
    "title": "example",
    "text": "example",
    "type": "bool",
    "default": true,
    "required": true
  }
  ```

  {% endcut %}

{% endcut %}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "name": "cargo_type",
  "title": "Тип кузова",
  "text": "Требование габаритов транспортного средства",
  "type": "select",
  "required": false,
  "options": [
    {
      "title": "Маленький кузов",
      "text": "170 см в длину, 100 в ширину, 90 в высоту",
      "value": "van"
    }
  ]
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### DeliveryOption {#entity-DeliveryOption}

#|
|| **Name** | **Description** ||
||

_description_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Локализованное описание

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "description": "example"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### B2BTariff {#entity-B2BTariff}

#|
|| **Name** | **Description** ||
||

_minimal_price_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: number

Минимальная стоимость
{.table-cell}
||
||

_name_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [Tariff](#entity-Tariff)

Тариф

_Example:_{.json-schema-reset .json-schema-example} `cargo`
{.table-cell}
||
||

_supported_requirements_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [TariffRequirement](#entity-TariffRequirement)[]

Поддерживаемые требования к доставке

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "name": "cargo_type",
    "title": "Тип кузова",
    "text": "Требование габаритов транспортного средства",
    "type": "select",
    "required": false,
    "options": [
      {
        "title": "Маленький кузов",
        "text": "170 см в длину, 100 в ширину, 90 в высоту",
        "value": "van"
      }
    ]
  }
]
```

{% endcut %}
{.table-cell}
||
||

_text_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание тарифа

_Example:_{.json-schema-reset .json-schema-example} `Тариф экспресс`
{.table-cell}
||
||

_title_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Название тарифа

_Example:_{.json-schema-reset .json-schema-example} `Экспресс`
{.table-cell}
||
||

_delivery_options_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [DeliveryOption](#entity-DeliveryOption)[]

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "description": "example"
  }
]
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "name": "cargo",
  "title": "Экспресс",
  "text": "Тариф экспресс",
  "minimal_price": 213,
  "supported_requirements": [
    {
      "name": "cargo_type",
      "title": "Тип кузова",
      "text": "Требование габаритов транспортного средства",
      "type": "select",
      "required": false,
      "options": [
        {}
      ]
    }
  ],
  "delivery_options": [
    {
      "description": "example"
    }
  ]
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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `bad_request`, `address_not_found`
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

</div>

[*Deprecated]: No longer supported, please use an alternative and newer version.