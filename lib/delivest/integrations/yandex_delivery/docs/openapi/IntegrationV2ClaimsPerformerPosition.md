---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2ClaimsPerformerPosition.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsPerformerPosition.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsPerformerPosition.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Местоположение курьера

<!-- markdownlint-disable-file -->

Метод возвращает координаты, скорость и направления движения курьера заявки.

## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-get);margin-bottom: 12px">

<div class="openapi__request">

GET {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/performer-position
```

</div>

Адрес сервиса

</div>

</div>

### Query parameters

#|
|| **Name** | **Description** ||
||

_claim_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

ID заявки, полученный на этапе создания заявки

_Min length:_{.json-schema-reset .json-schema-assertion} `32`

_Max length:_{.json-schema-reset .json-schema-assertion} `64`

_Example:_{.json-schema-reset .json-schema-example} ``
{.table-cell}
||
|#{.json-schema-properties}

## Responses

<div class="openapi__response__code__200">

## 200 OK

Информация о местоположении курьера

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "position": {
    "lat": -90,
    "lon": -180,
    "timestamp": 0,
    "accuracy": 0.5,
    "speed": 0.5,
    "direction": 0.5
  },
  "route_points": [
    {
      "id": 1,
      "type": "source",
      "visit_order": 1,
      "sharing_link": "example"
    }
  ]
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_position_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
{% cut "**Type**: object" %}

#|
||

_lat_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: number

Широта

_Min value:_{.json-schema-reset .json-schema-assertion} `-90`

_Max value:_{.json-schema-reset .json-schema-assertion} `90`
{.table-cell}
||
||

_lon_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: number

Долгота

_Min value:_{.json-schema-reset .json-schema-assertion} `-180`

_Max value:_{.json-schema-reset .json-schema-assertion} `180`
{.table-cell}
||
||

_timestamp_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Время снятия сигнала GPS, unix-time
{.table-cell}
||
||

_accuracy_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: number

Точность GPS. Пока запрещена к передаче т.к. не решили
с единицами измерения.

{.table-cell}
||
||

_direction_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: number

Направление. Угол от 0 градусов до 360 градусов от направления на север,
по часовой стрелке. 0 - север, 90 - восток, 180 - юг,
270 - запад.

{.table-cell}
||
||

_speed_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: number

Средняя скорость, в м/с
{.table-cell}
||
|#{.json-schema-properties}

{% endcut %}

Расширенный формат геопозиции курьера

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "lat": -90,
  "lon": -180,
  "timestamp": 0,
  "accuracy": 0.5,
  "speed": 0.5,
  "direction": 0.5
}
```

{% endcut %}
{.table-cell}
||
||

_route_points_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [PointWithSharingLink](#entity-PointWithSharingLink)[]

Точки маршрута со ссылками на отслеживание

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "id": 1,
    "type": "source",
    "visit_order": 1,
    "sharing_link": "example"
  }
]
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### PointType {#entity-PointType}

Тип точки:
  - source - точка отправления, где курьер забирает товар
  - destination – точки назначения, где курьер передает товар
  - return - точка возврата товара (добавляется автоматически и по умолчанию совпадает с точкой отправления, но также можно определить другую точку)


**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `source`, `destination`, `return`

</div>

<div class="openapi-entity">

### PointWithSharingLink {#entity-PointWithSharingLink}

#|
|| **Name** | **Description** ||
||

_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Целочисленный идентификатор точки (int64)
{.table-cell}
||
||

_type_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [PointType](#entity-PointType)

Тип точки:
  - source - точка отправления, где курьер забирает товар
  - destination – точки назначения, где курьер передает товар
  - return - точка возврата товара (добавляется автоматически и по умолчанию совпадает с точкой отправления, но также можно определить другую точку)


_Enum:_{.json-schema-reset .json-schema-value} `source`, `destination`, `return`
{.table-cell}
||
||

_visit_order_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Порядок посещения точки (нумерация начинается с 1) (int64)
{.table-cell}
||
||

_sharing_link_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Ссылка для отслеживания маршрута. Доступна
только для точек с типом 'destination'


_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "id": 1,
  "type": "source",
  "visit_order": 1,
  "sharing_link": "example"
}
```

{% endcut %}

</div>

</div>

<div class="openapi__response__code__404">

## 404 Not Found

Исполнитель или местоположение курьера не найдены

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "not_found",
  "message": "Заявка не найдена"
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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `not_found`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание ошибки

_Example:_{.json-schema-reset .json-schema-example} `Заявка не найдена`
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

<div class="openapi__response__code__409">

## 409 Conflict

Заявка в неактивном статусе или нет информации об исполнителе


<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "inappropriate_status",
  "message": "Недопустимое действие над заявкой"
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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `unknown_performer_position`, `inappropriate_status`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание ошибки

_Example:_{.json-schema-reset .json-schema-example} `Недопустимое действие над заявкой`
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