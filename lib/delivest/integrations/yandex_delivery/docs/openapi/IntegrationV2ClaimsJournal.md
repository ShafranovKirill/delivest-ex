---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2ClaimsJournal.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsJournal.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsJournal.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Журнал изменений

<!-- markdownlint-disable-file -->

Метод возвращает историю изменения заявки. Вы можете узнать об изменении статусов и цены заказа. Для терминальных статусов возвращается поле resolution, возможные значения success, failed.

## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/journal
```

</div>

Адрес сервиса

</div>

</div>

### Query parameters

#|
|| **Name** | **Description** ||
||

_limit_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: integer

Максимальное количество возвращаемых записей

_Default:_{.json-schema-reset .json-schema-value} `1000`

_Min value:_{.json-schema-reset .json-schema-assertion} `1`

_Max value:_{.json-schema-reset .json-schema-assertion} `1000`
{.table-cell}
||
|#{.json-schema-properties}

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "cursor": "example"
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_cursor_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Строка с идентификатором последнего
изменения. Если cursor
не передан, то будут выданы все изменения
с некоторым лимитом


_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
|#{.json-schema-properties}

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
  "cursor": "example",
  "events": [
    {
      "operation_id": 1,
      "claim_id": "3b8d1af142664fde824626a7c19e2bd9",
      "change_type": "status_changed",
      "updated_ts": "2020-01-01T00:00:00+00:00",
      "new_status": "new",
      "new_price": "20.00",
      "new_currency": "RUB",
      "resolution": "success",
      "revision": 1,
      "client_id": "95d010b2471041499b8cb1bfa282692f",
      "current_point_id": 372036854775807
    }
  ]
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_cursor_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Идентификатор последнего изменения

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_events_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [Event](#entity-Event)[]

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "operation_id": 1,
    "claim_id": "3b8d1af142664fde824626a7c19e2bd9",
    "change_type": "status_changed",
    "updated_ts": "2020-01-01T00:00:00+00:00",
    "new_status": "new",
    "new_price": "20.00",
    "new_currency": "RUB",
    "resolution": "success",
    "revision": 1,
    "client_id": "95d010b2471041499b8cb1bfa282692f",
    "current_point_id": 372036854775807
  }
]
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### ClaimStatus {#entity-ClaimStatus}

Статус заявки. Подробнее см. в разделе [Статусная модель](https://yandex.com/support/delivery-profile/ru/api/express/claim-process.md)

**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `new`, `estimating`, `estimating_failed`, `ready_for_approval`, `accepted`, `performer_lookup`, `performer_draft`, `performer_found`, `performer_not_found`, `pickup_arrived`, `ready_for_pickup_confirmation`, `pickuped`, `delivery_arrived`, `ready_for_delivery_confirmation`, `delivered`, `delivered_finish`, `returning`, `return_arrived`, `ready_for_return_confirmation`, `returned`, `returned_finish`, `failed`, `cancelled`, `cancelled_with_payment`, `cancelled_by_taxi`, `cancelled_with_items_on_hands`

</div>

<div class="openapi-entity">

### ClaimStatusResolution {#entity-ClaimStatusResolution}

Резолюция терминального статуса

**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `success`, `failed`

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

### Event {#entity-Event}

Информация об изменении заказа

#|
|| **Name** | **Description** ||
||

_change_type_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тип изменения. Возможные значения:
- status_changed — изменение статуса; 
- price_changed — изменение цены.


_Example:_{.json-schema-reset .json-schema-example} `status_changed`
{.table-cell}
||
||

_claim_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Идентификатор заявки claim_id

_Example:_{.json-schema-reset .json-schema-example} `3b8d1af142664fde824626a7c19e2bd9`
{.table-cell}
||
||

_operation_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Идентификатор операции (int64)
{.table-cell}
||
||

_revision_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Версия изменения заявки (int64)
{.table-cell}
||
||

_updated_ts_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Время события в формате ISO 8601

_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T00:00:00+00:00`
{.table-cell}
||
||

_client_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Идентификатор клиента

_Example:_{.json-schema-reset .json-schema-example} `95d010b2471041499b8cb1bfa282692f`
{.table-cell}
||
||

_current_point_id_{.json-schema-reset .json-schema-property}
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

_new_currency_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Код валюты заказа

_Example:_{.json-schema-reset .json-schema-example} `RUB`
{.table-cell}
||
||

_new_price_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Цена заказа

_Example:_{.json-schema-reset .json-schema-example} `20.00`
{.table-cell}
||
||

_new_status_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ClaimStatus](#entity-ClaimStatus)

Статус заявки. Подробнее см. в разделе [Статусная модель](https://yandex.com/support/delivery-profile/ru/api/express/claim-process.md)

_Enum:_{.json-schema-reset .json-schema-value} `new`, `estimating`, `estimating_failed`, `ready_for_approval`, `accepted`, `performer_lookup`, `performer_draft`, `performer_found`, `performer_not_found`, `pickup_arrived`, `ready_for_pickup_confirmation`, `pickuped`, `delivery_arrived`, `ready_for_delivery_confirmation`, `delivered`, `delivered_finish`, `returning`, `return_arrived`, `ready_for_return_confirmation`, `returned`, `returned_finish`, `failed`, `cancelled`, `cancelled_with_payment`, `cancelled_by_taxi`, `cancelled_with_items_on_hands`
{.table-cell}
||
||

_resolution_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ClaimStatusResolution](#entity-ClaimStatusResolution)

Резолюция терминального статуса

_Enum:_{.json-schema-reset .json-schema-value} `success`, `failed`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "operation_id": 1,
  "claim_id": "3b8d1af142664fde824626a7c19e2bd9",
  "change_type": "status_changed",
  "updated_ts": "2020-01-01T00:00:00+00:00",
  "new_status": "new",
  "new_price": "20.00",
  "new_currency": "RUB",
  "resolution": "success",
  "revision": 1,
  "client_id": "95d010b2471041499b8cb1bfa282692f",
  "current_point_id": 372036854775807
}
```

{% endcut %}

</div>

</div>

<div class="openapi__response__code__400">

## 400 Bad Request

BAD REQUEST

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "unknown_error",
  "message": "Неправильный формат cursor"
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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `invalid_cursor`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание ошибки

_Example:_{.json-schema-reset .json-schema-example} `Неправильный формат cursor`
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

<div class="openapi__response__code__429">

## 429 Too Many Requests

TOO MANY REQUESTS

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