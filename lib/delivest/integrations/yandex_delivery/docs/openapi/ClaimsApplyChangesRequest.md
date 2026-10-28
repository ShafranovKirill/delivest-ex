---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/ClaimsApplyChangesRequest.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/ClaimsApplyChangesRequest.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/ClaimsApplyChangesRequest.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Редактирование заявки после подтверждения

<!-- markdownlint-disable-file -->

Метод позволяет изменять некоторые параметры заявки после ее подтверждения


## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/apply-changes/request
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

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "last_known_revision": "example",
  "changes": [
    {
      "kind": "change_items",
      "pickup_point_id": 1,
      "dropoff_point_id": 2,
      "items": [
        {}
      ]
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
**Type**: [ChangeRequest](#entity-ChangeRequest)[]

Набор изменений в заявке (применится весь набор или ничего).

_Min items:_{.json-schema-reset .json-schema-assertion} `1`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "kind": "change_items",
    "pickup_point_id": 1,
    "dropoff_point_id": 2,
    "items": [
      {
        "extra_id": "БП-208",
        "pickup_point": 1,
        "dropoff_point": 2,
        "title": "Плюмбус",
        "size": {},
        "weight": 2,
        "cost_value": "2.00",
        "cost_currency": "RUB",
        "quantity": 1,
        "fiscalization": {},
        "age_restricted": false
      }
    ]
  }
]
```

{% endcut %}
{.table-cell}
||
||

_last_known_revision_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Последняя известная клиенту версия заявки (version, полученная из [claims/info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md))

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
|#{.json-schema-properties}

</div>

<div class="openapi-entity">

### CargoItemSizes {#entity-CargoItemSizes}

Габариты товара в метрах. В полях следует передавать актуальные значения.

Если габариты не были переданы, заказ оформляется с учетом
максимально допустимых габаритов для выбранного тарифа.

Если фактические характеристики товара превысят допустимые,
курьер вправе отказаться от выполнения такого заказа на месте.
В этом случае будет удержана стоимость подачи.

Курьер (courier): до 0.80 м × 0.50 м × 0.50 м
Экспресс (express): до 1.00 м × 0.60 м × 0.50 м
Грузовой (cargo):
- Маленький кузов: до 1.70 м × 0.96 м × 0.90 м
- Средний кузов: до 2.60 м × 1.30 м × 1.50 м
- Большой кузов: до 3.80 м × 1.80 м × 1.80 м


#|
|| **Name** | **Description** ||
||

_height_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: number

Высота в метрах

_Min value:_{.json-schema-reset .json-schema-assertion} `0`

_Max value:_{.json-schema-reset .json-schema-assertion} `500`
{.table-cell}
||
||

_length_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: number

Длина в метрах

_Min value:_{.json-schema-reset .json-schema-assertion} `0`

_Max value:_{.json-schema-reset .json-schema-assertion} `500`
{.table-cell}
||
||

_width_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: number

Ширина в метрах

_Min value:_{.json-schema-reset .json-schema-assertion} `0`

_Max value:_{.json-schema-reset .json-schema-assertion} `500`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "length": 0.1,
  "width": 0.2,
  "height": 0.3
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### Currency {#entity-Currency}

Трехзначный код валюты, в которой ведется расчет

**Type**: string

_Min length:_{.json-schema-reset .json-schema-assertion} `3`

_Max length:_{.json-schema-reset .json-schema-assertion} `3`

_Example:_{.json-schema-reset .json-schema-example} `RUB`

</div>

<div class="openapi-entity">

### Money {#entity-Money}

Стоимость доставки в формате десятичной дроби Decimal(18, 4)

**Type**: string

_Pattern:_{.json-schema-reset .json-schema-assertion} `^-?[0-9]{1,14}(\.[0-9]{0,4})?$`

_Example:_{.json-schema-reset .json-schema-example} `12.50`

</div>

<div class="openapi-entity">

### VatCodeStrApi {#entity-VatCodeStrApi}

Ставка НДС. Возможные значения:
vat_none - без НДС;
vat0 - нулевая ставка НДС (применяется в редких случаях);
vat10 - ставка НДС 10%;
vat20 - ставка НДС 20%.


**Type**: string

_Example:_{.json-schema-reset .json-schema-example} `vat_none`

</div>

<div class="openapi-entity">

### SupplierInn {#entity-SupplierInn}

ИНН поставщика (10 или 12 цифр). 

**Type**: string

_Pattern:_{.json-schema-reset .json-schema-assertion} `^[A-Z0-9\\-]+$`

_Example:_{.json-schema-reset .json-schema-example} `3664069397`

</div>

<div class="openapi-entity">

### ItemArticle {#entity-ItemArticle}

Артикул товара.
Должен быть уникальным для товаров, передаваемых из одной точки.


**Type**: string

_Example:_{.json-schema-reset .json-schema-example} `20ML50OWKY4FC86`

</div>

<div class="openapi-entity">

### ItemMark {#entity-ItemMark}

Уникальный код товара (КИЗ). Актуален для РФ.
Если товары имеют уникальный код, то на каждый товар необходимо создать отдельный блок


#|
|| **Name** | **Description** ||
||

_code_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Код маркировки товара в соответствии с форматом kind


_Example:_{.json-schema-reset .json-schema-example} `444D00000000003741`
{.table-cell}
||
||

_kind_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тип маркировки.
Возможные значения:
  1. compiled - уже разобранная марка с выделенным GTIN и Serial.
    Пример:
    - 444D00000000003741
  2. gs1_data_matrix_base64 - код товара в формате GS1 Data Matrix,
   подлежащий маркировке средствами идентификации.
   Максимум 200 символов.
   Код товара необходимо передавать целиком,
   закодировав строку в формат base64.


_Example:_{.json-schema-reset .json-schema-example} `gs1_data_matrix_base64`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "kind": "gs1_data_matrix_base64",
  "code": "444D00000000003741"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ItemType {#entity-ItemType}

Тип наименования: товар или услуга.
Значение по умолчанию: product


**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `product`, `service`

</div>

<div class="openapi-entity">

### ItemFiscalization {#entity-ItemFiscalization}

Информация по фискализации (актуально для оплаты при получении)

#|
|| **Name** | **Description** ||
||

_article_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ItemArticle](#entity-ItemArticle)

Артикул товара.
Должен быть уникальным для товаров, передаваемых из одной точки.


_Example:_{.json-schema-reset .json-schema-example} `20ML50OWKY4FC86`
{.table-cell}
||
||

_excise_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Money](#entity-Money)

Сумма акциза

Стоимость доставки в формате десятичной дроби Decimal(18, 4)

_Pattern:_{.json-schema-reset .json-schema-assertion} `^-?[0-9]{1,14}(\.[0-9]{0,4})?$`

_Example:_{.json-schema-reset .json-schema-example} `12.50`
{.table-cell}
||
||

_item_type_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ItemType](#entity-ItemType)

Тип наименования: товар или услуга.
Значение по умолчанию: product


_Enum:_{.json-schema-reset .json-schema-value} `product`, `service`
{.table-cell}
||
||

_mark_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ItemMark](#entity-ItemMark)

Уникальный код товара (КИЗ). Актуален для РФ.
Если товары имеют уникальный код, то на каждый товар необходимо создать отдельный блок


{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "kind": "gs1_data_matrix_base64",
  "code": "444D00000000003741"
}
```

{% endcut %}
{.table-cell}
||
||

_supplier_inn_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [SupplierInn](#entity-SupplierInn)

ИНН поставщика (10 или 12 цифр). 

_Pattern:_{.json-schema-reset .json-schema-assertion} `^[A-Z0-9\\-]+$`

_Example:_{.json-schema-reset .json-schema-example} `3664069397`
{.table-cell}
||
||

_vat_code_str_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [VatCodeStrApi](#entity-VatCodeStrApi)

Ставка НДС. Возможные значения:
vat_none - без НДС;
vat0 - нулевая ставка НДС (применяется в редких случаях);
vat10 - ставка НДС 10%;
vat20 - ставка НДС 20%.


_Example:_{.json-schema-reset .json-schema-example} `vat_none`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "excise": "12.50",
  "vat_code_str": "vat_none",
  "supplier_inn": "3664069397",
  "article": "20ML50OWKY4FC86",
  "mark": {
    "kind": "gs1_data_matrix_base64",
    "code": "444D00000000003741"
  },
  "item_type": "product"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### V2CargoItem {#entity-V2CargoItem}

#|
|| **Name** | **Description** ||
||

_cost_currency_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [Currency](#entity-Currency)

Трехзначный код валюты, в которой ведется расчет

_Min length:_{.json-schema-reset .json-schema-assertion} `3`

_Max length:_{.json-schema-reset .json-schema-assertion} `3`

_Example:_{.json-schema-reset .json-schema-example} `RUB`
{.table-cell}
||
||

_cost_value_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Цена за единицу товара в валюте cost_currency.
Для страхования стоимости передайте фактическую цену груза


_Pattern:_{.json-schema-reset .json-schema-assertion} `^[0-9]+(\.[0-9]{1,2})?$`

_Example:_{.json-schema-reset .json-schema-example} `2.00`
{.table-cell}
||
||

_dropoff_point_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Идентификатор точки (int64), куда нужно доставить
товар. Отличается от идентификатора в заявке.

Может быть любым числом. Должен соответствовать значению route_points[].point_id
у точки назначения

{.table-cell}
||
||

_pickup_point_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Идентификатор точки (int64), откуда нужно забрать
товар. Отличается от идентификатора в заявке.

Может быть любым числом. Должен соответствовать значению route_points[].point_id
у точки отправки

{.table-cell}
||
||

_quantity_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Количество товара в единицах (int64)

_Min value:_{.json-schema-reset .json-schema-assertion} `1`
{.table-cell}
||
||

_title_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Наименование единицы товара

_Example:_{.json-schema-reset .json-schema-example} `Плюмбус`
{.table-cell}
||
||

_age_restricted_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Нужно ли проверить возраст клиента при выдаче товара

_Default:_{.json-schema-reset .json-schema-value} `false`
{.table-cell}
||
||

_extra_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Краткий уникальный идентификатор товара (номер заказа в рамках заявки, как правило идентичен external_order_id)

_Example:_{.json-schema-reset .json-schema-example} `БП-208`
{.table-cell}
||
||

_fiscalization_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ItemFiscalization](#entity-ItemFiscalization)

Информация по фискализации (актуально для оплаты при получении)

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "excise": "12.50",
  "vat_code_str": "vat_none",
  "supplier_inn": "3664069397",
  "article": "20ML50OWKY4FC86",
  "mark": {
    "kind": "gs1_data_matrix_base64",
    "code": "444D00000000003741"
  },
  "item_type": "product"
}
```

{% endcut %}
{.table-cell}
||
||

_size_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CargoItemSizes](#entity-CargoItemSizes)

Габариты товара в метрах. В полях следует передавать актуальные значения.

Если габариты не были переданы, заказ оформляется с учетом
максимально допустимых габаритов для выбранного тарифа.

Если фактические характеристики товара превысят допустимые,
курьер вправе отказаться от выполнения такого заказа на месте.
В этом случае будет удержана стоимость подачи.

Курьер (courier): до 0.80 м × 0.50 м × 0.50 м
Экспресс (express): до 1.00 м × 0.60 м × 0.50 м
Грузовой (cargo):
- Маленький кузов: до 1.70 м × 0.96 м × 0.90 м
- Средний кузов: до 2.60 м × 1.30 м × 1.50 м
- Большой кузов: до 3.80 м × 1.80 м × 1.80 м


{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "length": 0.1,
  "width": 0.2,
  "height": 0.3
}
```

{% endcut %}
{.table-cell}
||
||

_weight_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: number

Вес единицы товара в кг. В поле следует передавать актуальные значения.

Если вес не был передан, заказ оформляется с учетом
максимально допустимых габаритов для выбранного тарифа.

Если фактические характеристики товара превысят допустимые,
курьер вправе отказаться от выполнения такого заказа на месте.
В этом случае будет удержана стоимость подачи.

Курьер (courier): до 10 кг
Экспресс (express): до 20 кг
Грузовой (cargo):
- Маленький кузов: до 300 кг
- Средний кузов: до 700 кг
- Большой кузов: до 1400 кг

{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "extra_id": "БП-208",
  "pickup_point": 1,
  "dropoff_point": 2,
  "title": "Плюмбус",
  "size": {
    "length": 0.1,
    "width": 0.2,
    "height": 0.3
  },
  "weight": 2,
  "cost_value": "2.00",
  "cost_currency": "RUB",
  "quantity": 1,
  "fiscalization": {
    "excise": "12.50",
    "vat_code_str": "vat_none",
    "supplier_inn": "3664069397",
    "article": "20ML50OWKY4FC86",
    "mark": {
      "kind": "gs1_data_matrix_base64",
      "code": "444D00000000003741"
    },
    "item_type": "product"
  },
  "age_restricted": false
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ChangeItemsRequest {#entity-ChangeItemsRequest}

Запрос на изменение списка товаров в заказе

#|
|| **Name** | **Description** ||
||

_dropoff_point_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

ID точки назначения, в которой меняем список товаров (int64)
{.table-cell}
||
||

_items_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [V2CargoItem](#entity-V2CargoItem)[]

Новый список товаров для данной комбинации точек

_Min items:_{.json-schema-reset .json-schema-assertion} `1`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "extra_id": "БП-208",
    "pickup_point": 1,
    "dropoff_point": 2,
    "title": "Плюмбус",
    "size": {
      "length": 0.1,
      "width": 0.2,
      "height": 0.3
    },
    "weight": 2,
    "cost_value": "2.00",
    "cost_currency": "RUB",
    "quantity": 1,
    "fiscalization": {
      "excise": "12.50",
      "vat_code_str": "vat_none",
      "supplier_inn": "3664069397",
      "article": "20ML50OWKY4FC86",
      "mark": {
        "kind": "gs1_data_matrix_base64",
        "code": "444D00000000003741"
      },
      "item_type": "product"
    },
    "age_restricted": false
  }
]
```

{% endcut %}
{.table-cell}
||
||

_kind_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тип изменения (change_items)

_Const:_{.json-schema-reset .json-schema-value} `change_items`

_Example:_{.json-schema-reset .json-schema-example} `change_items`
{.table-cell}
||
||

_pickup_point_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

ID точки отправки, в которой меняем список товаров (int64)
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "kind": "change_items",
  "pickup_point_id": 1,
  "dropoff_point_id": 2,
  "items": [
    {
      "extra_id": "БП-208",
      "pickup_point": 1,
      "dropoff_point": 2,
      "title": "Плюмбус",
      "size": {
        "length": 0.1,
        "width": 0.2,
        "height": 0.3
      },
      "weight": 2,
      "cost_value": "2.00",
      "cost_currency": "RUB",
      "quantity": 1,
      "fiscalization": {
        "excise": "12.50",
        "vat_code_str": "vat_none",
        "supplier_inn": "3664069397",
        "article": "20ML50OWKY4FC86",
        "mark": {
          "kind": "gs1_data_matrix_base64",
          "code": "444D00000000003741"
        },
        "item_type": "product"
      },
      "age_restricted": false
    }
  ]
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ChangeCommentRequest {#entity-ChangeCommentRequest}

Запрос на изменение комментария в точке маршрута

#|
|| **Name** | **Description** ||
||

_comment_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Новый комментарий в точке

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_kind_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тип изменения (change_comment)

_Const:_{.json-schema-reset .json-schema-value} `change_comment`

_Example:_{.json-schema-reset .json-schema-example} `change_comment`
{.table-cell}
||
||

_point_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

ID точки, для которой меняем комментарий (int64)
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "kind": "change_comment",
  "point_id": 1,
  "comment": "example"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ContactOnPoint {#entity-ContactOnPoint}

Информация о контактном лице

#|
|| **Name** | **Description** ||
||

_name_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Имя контактного лица

_Example:_{.json-schema-reset .json-schema-example} `Морти`
{.table-cell}
||
||

_phone_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Телефон контактного лица

_Example:_{.json-schema-reset .json-schema-example} `+79099999998`
{.table-cell}
||
||

_email_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Email — обязательный параметр для точек с типом source и return

_Example:_{.json-schema-reset .json-schema-example} `example@yandex.ru`
{.table-cell}
||
||

_phone_additional_code_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Добавочный номер для звонка курьера

_Example:_{.json-schema-reset .json-schema-example} `602 17 500`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "name": "Морти",
  "phone": "+79099999998",
  "phone_additional_code": "602 17 500",
  "email": "example@yandex.ru"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ChangeContactRequest {#entity-ChangeContactRequest}

Запрос на изменение контакта в точке

#|
|| **Name** | **Description** ||
||

_contact_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [ContactOnPoint](#entity-ContactOnPoint)

Информация о контактном лице

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "name": "Морти",
  "phone": "+79099999998",
  "phone_additional_code": "602 17 500",
  "email": "example@yandex.ru"
}
```

{% endcut %}
{.table-cell}
||
||

_kind_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тип изменения (change_contact)

_Const:_{.json-schema-reset .json-schema-value} `change_contact`

_Example:_{.json-schema-reset .json-schema-example} `change_contact`
{.table-cell}
||
||

_point_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

ID точки, в которой меняем контакт (int64)
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "kind": "change_contact",
  "point_id": 1,
  "contact": {
    "name": "Морти",
    "phone": "+79099999998",
    "phone_additional_code": "602 17 500",
    "email": "example@yandex.ru"
  }
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### PackageId {#entity-PackageId}

Уникальный в рамках заявки идентификатор грузоместа.
Генерируется клиентом перед отправкой запроса


**Type**: string&lt;uuid&gt;

_Example:_{.json-schema-reset .json-schema-example} `a8e5b0e6-3d67-4d6f-89a5-3b6c1a0e4f5c`

</div>

<div class="openapi-entity">

### PackageType {#entity-PackageType}

Тип грузоместа.
Возможные значения:
- package — пакет
- box — коробка
- bag — мешок
- pallet — паллета
- other — тип по умолчанию


**Type**: string

_Default:_{.json-schema-reset .json-schema-value} `other`

_Enum:_{.json-schema-reset .json-schema-value} `package`, `box`, `bag`, `pallet`, `other`

</div>

<div class="openapi-entity">

### PackageCode {#entity-PackageCode}

Опциональный код/маркировка грузоместа.
Может содержать только латинские буквы, цифры и ASCII-спецсимволы.
Кириллица, emoji и другие не-ASCII символы не допускаются. Длина значения — от 1 до 30 символов.
Может повторяться в пределах заявки.


**Type**: string

_Min length:_{.json-schema-reset .json-schema-assertion} `1`

_Max length:_{.json-schema-reset .json-schema-assertion} `30`

_Pattern:_{.json-schema-reset .json-schema-assertion} `^[\x21-\x7E]+$`

_Example:_{.json-schema-reset .json-schema-example} `ab10702030/?`

</div>

<div class="openapi-entity">

### Package {#entity-Package}

Грузоместо — отдельная физическая единица обработки и перевозки.
Содержит тип грузоместа, его идентификатор и опциональную маркировку. Связано с соответствующими точками


#|
|| **Name** | **Description** ||
||

_dropoff_point_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Идентификатор точки, куда нужно доставить товар (отличается от идентификатора в заявке).
Может быть любым числом. Должен соответствовать значению route_points[].point_id у точки назначения

{.table-cell}
||
||

_package_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [PackageId](#entity-PackageId)

Уникальный в рамках заявки идентификатор грузоместа.
Генерируется клиентом перед отправкой запроса


_Example:_{.json-schema-reset .json-schema-example} `a8e5b0e6-3d67-4d6f-89a5-3b6c1a0e4f5c`
{.table-cell}
||
||

_pickup_point_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Идентификатор точки, откуда нужно забрать товар (отличается от идентификатора в заявке).
Может быть любым числом. Должен соответствовать значению route_points[].point_id у точки забора

{.table-cell}
||
||

_package_code_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [PackageCode](#entity-PackageCode)

Опциональный код/маркировка грузоместа.
Может содержать только латинские буквы, цифры и ASCII-спецсимволы.
Кириллица, emoji и другие не-ASCII символы не допускаются. Длина значения — от 1 до 30 символов.
Может повторяться в пределах заявки.


_Min length:_{.json-schema-reset .json-schema-assertion} `1`

_Max length:_{.json-schema-reset .json-schema-assertion} `30`

_Pattern:_{.json-schema-reset .json-schema-assertion} `^[\x21-\x7E]+$`

_Example:_{.json-schema-reset .json-schema-example} `ab10702030/?`
{.table-cell}
||
||

_package_type_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [PackageType](#entity-PackageType)

Тип грузоместа.
Возможные значения:
- package — пакет
- box — коробка
- bag — мешок
- pallet — паллета
- other — тип по умолчанию


_Default:_{.json-schema-reset .json-schema-value} `other`

_Enum:_{.json-schema-reset .json-schema-value} `package`, `box`, `bag`, `pallet`, `other`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "package_id": "a8e5b0e6-3d67-4d6f-89a5-3b6c1a0e4f5c",
  "package_type": "other",
  "package_code": "ab10702030/?",
  "pickup_point": 1,
  "dropoff_point": 2
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ChangePackagesRequest {#entity-ChangePackagesRequest}

Запрос на изменение списка грузомест в заказе

#|
|| **Name** | **Description** ||
||

_dropoff_point_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

ID точки назначения, в которой меняем список грузомест (int64)
{.table-cell}
||
||

_kind_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тип изменения (change_packages)

_Const:_{.json-schema-reset .json-schema-value} `change_packages`

_Example:_{.json-schema-reset .json-schema-example} `change_packages`
{.table-cell}
||
||

_packages_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [Package](#entity-Package)[]

Новый список грузомест для данной комбинации точек

_Min items:_{.json-schema-reset .json-schema-assertion} `1`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "package_id": "a8e5b0e6-3d67-4d6f-89a5-3b6c1a0e4f5c",
    "package_type": "other",
    "package_code": "ab10702030/?",
    "pickup_point": 1,
    "dropoff_point": 2
  }
]
```

{% endcut %}
{.table-cell}
||
||

_pickup_point_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

ID точки отправки, в которой меняем список грузомест (int64)
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "kind": "change_packages",
  "pickup_point_id": 1,
  "dropoff_point_id": 2,
  "packages": [
    {
      "package_id": "a8e5b0e6-3d67-4d6f-89a5-3b6c1a0e4f5c",
      "package_type": "other",
      "package_code": "ab10702030/?",
      "pickup_point": 1,
      "dropoff_point": 2
    }
  ]
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ChangeRequest {#entity-ChangeRequest}

{% cut "**One of 4 types**" %}{.json-schema-combinators data-marker=or}

- **Type**: [ChangeItemsRequest](#entity-ChangeItemsRequest)

  Запрос на изменение списка товаров в заказе

  {% cut "**Example**" %}{.json-schema-example}

  ```json translate=no
  {
    "kind": "change_items",
    "pickup_point_id": 1,
    "dropoff_point_id": 2,
    "items": [
      {
        "extra_id": "БП-208",
        "pickup_point": 1,
        "dropoff_point": 2,
        "title": "Плюмбус",
        "size": {
          "length": 0.1,
          "width": 0.2,
          "height": 0.3
        },
        "weight": 2,
        "cost_value": "2.00",
        "cost_currency": "RUB",
        "quantity": 1,
        "fiscalization": {
          "excise": "12.50",
          "vat_code_str": "vat_none",
          "supplier_inn": "3664069397",
          "article": "20ML50OWKY4FC86",
          "mark": {
            "kind": "gs1_data_matrix_base64",
            "code": "444D00000000003741"
          },
          "item_type": "product"
        },
        "age_restricted": false
      }
    ]
  }
  ```

  {% endcut %}

- **Type**: [ChangeCommentRequest](#entity-ChangeCommentRequest)

  Запрос на изменение комментария в точке маршрута

  {% cut "**Example**" %}{.json-schema-example}

  ```json translate=no
  {
    "kind": "change_comment",
    "point_id": 1,
    "comment": "example"
  }
  ```

  {% endcut %}

- **Type**: [ChangeContactRequest](#entity-ChangeContactRequest)

  Запрос на изменение контакта в точке

  {% cut "**Example**" %}{.json-schema-example}

  ```json translate=no
  {
    "kind": "change_contact",
    "point_id": 1,
    "contact": {
      "name": "Морти",
      "phone": "+79099999998",
      "phone_additional_code": "602 17 500",
      "email": "example@yandex.ru"
    }
  }
  ```

  {% endcut %}

- **Type**: [ChangePackagesRequest](#entity-ChangePackagesRequest)

  Запрос на изменение списка грузомест в заказе

  {% cut "**Example**" %}{.json-schema-example}

  ```json translate=no
  {
    "kind": "change_packages",
    "pickup_point_id": 1,
    "dropoff_point_id": 2,
    "packages": [
      {
        "package_id": "a8e5b0e6-3d67-4d6f-89a5-3b6c1a0e4f5c",
        "package_type": "other",
        "package_code": "ab10702030/?",
        "pickup_point": 1,
        "dropoff_point": 2
      }
    ]
  }
  ```

  {% endcut %}

{% endcut %}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "kind": "change_items",
  "pickup_point_id": 1,
  "dropoff_point_id": 2,
  "items": [
    {
      "extra_id": "БП-208",
      "pickup_point": 1,
      "dropoff_point": 2,
      "title": "Плюмбус",
      "size": {
        "length": 0.1,
        "width": 0.2,
        "height": 0.3
      },
      "weight": 2,
      "cost_value": "2.00",
      "cost_currency": "RUB",
      "quantity": 1,
      "fiscalization": {
        "excise": "12.50",
        "vat_code_str": "vat_none",
        "supplier_inn": "3664069397",
        "article": "20ML50OWKY4FC86",
        "mark": {},
        "item_type": "product"
      },
      "age_restricted": false
    }
  ]
}
```

{% endcut %}

</div>

## Responses

<div class="openapi__response__code__200">

## 200 OK

OK

</div>

<div class="openapi__response__code__400">

## 400 Bad Request

Достигнут лимит на максимальное количество вызовов запроса apply-changes

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "max_apply_changes",
  "message": "Заявка изменилась, обновите страницу"
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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `max_apply_changes`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Сообщение об ошибке, понятное человеку

_Example:_{.json-schema-reset .json-schema-example} `Заявка изменилась, обновите страницу`
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

Переданная ревизия запроса является устаревшей, необходимо обновить данные через [claims/info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md))

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "old_version",
  "message": "Заявка изменилась, обновите страницу"
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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `old_version`, `inappropriate_status`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Сообщение об ошибке, понятное человеку

_Example:_{.json-schema-reset .json-schema-example} `Заявка изменилась, обновите страницу`
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

</div>

[*Deprecated]: No longer supported, please use an alternative and newer version.