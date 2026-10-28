---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV1RobotHandoverInfo.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV1RobotHandoverInfo.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Получение состояний обмена роботом

<!-- markdownlint-disable-file -->

Возвращает состояния обмена заказом роботом доставщиком на точках маршрута.

На основе ответа можно определить:
- состояние обмена на каждой точке маршрута
- требуется ли подтверждение завершения обмена на каждой точке маршрута
- номер секции в отсеке робота, если они есть


## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v1/robot/handover/info
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

## Responses

<div class="openapi__response__code__200">

## 200 OK

success

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "handovers": [
    {
      "type": "with_confirmation",
      "status": "pending",
      "section": 1,
      "claim_point_id": 372036854775807
    }
  ]
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_handovers_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [HandoverInfoItem](#entity-HandoverInfoItem)[]

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "type": "with_confirmation",
    "status": "pending",
    "section": 1,
    "claim_point_id": 372036854775807
  }
]
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### HandoverType {#entity-HandoverType}

Тип обмена заказом с роботом

- with_confirmation - с подтверждением завершения обмена
- without_confirmation - без подтверждения завершения обмена,
(при зарытии крышки обмен считается завершенным)


**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `with_confirmation`, `without_confirmation`

</div>

<div class="openapi-entity">

### HandoverStatus {#entity-HandoverStatus}

**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `pending`, `ready`, `initializing`, `exchanging`, `finishing`, `completed`, `skipped`

</div>

<div class="openapi-entity">

### ClaimPointId {#entity-ClaimPointId}

Целочисленный идентификатор точки (int64), генерируемый
на стороне Яндекс Доставки.
Содержится в поле route_points[].id. Применимо к точкам с типом
source, destination, return.


**Type**: integer

</div>

<div class="openapi-entity">

### HandoverInfoItem {#entity-HandoverInfoItem}

#|
|| **Name** | **Description** ||
||

_status_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [HandoverStatus](#entity-HandoverStatus)

_Enum:_{.json-schema-reset .json-schema-value} `pending`, `ready`, `initializing`, `exchanging`, `finishing`, `completed`, `skipped`
{.table-cell}
||
||

_type_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [HandoverType](#entity-HandoverType)

Тип обмена заказом с роботом

- with_confirmation - с подтверждением завершения обмена
- without_confirmation - без подтверждения завершения обмена,
(при зарытии крышки обмен считается завершенным)


_Enum:_{.json-schema-reset .json-schema-value} `with_confirmation`, `without_confirmation`
{.table-cell}
||
||

_claim_point_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ClaimPointId](#entity-ClaimPointId)

Целочисленный идентификатор точки (int64), генерируемый
на стороне Яндекс Доставки.
Содержится в поле route_points[].id. Применимо к точкам с типом
source, destination, return.


_Example:_{.json-schema-reset .json-schema-example} `372036854775807`
{.table-cell}
||
||

_section_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: integer

Номер секции в отсеке робота.
Если значение null - значит у робота только один отсек
без разделителей.

{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "type": "with_confirmation",
  "status": "pending",
  "section": 1,
  "claim_point_id": 372036854775807
}
```

{% endcut %}

</div>

</div>

<div class="openapi__response__code__400">

## 400 Bad Request

Некорректный запрос

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "state_mismatch",
  "message": "State mismatch error"
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

_Example:_{.json-schema-reset .json-schema-example} `state_mismatch`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание ошибки

_Example:_{.json-schema-reset .json-schema-example} `State mismatch error`
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

<div class="openapi__response__code__404">

## 404 Not Found

Заявка не найдена

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "state_mismatch",
  "message": "State mismatch error"
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

_Example:_{.json-schema-reset .json-schema-example} `state_mismatch`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание ошибки

_Example:_{.json-schema-reset .json-schema-example} `State mismatch error`
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

</div>

[*Deprecated]: No longer supported, please use an alternative and newer version.