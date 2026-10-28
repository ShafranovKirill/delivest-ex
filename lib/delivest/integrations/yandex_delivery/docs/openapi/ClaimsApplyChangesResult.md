---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/ClaimsApplyChangesResult.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/ClaimsApplyChangesResult.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/ClaimsApplyChangesResult.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Редактирование заявки после подтверждения

<!-- markdownlint-disable-file -->

Метод возвращает ответ о статусе изменений, запрошенных через метод [claims/apply-changes/request](https://yandex.com/support/delivery-profile/ru/api/express/openapi/ClaimsApplyChangesRequest.md).


## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/apply-changes/result
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
||

_request_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Уникальный идентификатор запроса на редактирование (токен идемпотентности)

_Min length:_{.json-schema-reset .json-schema-assertion} `1`

_Max length:_{.json-schema-reset .json-schema-assertion} `63`

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
  "changes": [
    {
      "id": 0,
      "kind": "example",
      "status": "new",
      "error": {
        "code": "apply_change_error",
        "message": "State mismatch error",
        "details": "bad item at pos 2"
      }
    }
  ]
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_changes_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [ChangeResponse](#entity-ChangeResponse)[]

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "id": 0,
    "kind": "example",
    "status": "new",
    "error": {
      "code": "apply_change_error",
      "message": "State mismatch error",
      "details": "bad item at pos 2"
    }
  }
]
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### ChangeStatus {#entity-ChangeStatus}

Статус обработки изменения

**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `new`, `pending`, `applied`, `failed`

</div>

<div class="openapi-entity">

### ErrorWithDetails {#entity-ErrorWithDetails}

Информация об ошибке

#|
|| **Name** | **Description** ||
||

_code_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Код ошибки

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `apply_change_error`, `inappropriate_point`, `invalid_destination_point`, `invalid_item_destination_point`, `invalid_item_source_point`, `invalid_source_point`, `not_allowed`, `invalid_phone_incorrect_symbol`, `invalid_phone_must_start_plus_symbol`, `invalid_phone_size_incorrect`, `country_phone_code_not_supported`, `invalid_post_payment`, `max_order_cost_exceeded`, `cargo_payments_update_error`
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
||

_details_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Нелокализованное сообщение об ошибке

_Example:_{.json-schema-reset .json-schema-example} `bad item at pos 2`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "code": "apply_change_error",
  "message": "State mismatch error",
  "details": "bad item at pos 2"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ChangeResponse {#entity-ChangeResponse}

#|
|| **Name** | **Description** ||
||

_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Уникальный идентификатор изменения (int64)
{.table-cell}
||
||

_kind_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тип изменения

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_status_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [ChangeStatus](#entity-ChangeStatus)

Статус обработки изменения

_Enum:_{.json-schema-reset .json-schema-value} `new`, `pending`, `applied`, `failed`
{.table-cell}
||
||

_error_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ErrorWithDetails](#entity-ErrorWithDetails)

Описание ошибки (для статуса failed)

Информация об ошибке

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "code": "apply_change_error",
  "message": "State mismatch error",
  "details": "bad item at pos 2"
}
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "id": 0,
  "kind": "example",
  "status": "new",
  "error": {
    "code": "apply_change_error",
    "message": "State mismatch error",
    "details": "bad item at pos 2"
  }
}
```

{% endcut %}

</div>

</div>

<div class="openapi__response__code__404">

## 404 Not Found

Изменение не найдено

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