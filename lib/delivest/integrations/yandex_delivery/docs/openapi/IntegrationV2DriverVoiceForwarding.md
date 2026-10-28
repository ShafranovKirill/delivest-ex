---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2DriverVoiceForwarding.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2DriverVoiceForwarding.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2DriverVoiceForwarding.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Телефон курьера

<!-- markdownlint-disable-file -->

Возвращает номер телефона для звонка курьера, который выполняет
заявку в настоящий момент.


## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/driver-voiceforwarding
```

</div>

Адрес сервиса

</div>

</div>

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "claim_id": "example",
  "point_id": 372036854775807
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_claim_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Идентификатор заявки, полученный на этапе создания заявки

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_point_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ClaimPointId](#entity-ClaimPointId)

Идентификатор точки, с которой хочет позвонить контакт

Целочисленный идентификатор точки (int64), генерируемый
на стороне Яндекс Доставки.
Содержится в поле route_points[].id. Применимо к точкам с типом
source, destination, return.


_Example:_{.json-schema-reset .json-schema-example} `372036854775807`
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

OK

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "phone": "+79099999998",
  "ext": "0163",
  "ttl_seconds": 2088
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_ext_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Добавочный номер

_Example:_{.json-schema-reset .json-schema-example} `0163`
{.table-cell}
||
||

_phone_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Номер телефона

_Example:_{.json-schema-reset .json-schema-example} `+79099999998`
{.table-cell}
||
||

_ttl_seconds_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Время, в течение которого этот номер действителен (int64)
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

<div class="openapi__response__code__400">

## 400 Bad Request

Некорректный телефон

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "invalid_point_phone",
  "message": "Некорректный номер"
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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `invalid_point_phone`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание ошибки

_Example:_{.json-schema-reset .json-schema-example} `Некорректный номер`
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

<div class="openapi__response__code__404">

## 404 Not Found

Заявка или исполнитель заказа не найдены

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

Заказ завершен

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