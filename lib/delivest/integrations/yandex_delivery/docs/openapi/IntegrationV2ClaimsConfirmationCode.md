---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2ClaimsConfirmationCode.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsConfirmationCode.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsConfirmationCode.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Код подтверждения

<!-- markdownlint-disable-file -->

Метод возвращает код подтверждения в текущей точке (если код доступен).

## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/confirmation_code
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
  "claim_id": "741cedf82cd464fa6fa16d87155c636"
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_claim_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [ClaimId](#entity-ClaimId)

Идентификатор(ID) заявки, полученный на этапе создания заявки

_Min length:_{.json-schema-reset .json-schema-assertion} `32`

_Max length:_{.json-schema-reset .json-schema-assertion} `64`

_Example:_{.json-schema-reset .json-schema-example} `741cedf82cd464fa6fa16d87155c636`
{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### ClaimId {#entity-ClaimId}

Идентификатор(ID) заявки, полученный на этапе создания заявки

**Type**: string

_Min length:_{.json-schema-reset .json-schema-assertion} `32`

_Max length:_{.json-schema-reset .json-schema-assertion} `64`

_Example:_{.json-schema-reset .json-schema-example} `741cedf82cd464fa6fa16d87155c636`

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
  "code": "2000",
  "attempts": 1
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_attempts_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Количество оставшихся попыток ввода кода (int64)
{.table-cell}
||
||

_code_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Код подтверждения

_Example:_{.json-schema-reset .json-schema-example} `2000`
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

<div class="openapi__response__code__404">

## 404 Not Found

Заявка не найдена или выдача кода подтверждения через API запрещена.

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