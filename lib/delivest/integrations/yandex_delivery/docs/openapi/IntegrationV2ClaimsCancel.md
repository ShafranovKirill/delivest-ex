---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2ClaimsCancel.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCancel.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCancel.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Отмена заявки

<!-- markdownlint-disable-file -->

Метод отменяет подтвержденную заявку. Отменить заявку с использованием этого метода можно до передачи товара курьеру. Далее отмена заказа возможна только через службу поддержки.
<br>
Отмена заявки может быть платной и бесплатной. Бесплатная отмена доступна до прибытия курьера на точку отправления, платная отмена доступна до начала движения по получению груза курьером. Чтобы узнать тип отмены, используйте операцию получения информации по заявке [claims/cancel-info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCancelInfo.md) (поле cancel_state).
<br>
В случае бесплатной отмены заявка перейдет в статус cancelled, в случае платной отмены - в статус cancelled_with_payment.


## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/cancel
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
  "version": 1,
  "cancel_state": "free"
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_cancel_state_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [CancelState](#entity-CancelState)

Статус отмены (платная или бесплатная)

_Enum:_{.json-schema-reset .json-schema-value} `free`, `paid`
{.table-cell}
||
||

_version_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Версия отменяемой заявки (int64)
{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### CancelState {#entity-CancelState}

Статус отмены (платная или бесплатная)

**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `free`, `paid`

</div>

## Responses

<div class="openapi__response__code__200">

## 200 OK

Заявка отменена

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "id": "741cedf82cd464fa6fa16d87155c636",
  "status": "new",
  "version": 1,
  "user_request_revision": "example",
  "skip_client_notify": true
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [ClaimId](#entity-ClaimId)

Идентификатор(ID) заявки, полученный на этапе создания заявки

_Min length:_{.json-schema-reset .json-schema-assertion} `32`

_Max length:_{.json-schema-reset .json-schema-assertion} `64`

_Example:_{.json-schema-reset .json-schema-example} `741cedf82cd464fa6fa16d87155c636`
{.table-cell}
||
||

_skip_client_notify_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: boolean
{.table-cell}
||
||

_status_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [ClaimStatus](#entity-ClaimStatus)

Статус заявки. Подробнее см. в разделе [Статусная модель](https://yandex.com/support/delivery-profile/ru/api/express/claim-process.md)

_Enum:_{.json-schema-reset .json-schema-value} `new`, `estimating`, `estimating_failed`, `ready_for_approval`, `accepted`, `performer_lookup`, `performer_draft`, `performer_found`, `performer_not_found`, `pickup_arrived`, `ready_for_pickup_confirmation`, `pickuped`, `delivery_arrived`, `ready_for_delivery_confirmation`, `delivered`, `delivered_finish`, `returning`, `return_arrived`, `ready_for_return_confirmation`, `returned`, `returned_finish`, `failed`, `cancelled`, `cancelled_with_payment`, `cancelled_by_taxi`, `cancelled_with_items_on_hands`
{.table-cell}
||
||

_user_request_revision_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Текущая версия изменений в заявке, переданная пользователем

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_version_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Версия заявки из запроса (int64)
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

<div class="openapi-entity">

### ClaimStatus {#entity-ClaimStatus}

Статус заявки. Подробнее см. в разделе [Статусная модель](https://yandex.com/support/delivery-profile/ru/api/express/claim-process.md)

**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `new`, `estimating`, `estimating_failed`, `ready_for_approval`, `accepted`, `performer_lookup`, `performer_draft`, `performer_found`, `performer_not_found`, `pickup_arrived`, `ready_for_pickup_confirmation`, `pickuped`, `delivery_arrived`, `ready_for_delivery_confirmation`, `delivered`, `delivered_finish`, `returning`, `return_arrived`, `ready_for_return_confirmation`, `returned`, `returned_finish`, `failed`, `cancelled`, `cancelled_with_payment`, `cancelled_by_taxi`, `cancelled_with_items_on_hands`

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

<div class="openapi__response__code__409">

## 409 Conflict

Попытка отменить неактуальную версию заявки

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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `inappropriate_status`, `free_cancel_is_unavailable`, `state_mismatch`
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