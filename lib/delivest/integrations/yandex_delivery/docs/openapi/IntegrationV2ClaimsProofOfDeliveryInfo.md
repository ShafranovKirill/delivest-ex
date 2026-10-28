---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2ClaimsProofOfDeliveryInfo.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsProofOfDeliveryInfo.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsProofOfDeliveryInfo.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Подтверждение доставки

<!-- markdownlint-disable-file -->

Возвращает данные, подтверждающие доставку.

В ответе можно получить идентификаторы точек на маршруте, фотографии, сделанные курьером на этих точках, и имена получателей


## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/proof-of-delivery/info
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
  "proof_of_delivery_info": [
    {
      "claim_point_id": 372036854775807,
      "photos": [
        {
          "id": "123e4567-e89b-12d3-a456-426614174000",
          "claim_point_id": null,
          "url": "example",
          "status": "initiated",
          "external_id": "example"
        }
      ],
      "recipient_info": {
        "recipient_name": "example",
        "recipient_type": "example",
        "document_id": "example"
      }
    }
  ]
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_proof_of_delivery_info_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [ProofOfDeliveryInfo](#entity-ProofOfDeliveryInfo)[]

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "claim_point_id": 372036854775807,
    "photos": [
      {
        "id": "123e4567-e89b-12d3-a456-426614174000",
        "claim_point_id": null,
        "url": "example",
        "status": "initiated",
        "external_id": "example"
      }
    ],
    "recipient_info": {
      "recipient_name": "example",
      "recipient_type": "example",
      "document_id": "example"
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

### ClaimPointId {#entity-ClaimPointId}

Целочисленный идентификатор точки (int64), генерируемый
на стороне Яндекс Доставки.
Содержится в поле route_points[].id. Применимо к точкам с типом
source, destination, return.


**Type**: integer

</div>

<div class="openapi-entity">

### UploadStatusType {#entity-UploadStatusType}

Статус загрузки

**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `initiated`, `uploaded`, `mds_failed`, `validated`, `validation_failed`

</div>

<div class="openapi-entity">

### Photo {#entity-Photo}

Фотографии, подтверждающие доставку

#|
|| **Name** | **Description** ||
||

_claim_point_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [ClaimPointId](#entity-ClaimPointId)

Указание, в какой точке сделана фотография

Целочисленный идентификатор точки (int64), генерируемый
на стороне Яндекс Доставки.
Содержится в поле route_points[].id. Применимо к точкам с типом
source, destination, return.


_Example:_{.json-schema-reset .json-schema-example} `372036854775807`
{.table-cell}
||
||

_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;uuid&gt;

Уникальный идентификатор фотографии.

_Example:_{.json-schema-reset .json-schema-example} `123e4567-e89b-12d3-a456-426614174000`
{.table-cell}
||
||

_status_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [UploadStatusType](#entity-UploadStatusType)

Статус загрузки

_Enum:_{.json-schema-reset .json-schema-value} `initiated`, `uploaded`, `mds_failed`, `validated`, `validation_failed`
{.table-cell}
||
||

_url_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

URL для загрузки фотографий

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_external_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

внешний ID


_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "id": "123e4567-e89b-12d3-a456-426614174000",
  "claim_point_id": 372036854775807,
  "url": "example",
  "status": "initiated",
  "external_id": "example"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### RecipientInfo {#entity-RecipientInfo}

Информация о получателе товара


#|
|| **Name** | **Description** ||
||

_recipient_name_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Имя получателя

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_recipient_type_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Кем является фактический получатель
по отношению к получателю, указанному в заявке


_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_document_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Номер документа, подтверждающего доставку


_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "recipient_name": "example",
  "recipient_type": "example",
  "document_id": "example"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ProofOfDeliveryInfo {#entity-ProofOfDeliveryInfo}

#|
|| **Name** | **Description** ||
||

_claim_point_id_{.json-schema-reset .json-schema-property .json-schema-required}
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

_photos_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Photo](#entity-Photo)[]

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "claim_point_id": 372036854775807,
    "url": "example",
    "status": "initiated",
    "external_id": "example"
  }
]
```

{% endcut %}
{.table-cell}
||
||

_recipient_info_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [RecipientInfo](#entity-RecipientInfo)

Информация о получателе товара


{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "recipient_name": "example",
  "recipient_type": "example",
  "document_id": "example"
}
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "claim_point_id": 372036854775807,
  "photos": [
    {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "claim_point_id": null,
      "url": "example",
      "status": "initiated",
      "external_id": "example"
    }
  ],
  "recipient_info": {
    "recipient_name": "example",
    "recipient_type": "example",
    "document_id": "example"
  }
}
```

{% endcut %}

</div>

</div>

<div class="openapi__response__code__404">

## 404 Not Found

Заявка не найдена или информация по заявке не найдена

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