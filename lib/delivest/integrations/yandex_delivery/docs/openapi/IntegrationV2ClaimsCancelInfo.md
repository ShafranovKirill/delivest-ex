---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2ClaimsCancelInfo.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCancelInfo.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCancelInfo.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Условия отмены

<!-- markdownlint-disable-file -->

Метод возвращает информацию о возможности отмены.
Используйте этот метод для получения информации по заявке, созданной через [claims/create](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCreate.md).


## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/cancel-info
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

OK

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "cancel_state": "free",
  "price": "12.50",
  "price_with_vat": null,
  "currency": "RUB"
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_cancel_state_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [CancelInfoCancelState](#entity-CancelInfoCancelState)

Условия отмены

_Enum:_{.json-schema-reset .json-schema-value} `free`, `paid`, `unavailable`
{.table-cell}
||
||

_currency_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Валюта, в которой ведется расчет

_Example:_{.json-schema-reset .json-schema-example} `RUB`
{.table-cell}
||
||

_price_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Money](#entity-Money)

Стоимость доставки в формате десятичной дроби Decimal(18, 4)

_Pattern:_{.json-schema-reset .json-schema-assertion} `^-?[0-9]{1,14}(\.[0-9]{0,4})?$`

_Example:_{.json-schema-reset .json-schema-example} `12.50`
{.table-cell}
||
||

_price_with_vat_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Money](#entity-Money)

Стоимость доставки в формате десятичной дроби Decimal(18, 4)

_Pattern:_{.json-schema-reset .json-schema-assertion} `^-?[0-9]{1,14}(\.[0-9]{0,4})?$`

_Example:_{.json-schema-reset .json-schema-example} `12.50`
{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### CancelInfoCancelState {#entity-CancelInfoCancelState}

Условия отмены

**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `free`, `paid`, `unavailable`

</div>

<div class="openapi-entity">

### Money {#entity-Money}

Стоимость доставки в формате десятичной дроби Decimal(18, 4)

**Type**: string

_Pattern:_{.json-schema-reset .json-schema-assertion} `^-?[0-9]{1,14}(\.[0-9]{0,4})?$`

_Example:_{.json-schema-reset .json-schema-example} `12.50`

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
  "code": "bad_request",
  "message": "Неправильное тело запроса"
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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `bad_request`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание ошибки

_Example:_{.json-schema-reset .json-schema-example} `Неправильное тело запроса`
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

</div>

[*Deprecated]: No longer supported, please use an alternative and newer version.