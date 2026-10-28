---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2ClaimsReturn.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsReturn.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsReturn.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Пропуск точки в заявке с мультиточками

<!-- markdownlint-disable-file -->

Метод инициирует возврат заказа курьером в исходную точку отправки. Операция может быть выполнена только в том случае, если курьер уже забрал заказ.
<br>
Если на маршруте несколько точек назначения, то указанная в запросе точка будет пропущена, и в конце маршрута курьер вернет товар обратно отправителю.


## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/return
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

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "point_id": 372036854775807,
  "comment": "Клиент отказался от заказа",
  "need_return_items": true
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_comment_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Причина, по которой точку необходимо пропустить


_Example:_{.json-schema-reset .json-schema-example} `Клиент отказался от заказа`
{.table-cell}
||
||

_point_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [ClaimPointId](#entity-ClaimPointId)

Идентификатор точки, которую необходимо пропустить


Целочисленный идентификатор точки (int64), генерируемый
на стороне Яндекс Доставки.
Содержится в поле route_points[].id. Применимо к точкам с типом
source, destination, return.


_Example:_{.json-schema-reset .json-schema-example} `372036854775807`
{.table-cell}
||
||

_need_return_items_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Вернуть товар в исходную точку отправления

{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### ClaimPointId {#entity-ClaimPointId}

Целочисленный идентификатор точки (int64), генерируемый
на стороне Яндекс Доставки.
Содержится в поле route_points[].id. Применимо к точкам с типом
source, destination, return.


**Type**: integer

</div>

## Responses

<div class="openapi__response__code__200">

## 200 OK

Возврат инициирован

</div>

<div class="openapi__response__code__400">

## 400 Bad Request

Некорректная точка

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "state_mismatch",
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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `state_mismatch`
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

<div class="openapi__response__code__404">

## 404 Not Found

Заявка не найдена

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

Курьер еще не найден, вы можете отменить заявку

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "state_mismatch",
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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `not_allowed`, `state_transition_forbidden`, `state_mismatch`
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

<div class="openapi__response__code__410">

## 410 Gone

Заявка в неактивном статусе

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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `inappropriate_status`
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

</div>

[*Deprecated]: No longer supported, please use an alternative and newer version.