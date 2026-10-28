---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2ClaimsEdit.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsEdit.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsEdit.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Редактирование заявки до подтверждения

<!-- markdownlint-disable-file -->

Метод изменяет параметры заявки до принятия оффера (до операции [claims/accept](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsAccept.md))


## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/edit
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

_version_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Версия, с которой идет изменение (int64)
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
  "shipping_document": "example",
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
  ],
  "packages": [
    {
      "package_id": "a8e5b0e6-3d67-4d6f-89a5-3b6c1a0e4f5c",
      "package_type": "other",
      "package_code": "ab10702030/?",
      "pickup_point": 1,
      "dropoff_point": 2
    }
  ],
  "route_points": [
    {
      "point_id": 6987,
      "visit_order": 1,
      "contact": {
        "name": "Морти",
        "phone": "+79099999998",
        "phone_additional_code": "602 17 500",
        "email": "example@yandex.ru"
      },
      "address": {
        "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
        "shortname": "Большая Монетная улица, 1к1А",
        "coordinates": [
          0.5,
          0.5
        ],
        "country": "Россия",
        "city": "Санкт-Петербург",
        "building_name": "БЦ На Большой Монетной",
        "street": "Большая Монетная улица",
        "building": "23к1А",
        "porch": "A",
        "sfloor": "1",
        "sflat": "1",
        "door_code": "169",
        "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
        "doorbell_name": "Магидович",
        "comment": "Домофон не работает",
        "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
        "description": "Санкт-Петербург, Россия"
      },
      "skip_confirmation": false,
      "leave_under_door": true,
      "meet_outside": true,
      "no_door_call": true,
      "type": "source",
      "buyout": {
        "payment_method": "card"
      },
      "payment_on_delivery": {
        "customer": {
          "inn": "3664069397",
          "email": "example@yandex.ru",
          "phone": "79000000000"
        },
        "payment_method": null
      },
      "external_order_id": "100",
      "external_order_cost": {
        "value": "100.0",
        "currency": "RUB",
        "currency_sign": "₽"
      },
      "pickup_code": "893422",
      "should_notify_on_order_readiness": false,
      "code_verification_properties": {
        "code_verification_url": "https://www.example.com/"
      }
    },
    {
      "point_id": 6987,
      "visit_order": 1,
      "contact": {
        "name": "Морти",
        "phone": "+79099999998",
        "phone_additional_code": "602 17 500",
        "email": "example@yandex.ru"
      },
      "address": {
        "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
        "shortname": "Большая Монетная улица, 1к1А",
        "coordinates": [
          0.5,
          0.5
        ],
        "country": "Россия",
        "city": "Санкт-Петербург",
        "building_name": "БЦ На Большой Монетной",
        "street": "Большая Монетная улица",
        "building": "23к1А",
        "porch": "A",
        "sfloor": "1",
        "sflat": "1",
        "door_code": "169",
        "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
        "doorbell_name": "Магидович",
        "comment": "Домофон не работает",
        "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
        "description": "Санкт-Петербург, Россия"
      },
      "skip_confirmation": false,
      "leave_under_door": true,
      "meet_outside": true,
      "no_door_call": true,
      "type": "source",
      "buyout": {
        "payment_method": "card"
      },
      "payment_on_delivery": {
        "customer": {
          "inn": "3664069397",
          "email": "example@yandex.ru",
          "phone": "79000000000"
        },
        "payment_method": null
      },
      "external_order_id": "100",
      "external_order_cost": {
        "value": "100.0",
        "currency": "RUB",
        "currency_sign": "₽"
      },
      "pickup_code": "893422",
      "should_notify_on_order_readiness": false,
      "code_verification_properties": {
        "code_verification_url": "https://www.example.com/"
      }
    }
  ],
  "emergency_contact": {
    "name": "Рик",
    "phone": "+79826810246",
    "phone_additional_code": "602 17 500"
  },
  "client_requirements": {
    "taxi_class": "express",
    "cargo_type": "lcv_m",
    "cargo_loaders": 0,
    "cargo_options": [
      "thermobag"
    ],
    "pro_courier": false,
    "assign_robot": true,
    "rental_duration": 0
  },
  "callback_properties": {
    "callback_url": "https://www.example.com/"
  },
  "skip_door_to_door": false,
  "skip_client_notify": false,
  "skip_emergency_notify": false,
  "skip_act": false,
  "optional_return": false,
  "due": "2020-01-01T00:00:00+00:00",
  "comment": "Ресторан",
  "referral_source": "bitrix",
  "same_day_data": {
    "delivery_interval": {
      "from": "2020-01-01T07:00:00+00:00",
      "to": "2020-01-01T07:00:00+00:00"
    }
  },
  "auto_accept": true,
  "offer_payload": "asjdijasDKL;ahsdfljhlkjhasF;HS;Ldjf;ljloshf"
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_items_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [V2CargoItem](#entity-V2CargoItem)[]

Параметры товаров

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

_route_points_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [V2CargoRoutePoints](#entity-V2CargoRoutePoints)

Информация по точкам маршрута

_Min items:_{.json-schema-reset .json-schema-assertion} `2`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "point_id": 6987,
    "visit_order": 1,
    "contact": {
      "name": "Морти",
      "phone": "+79099999998",
      "phone_additional_code": "602 17 500",
      "email": "example@yandex.ru"
    },
    "address": {
      "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
      "shortname": "Большая Монетная улица, 1к1А",
      "coordinates": [
        0.5,
        0.5
      ],
      "country": "Россия",
      "city": "Санкт-Петербург",
      "building_name": "БЦ На Большой Монетной",
      "street": "Большая Монетная улица",
      "building": "23к1А",
      "porch": "A",
      "sfloor": "1",
      "sflat": "1",
      "door_code": "169",
      "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
      "doorbell_name": "Магидович",
      "comment": "Домофон не работает",
      "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
      "description": "Санкт-Петербург, Россия"
    },
    "skip_confirmation": false,
    "leave_under_door": true,
    "meet_outside": true,
    "no_door_call": true,
    "type": "source",
    "buyout": {
      "payment_method": "card"
    },
    "payment_on_delivery": {
      "customer": {
        "inn": "3664069397",
        "email": "example@yandex.ru",
        "phone": "79000000000"
      },
      "payment_method": null
    },
    "external_order_id": "100",
    "external_order_cost": {
      "value": "100.0",
      "currency": "RUB",
      "currency_sign": "₽"
    },
    "pickup_code": "893422",
    "should_notify_on_order_readiness": false,
    "code_verification_properties": {
      "code_verification_url": "https://www.example.com/"
    }
  },
  {
    "point_id": 6987,
    "visit_order": 1,
    "contact": {
      "name": "Морти",
      "phone": "+79099999998",
      "phone_additional_code": "602 17 500",
      "email": "example@yandex.ru"
    },
    "address": {
      "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
      "shortname": "Большая Монетная улица, 1к1А",
      "coordinates": [
        0.5,
        0.5
      ],
      "country": "Россия",
      "city": "Санкт-Петербург",
      "building_name": "БЦ На Большой Монетной",
      "street": "Большая Монетная улица",
      "building": "23к1А",
      "porch": "A",
      "sfloor": "1",
      "sflat": "1",
      "door_code": "169",
      "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
      "doorbell_name": "Магидович",
      "comment": "Домофон не работает",
      "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
      "description": "Санкт-Петербург, Россия"
    },
    "skip_confirmation": false,
    "leave_under_door": true,
    "meet_outside": true,
    "no_door_call": true,
    "type": "source",
    "buyout": {
      "payment_method": "card"
    },
    "payment_on_delivery": {
      "customer": {
        "inn": "3664069397",
        "email": "example@yandex.ru",
        "phone": "79000000000"
      },
      "payment_method": null
    },
    "external_order_id": "100",
    "external_order_cost": {
      "value": "100.0",
      "currency": "RUB",
      "currency_sign": "₽"
    },
    "pickup_code": "893422",
    "should_notify_on_order_readiness": false,
    "code_verification_properties": {
      "code_verification_url": "https://www.example.com/"
    }
  }
]
```

{% endcut %}
{.table-cell}
||
||

_auto_accept_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Включить автоматическое подтверждение заявки после создания. Для использования данной опции требуется согласование менеджера
{.table-cell}
||
||

_callback_properties_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CallbackProperties](#entity-CallbackProperties)

Параметры уведомления сервера клиента о смене статуса заявки.

Уведомление представляет собой POST-запрос по указанному url, к
которому будут добавлены информация о дате последнего изменения
заявки и идентификатора заявки в виде
'updated_ts=<ISO-8601>&claim_id=<id заявки>', то есть url вида
'https://example.com/?my_order_id=123&' будет расширен до
'https://example.com/?my_order_id=123&updated_ts=...&claim_id=...'.

Важно: параметры добавляются конкатенацией к callback_url, то есть
url вида 'https://example.com' превратится в невалидный
'https://example.comupdated_ts=...&claim_id=...'.


Поддерживаются только http и https. При https ssl-сертификат должен
быть выдан известным серверу центром сертификации.

К уведомлениям следует относиться как к push ahead of polling, как
к ускорению получения информации о смене статусов. Сервер ожидает
ответ 200, при таймаутах или любом другом ответе какое-то время
будет пытаться доставить уведомление, после чего прекратит попытки.
То есть для надежного получения статуса по заявке клиенту
необходимо запрашивать информацию с помощью метода [claims/info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md).

Клиенту следует учесть, что ответ операции [claims/info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md) может
содержать более старое состояние заявки (надо ориентироваться на
значение поля updated_ts). В этом случает необходимо повторить
вызов операции через некоторое время (от 5 до 30 секунд).


{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "callback_url": "https://www.example.com/"
}
```

{% endcut %}
{.table-cell}
||
||

_client_requirements_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ClientRequirements](#entity-ClientRequirements)

Требования от клиента, указанные при создании или редактировании заявки

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "taxi_class": "express",
  "cargo_type": "lcv_m",
  "cargo_loaders": 0,
  "cargo_options": [
    "thermobag"
  ],
  "pro_courier": false,
  "assign_robot": true,
  "rental_duration": 0
}
```

{% endcut %}
{.table-cell}
||
||

_comment_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Комментарий к заказу

_Example:_{.json-schema-reset .json-schema-example} `Ресторан`
{.table-cell}
||
||

_due_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Due](#entity-Due)

Желаемое время прибытия исполнителя на точку А (source).
В РФ отложить расчетное время прибытия исполнителя можно:
    - на 30-240 минут от текущего момента – для тарифа `express`;
    - на пять суток от текущего момента – для тарифа `cargo`.

Параметр не совместим с опциями замедления в тарифе `express` на территории РФ.
Если этот параметр не задан, то запустится поиск исполнителя на ближайшее время.


_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T00:00:00+00:00`
{.table-cell}
||
||

_emergency_contact_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ContactWithPhone](#entity-ContactWithPhone)

Информация о контактном лице с номером телефона

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "name": "Рик",
  "phone": "+79826810246",
  "phone_additional_code": "602 17 500"
}
```

{% endcut %}
{.table-cell}
||
||

_offer_payload_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Payload, полученный методом [offers/calculate](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2OfferCalculate.md)

_Example:_{.json-schema-reset .json-schema-example} `asjdijasDKL;ahsdfljhlkjhasF;HS;Ldjf;ljloshf`
{.table-cell}
||
||

_optional_return_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [OptionalReturn](#entity-OptionalReturn)

Отключить возврат товаров в случае отмены заказа.

Возможные значения:
  - true (курьер оставляет товар себе)
  - false (по умолчанию, требуется вернуть товар)


_Default:_{.json-schema-reset .json-schema-value} `false`

_Example:_{.json-schema-reset .json-schema-example} `false`
{.table-cell}
||
||

_packages_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Package](#entity-Package)[]

Список грузомест

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

_referral_source_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Источник заявки (можно передать наименование CMS, из которой создается запрос)


_Example:_{.json-schema-reset .json-schema-example} `bitrix`
{.table-cell}
||
||

_same_day_data_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [SameDayData](#entity-SameDayData)

Признаки заказа "В течение дня"

Дополнительная информация для заявок `В течение дня`. Недоступно в России

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "delivery_interval": {
    "from": "2020-01-01T07:00:00+00:00",
    "to": "2020-01-01T07:00:00+00:00"
  }
}
```

{% endcut %}
{.table-cell}
||
||

_shipping_document_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Сопроводительные документы

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_skip_act_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [SkipAct](#entity-SkipAct)

Не показывать акт приема-передачи

_Example:_{.json-schema-reset .json-schema-example} `false`
{.table-cell}
||
||

_skip_client_notify_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [SkipClientNotify](#entity-SkipClientNotify)

Не отправлять отправителю/получателю смс-уведомления,
когда к нему направится курьер.

Значение по умолчанию: false (отправлять уведомления)


_Default:_{.json-schema-reset .json-schema-value} `false`

_Example:_{.json-schema-reset .json-schema-example} `false`
{.table-cell}
||
||

_skip_door_to_door_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [SkipDoorToDoor](#entity-SkipDoorToDoor)

Отключить доставку до двери (выключить опцию "От двери до двери").

Возможные значения:
  - true (курьер доставит заказ только на улицу, до подъезда)
  - false (курьер доставит до двери) - значение по умолчанию


_Default:_{.json-schema-reset .json-schema-value} `false`

_Example:_{.json-schema-reset .json-schema-example} `false`
{.table-cell}
||
||

_skip_emergency_notify_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [SkipEmergencyNotify](#entity-SkipEmergencyNotify)

Не отправлять уведомление запасному контактному лицу

Значение по умолчанию: false (отправлять уведомления)


_Default:_{.json-schema-reset .json-schema-value} `false`

_Example:_{.json-schema-reset .json-schema-example} `false`
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

### AddressFullname {#entity-AddressFullname}

Полный адрес с указанием города, улицы и номера дома.
Номер квартиры, подъезда и этаж указывать не нужно.


**Type**: string

_Example:_{.json-schema-reset .json-schema-example} `Санкт-Петербург, Большая Монетная улица, 1к1А`

</div>

<div class="openapi-entity">

### PointAddress {#entity-PointAddress}

Адрес точки

#|
|| **Name** | **Description** ||
||

_coordinates_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: number[]

Координаты точек в виде массива из двух вещественных чисел: долгота, широта — именно в таком порядке.
Указываются округленные значения координат.


_Min items:_{.json-schema-reset .json-schema-assertion} `2`

_Max items:_{.json-schema-reset .json-schema-assertion} `2`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  0.5,
  0.5
]
```

{% endcut %}
{.table-cell}
||
||

_fullname_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [AddressFullname](#entity-AddressFullname)

Полный адрес с указанием города, улицы и номера дома.
Номер квартиры, подъезда и этаж указывать не нужно.


_Example:_{.json-schema-reset .json-schema-example} `Санкт-Петербург, Большая Монетная улица, 1к1А`
{.table-cell}
||
||

_building_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Строение

_Example:_{.json-schema-reset .json-schema-example} `23к1А`
{.table-cell}
||
||

_building_name_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Название апартаментов (здания)

_Example:_{.json-schema-reset .json-schema-example} `БЦ На Большой Монетной`
{.table-cell}
||
||

_city_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Город

_Example:_{.json-schema-reset .json-schema-example} `Санкт-Петербург`
{.table-cell}
||
||

_comment_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Комментарий для курьера.

Для точки отправки используйте шаблон: "Доставка из магазина <>. Сообщите менеджеру, что заказ для Яндекс Доставки. Назовите номер заказа <> и заберите товар. Заказ оплачен безналично, при передаче заказа нельзя требовать с получателя деньги за доставку."

Для точек доставки в комментарии передавайте пожелания получателя. Например, "домофон не работает" / "шлагбаум закрыт, позвонить за 10 минут" / "не звонить, спит ребенок".


_Example:_{.json-schema-reset .json-schema-example} `Домофон не работает`
{.table-cell}
||
||

_country_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Страна

_Example:_{.json-schema-reset .json-schema-example} `Россия`
{.table-cell}
||
||

_description_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Географическая область, уточняющая краткий адрес до глобального соответствия

_Example:_{.json-schema-reset .json-schema-example} `Санкт-Петербург, Россия`
{.table-cell}
||
||

_door_code_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Код домофона

_Example:_{.json-schema-reset .json-schema-example} `169`
{.table-cell}
||
||

_door_code_extra_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Дополнительные указания по домофонам

_Example:_{.json-schema-reset .json-schema-example} `код на вход во двор #1234, код от апартаментов #4321`
{.table-cell}
||
||

_doorbell_name_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Имя на дверном звонке

_Example:_{.json-schema-reset .json-schema-example} `Магидович`
{.table-cell}
||
||

_porch_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Подъезд (может быть A)

_Example:_{.json-schema-reset .json-schema-example} `A`
{.table-cell}
||
||

_sflat_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Квартира

_Example:_{.json-schema-reset .json-schema-example} `1`
{.table-cell}
||
||

_sfloor_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Этаж

_Example:_{.json-schema-reset .json-schema-example} `1`
{.table-cell}
||
||

_shortname_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Краткий адрес в пределах города (как на Таксометре)


_Example:_{.json-schema-reset .json-schema-example} `Большая Монетная улица, 1к1А`
{.table-cell}
||
||

_street_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Улица

_Example:_{.json-schema-reset .json-schema-example} `Большая Монетная улица`
{.table-cell}
||
||

_uri_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

URI геообъекта на картах

_Example:_{.json-schema-reset .json-schema-example} `ymapsbm1://geo?ll=38.805%2C55.084`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
  "shortname": "Большая Монетная улица, 1к1А",
  "coordinates": [
    0.5,
    0.5
  ],
  "country": "Россия",
  "city": "Санкт-Петербург",
  "building_name": "БЦ На Большой Монетной",
  "street": "Большая Монетная улица",
  "building": "23к1А",
  "porch": "A",
  "sfloor": "1",
  "sflat": "1",
  "door_code": "169",
  "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
  "doorbell_name": "Магидович",
  "comment": "Домофон не работает",
  "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
  "description": "Санкт-Петербург, Россия"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### CargoPointSkipConfirmation {#entity-CargoPointSkipConfirmation}

Пропускать подтверждение по смс в данной точке

Значение по умолчанию: false (подтверждение требуется).


**Type**: boolean

_Default:_{.json-schema-reset .json-schema-value} `false`

</div>

<div class="openapi-entity">

### PointType {#entity-PointType}

Тип точки:
  - source - точка отправления, где курьер забирает товар
  - destination – точки назначения, где курьер передает товар
  - return - точка возврата товара (добавляется автоматически и по умолчанию совпадает с точкой отправления, но также можно определить другую точку)


**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `source`, `destination`, `return`

</div>

<div class="openapi-entity">

### PaymentMethod {#entity-PaymentMethod}

Выбранный тип оплаты.
card - оплата картой;
cash - оплата наличными (пока недоступна);


**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `card`, `cash`

</div>

<div class="openapi-entity">

### RequestBuyout {#entity-RequestBuyout}

Информация по выкупу товара курьером в точке отправления (актуально, если для всех точек назначения в маршруте включена оплата при получении).

#|
|| **Name** | **Description** ||
||

_payment_method_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [PaymentMethod](#entity-PaymentMethod)

На данный момент актуально только cash

Выбранный тип оплаты.
card - оплата картой;
cash - оплата наличными (пока недоступна);


_Enum:_{.json-schema-reset .json-schema-value} `card`, `cash`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "payment_method": "card"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### Inn {#entity-Inn}

ИНН пользователя (10 или 12 цифр)

**Type**: string

_Pattern:_{.json-schema-reset .json-schema-assertion} `^[A-Z0-9\\-]+$`

_Example:_{.json-schema-reset .json-schema-example} `3664069397`

</div>

<div class="openapi-entity">

### RequestCustomerFiscalization {#entity-RequestCustomerFiscalization}

Информация о получателе

#|
|| **Name** | **Description** ||
||

_email_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Электронная почта пользователя в формате example@yandex.ru.
Если не указано, будет использована почта получателя из точки назначения


_Example:_{.json-schema-reset .json-schema-example} `example@yandex.ru`
{.table-cell}
||
||

_inn_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Inn](#entity-Inn)

ИНН пользователя (10 или 12 цифр)

_Pattern:_{.json-schema-reset .json-schema-assertion} `^[A-Z0-9\\-]+$`

_Example:_{.json-schema-reset .json-schema-example} `3664069397`
{.table-cell}
||
||

_phone_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Телефон пользователя в формате +X XXX XXX XX XX. Если не указано, будет использован телефон получателя из точки

_Example:_{.json-schema-reset .json-schema-example} `79000000000`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "inn": "3664069397",
  "email": "example@yandex.ru",
  "phone": "79000000000"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### RequestPaymentOnDelivery {#entity-RequestPaymentOnDelivery}

Информация по оплате при получении (актуально для оплаты при получении)

#|
|| **Name** | **Description** ||
||

_payment_method_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [PaymentMethod](#entity-PaymentMethod)

Выбранный тип оплаты.
card - оплата картой;
cash - оплата наличными (пока недоступна);


_Enum:_{.json-schema-reset .json-schema-value} `card`, `cash`
{.table-cell}
||
||

_customer_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [RequestCustomerFiscalization](#entity-RequestCustomerFiscalization)

Информация о получателе

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "inn": "3664069397",
  "email": "example@yandex.ru",
  "phone": "79000000000"
}
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "customer": {
    "inn": "3664069397",
    "email": "example@yandex.ru",
    "phone": "79000000000"
  },
  "payment_method": "card"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ExternalOrderCost {#entity-ExternalOrderCost}

Стоимость внешнего заказа, привязанного к точке

#|
|| **Name** | **Description** ||
||

_currency_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Валюта

_Example:_{.json-schema-reset .json-schema-example} `RUB`
{.table-cell}
||
||

_currency_sign_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Знак валюты

_Example:_{.json-schema-reset .json-schema-example} `₽`
{.table-cell}
||
||

_value_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Стоимость

_Example:_{.json-schema-reset .json-schema-example} `100.0`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "value": "100.0",
  "currency": "RUB",
  "currency_sign": "₽"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### PickupCode {#entity-PickupCode}

Код выдачи заказа курьеру.
Курьеру потребуется ввести этот код, чтобы подтвердить, что он забрал заказ.
Для этого необходимо, чтобы ваши сотрудники на точке выдачи имели возможность назвать этот код курьеру.
Актуально для точки с типом 'source'.
Формат кода: 6 цифр
|
Код выдачи товара (ПВЗ)


**Type**: string

_Example:_{.json-schema-reset .json-schema-example} `893422`

</div>

<div class="openapi-entity">

### CodeVerificationProperties {#entity-CodeVerificationProperties}

Параметры проверки кода во внешнем сервисе.

Если поле заполнено, то проверка кода представляет собой запрос по указанному url. Для корректной
работы проверки кода для этого url необходимо поддержать следующее api:

    post:
        description: |
          bearerAuth: содержит JWT с зашифрованным payload:
            type: object
              required:
                - iss
                - sub
                - exp
                - claim_id
                - point_id
              properties:
                claim_id:
                  type: string
                  description: Уникальный идентификатор заявки
                  example: "123456789"
                point_id:
                  type: string
                  description: Идентификатор точки
                  example: "123456789"
                iss:
                  type: string
                  description: Издатель токена
                  enum: [dostavka.yandex.ru]
                sub:
                  type: string
                  description: Сущность, для которой токен выписан
                  example: "example.com"
                exp:
                  type: string
                  format: date-time
                  description: Время истечения срока жизни токена
          расшифровывать информацию следует с помощью публичных токенов доступных по ссылке https://dostavka.yandex.ru/.well-known/jwks.json и традиционных библиотек для JWT
        security:
          - bearerAuth: []
        requestBody:
          required: true
          content:
            application/json:
                type: object
                required:
                  - verification_code
                properties:
                  verification_code:
                    type: string
                    description: Код подтверждения для сборочного задания
                    example: "8392"
        responses:
          '200':
            description: Результат обработки кода подтверждения
            content:
              application/json:
                type: object
                required:
                  - status
                properties:
                  status:
                    type: string
                    description: |
                    Результат обработки кода подтверждения

                    Описание значений:
                      - `in_progress` — проверка кода выполняется
                      - `completed` — код подтвержден успешно
                      - `invalid_code` — передан неверный код подтверждения
                    enum:
                      - in_progress
                      - completed
                      - invalid_code
                    example: "in_progress"
          '400':
            description: Некорректный формат запроса
          '401':
            description: Отсутствует или невалидный JWT
          '403':
            description: Ошибка проверки подписи JWT
          '404':
            description: Заявка не найдена
            content:
              application/json:
                type: object
                required:
                  - status
                properties:
                  status:
                    type: string
                    enum: [not_found]
                    example: "not_found"
          '409':
            description: Конфликт при обработке запроса
            content:
              application/json:
                type: object
                required:
                  - status
                properties:
                  status:
                    type: string
                    description: |
                      Код причины конфликта:
                      - `b2b_problem` — проблема с доступом или токеном у b2b клиента(access_denied, token_problem)
                      - `state_mismatch` — операция невозможна для текущего статуса заявки
                      - `operation_timeout` — не удалось обработать запрос подтверждения кода в течение 60 секунд (параметр конфигурируется) из-за превышения лимитов (rate limit) на выполнение запросов.
                    enum:
                      - b2b_problem
                      - state_mismatch
                      - operation_timeout
                    example: "b2b_problem"
                  message:
                    type: string
                    description: |
                      человекочитаемое сообщение об ошибке
          '500':
            description: Внутренняя ошибка сервиса

Поддерживаются только https, ssl-сертификат должен
быть выдан известным серверу центром сертификации.


#|
|| **Name** | **Description** ||
||

_code_verification_url_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

URL, который вызывается при проверке кода получателя.


_Pattern:_{.json-schema-reset .json-schema-assertion} `^https?:.*`

_Example:_{.json-schema-reset .json-schema-example} `https://www.example.com/`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "code_verification_url": "https://www.example.com/"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### V2CargoPoint {#entity-V2CargoPoint}

#|
|| **Name** | **Description** ||
||

_address_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [PointAddress](#entity-PointAddress)

Адрес точки

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
  "shortname": "Большая Монетная улица, 1к1А",
  "coordinates": [
    0.5,
    0.5
  ],
  "country": "Россия",
  "city": "Санкт-Петербург",
  "building_name": "БЦ На Большой Монетной",
  "street": "Большая Монетная улица",
  "building": "23к1А",
  "porch": "A",
  "sfloor": "1",
  "sflat": "1",
  "door_code": "169",
  "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
  "doorbell_name": "Магидович",
  "comment": "Домофон не работает",
  "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
  "description": "Санкт-Петербург, Россия"
}
```

{% endcut %}
{.table-cell}
||
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

_point_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Целочисленный идентификатор точки (int64), уникальна в рамках создания заявки

{.table-cell}
||
||

_type_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [PointType](#entity-PointType)

Тип точки:
  - source - точка отправления, где курьер забирает товар
  - destination – точки назначения, где курьер передает товар
  - return - точка возврата товара (добавляется автоматически и по умолчанию совпадает с точкой отправления, но также можно определить другую точку)


_Enum:_{.json-schema-reset .json-schema-value} `source`, `destination`, `return`
{.table-cell}
||
||

_visit_order_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Порядок посещения точки (нумерация начинается с 1) (int64)
{.table-cell}
||
||

_buyout_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [RequestBuyout](#entity-RequestBuyout)

Информация по выкупу товара курьером в точке отправления (актуально, если для всех точек назначения в маршруте включена оплата при получении).

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "payment_method": "card"
}
```

{% endcut %}
{.table-cell}
||
||

_code_verification_properties_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CodeVerificationProperties](#entity-CodeVerificationProperties)

Параметры проверки кода во внешнем сервисе.

Если поле заполнено, то проверка кода представляет собой запрос по указанному url. Для корректной
работы проверки кода для этого url необходимо поддержать следующее api:

    post:
        description: &#124;
          bearerAuth: содержит JWT с зашифрованным payload:
            type: object
              required:
                - iss
                - sub
                - exp
                - claim_id
                - point_id
              properties:
                claim_id:
                  type: string
                  description: Уникальный идентификатор заявки
                  example: "123456789"
                point_id:
                  type: string
                  description: Идентификатор точки
                  example: "123456789"
                iss:
                  type: string
                  description: Издатель токена
                  enum: [dostavka.yandex.ru]
                sub:
                  type: string
                  description: Сущность, для которой токен выписан
                  example: "example.com"
                exp:
                  type: string
                  format: date-time
                  description: Время истечения срока жизни токена
          расшифровывать информацию следует с помощью публичных токенов доступных по ссылке https://dostavka.yandex.ru/.well-known/jwks.json и традиционных библиотек для JWT
        security:
          - bearerAuth: []
        requestBody:
          required: true
          content:
            application/json:
                type: object
                required:
                  - verification_code
                properties:
                  verification_code:
                    type: string
                    description: Код подтверждения для сборочного задания
                    example: "8392"
        responses:
          '200':
            description: Результат обработки кода подтверждения
            content:
              application/json:
                type: object
                required:
                  - status
                properties:
                  status:
                    type: string
                    description: &#124;
                    Результат обработки кода подтверждения

                    Описание значений:
                      - `in_progress` — проверка кода выполняется
                      - `completed` — код подтвержден успешно
                      - `invalid_code` — передан неверный код подтверждения
                    enum:
                      - in_progress
                      - completed
                      - invalid_code
                    example: "in_progress"
          '400':
            description: Некорректный формат запроса
          '401':
            description: Отсутствует или невалидный JWT
          '403':
            description: Ошибка проверки подписи JWT
          '404':
            description: Заявка не найдена
            content:
              application/json:
                type: object
                required:
                  - status
                properties:
                  status:
                    type: string
                    enum: [not_found]
                    example: "not_found"
          '409':
            description: Конфликт при обработке запроса
            content:
              application/json:
                type: object
                required:
                  - status
                properties:
                  status:
                    type: string
                    description: &#124;
                      Код причины конфликта:
                      - `b2b_problem` — проблема с доступом или токеном у b2b клиента(access_denied, token_problem)
                      - `state_mismatch` — операция невозможна для текущего статуса заявки
                      - `operation_timeout` — не удалось обработать запрос подтверждения кода в течение 60 секунд (параметр конфигурируется) из-за превышения лимитов (rate limit) на выполнение запросов.
                    enum:
                      - b2b_problem
                      - state_mismatch
                      - operation_timeout
                    example: "b2b_problem"
                  message:
                    type: string
                    description: &#124;
                      человекочитаемое сообщение об ошибке
          '500':
            description: Внутренняя ошибка сервиса

Поддерживаются только https, ssl-сертификат должен
быть выдан известным серверу центром сертификации.


{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "code_verification_url": "https://www.example.com/"
}
```

{% endcut %}
{.table-cell}
||
||

_external_order_cost_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ExternalOrderCost](#entity-ExternalOrderCost)

Стоимость внешнего заказа, привязанного к точке

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "value": "100.0",
  "currency": "RUB",
  "currency_sign": "₽"
}
```

{% endcut %}
{.table-cell}
||
||

_external_order_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Номер заказа из системы клиента.
Передается для точки с типом destination


_Example:_{.json-schema-reset .json-schema-example} `100`
{.table-cell}
||
||

_leave_under_door_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Оставить заказ у двери
{.table-cell}
||
||

_meet_outside_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Курьера встретят на улице у подъезда
{.table-cell}
||
||

_no_door_call_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Не звонить в дверь
{.table-cell}
||
||

_payment_on_delivery_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [RequestPaymentOnDelivery](#entity-RequestPaymentOnDelivery)

Информация по оплате при получении (актуально для оплаты при получении)

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "customer": {
    "inn": "3664069397",
    "email": "example@yandex.ru",
    "phone": "79000000000"
  },
  "payment_method": "card"
}
```

{% endcut %}
{.table-cell}
||
||

_pickup_code_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [PickupCode](#entity-PickupCode)

Код выдачи заказа курьеру.
Курьеру потребуется ввести этот код, чтобы подтвердить, что он забрал заказ.
Для этого необходимо, чтобы ваши сотрудники на точке выдачи имели возможность назвать этот код курьеру.
Актуально для точки с типом 'source'.
Формат кода: 6 цифр
&#124;
Код выдачи товара (ПВЗ)


_Example:_{.json-schema-reset .json-schema-example} `893422`
{.table-cell}
||
||

_should_notify_on_order_readiness_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Укажите этот параметр равным `true`, чтобы использовать метод [Готовность заказа к выдаче](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsSetPointReady.md) для уведомления курьера о готовности заказа.
Доступно только для точки отправления


_Default:_{.json-schema-reset .json-schema-value} `false`
{.table-cell}
||
||

_skip_confirmation_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CargoPointSkipConfirmation](#entity-CargoPointSkipConfirmation)

Пропускать подтверждение по смс в данной точке

Значение по умолчанию: false (подтверждение требуется).


_Default:_{.json-schema-reset .json-schema-value} `false`

_Example:_{.json-schema-reset .json-schema-example} `false`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "point_id": 6987,
  "visit_order": 1,
  "contact": {
    "name": "Морти",
    "phone": "+79099999998",
    "phone_additional_code": "602 17 500",
    "email": "example@yandex.ru"
  },
  "address": {
    "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
    "shortname": "Большая Монетная улица, 1к1А",
    "coordinates": [
      0.5,
      0.5
    ],
    "country": "Россия",
    "city": "Санкт-Петербург",
    "building_name": "БЦ На Большой Монетной",
    "street": "Большая Монетная улица",
    "building": "23к1А",
    "porch": "A",
    "sfloor": "1",
    "sflat": "1",
    "door_code": "169",
    "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
    "doorbell_name": "Магидович",
    "comment": "Домофон не работает",
    "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
    "description": "Санкт-Петербург, Россия"
  },
  "skip_confirmation": false,
  "leave_under_door": true,
  "meet_outside": true,
  "no_door_call": true,
  "type": "source",
  "buyout": {
    "payment_method": "card"
  },
  "payment_on_delivery": {
    "customer": {
      "inn": "3664069397",
      "email": "example@yandex.ru",
      "phone": "79000000000"
    },
    "payment_method": null
  },
  "external_order_id": "100",
  "external_order_cost": {
    "value": "100.0",
    "currency": "RUB",
    "currency_sign": "₽"
  },
  "pickup_code": "893422",
  "should_notify_on_order_readiness": false,
  "code_verification_properties": {
    "code_verification_url": "https://www.example.com/"
  }
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### V2CargoRoutePoints {#entity-V2CargoRoutePoints}

Информация по точкам маршрута

**Type**: [V2CargoPoint](#entity-V2CargoPoint)[]

_Min items:_{.json-schema-reset .json-schema-assertion} `2`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "point_id": 6987,
    "visit_order": 1,
    "contact": {
      "name": "Морти",
      "phone": "+79099999998",
      "phone_additional_code": "602 17 500",
      "email": "example@yandex.ru"
    },
    "address": {
      "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
      "shortname": "Большая Монетная улица, 1к1А",
      "coordinates": [
        0.5,
        0.5
      ],
      "country": "Россия",
      "city": "Санкт-Петербург",
      "building_name": "БЦ На Большой Монетной",
      "street": "Большая Монетная улица",
      "building": "23к1А",
      "porch": "A",
      "sfloor": "1",
      "sflat": "1",
      "door_code": "169",
      "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
      "doorbell_name": "Магидович",
      "comment": "Домофон не работает",
      "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
      "description": "Санкт-Петербург, Россия"
    },
    "skip_confirmation": false,
    "leave_under_door": true,
    "meet_outside": true,
    "no_door_call": true,
    "type": "source",
    "buyout": {
      "payment_method": "card"
    },
    "payment_on_delivery": {
      "customer": {
        "inn": "3664069397",
        "email": "example@yandex.ru",
        "phone": "79000000000"
      },
      "payment_method": null
    },
    "external_order_id": "100",
    "external_order_cost": {
      "value": "100.0",
      "currency": "RUB",
      "currency_sign": "₽"
    },
    "pickup_code": "893422",
    "should_notify_on_order_readiness": false,
    "code_verification_properties": {
      "code_verification_url": "https://www.example.com/"
    }
  },
  {
    "point_id": 6987,
    "visit_order": 1,
    "contact": {
      "name": "Морти",
      "phone": "+79099999998",
      "phone_additional_code": "602 17 500",
      "email": "example@yandex.ru"
    },
    "address": {
      "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
      "shortname": "Большая Монетная улица, 1к1А",
      "coordinates": [
        0.5,
        0.5
      ],
      "country": "Россия",
      "city": "Санкт-Петербург",
      "building_name": "БЦ На Большой Монетной",
      "street": "Большая Монетная улица",
      "building": "23к1А",
      "porch": "A",
      "sfloor": "1",
      "sflat": "1",
      "door_code": "169",
      "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
      "doorbell_name": "Магидович",
      "comment": "Домофон не работает",
      "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
      "description": "Санкт-Петербург, Россия"
    },
    "skip_confirmation": false,
    "leave_under_door": true,
    "meet_outside": true,
    "no_door_call": true,
    "type": "source",
    "buyout": {
      "payment_method": "card"
    },
    "payment_on_delivery": {
      "customer": {
        "inn": "3664069397",
        "email": "example@yandex.ru",
        "phone": "79000000000"
      },
      "payment_method": null
    },
    "external_order_id": "100",
    "external_order_cost": {
      "value": "100.0",
      "currency": "RUB",
      "currency_sign": "₽"
    },
    "pickup_code": "893422",
    "should_notify_on_order_readiness": false,
    "code_verification_properties": {
      "code_verification_url": "https://www.example.com/"
    }
  }
]
```

{% endcut %}

</div>

<div class="openapi-entity">

### ContactWithPhone {#entity-ContactWithPhone}

Информация о контактном лице с номером телефона

#|
|| **Name** | **Description** ||
||

_name_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Имя контактного лица

_Example:_{.json-schema-reset .json-schema-example} `Рик`
{.table-cell}
||
||

_phone_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Телефон контактного лица

_Example:_{.json-schema-reset .json-schema-example} `+79826810246`
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
  "name": "Рик",
  "phone": "+79826810246",
  "phone_additional_code": "602 17 500"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### CargoType {#entity-CargoType}

Тип (размер) кузова для грузового тарифа.
Возможные значения:
- van ("Маленький кузов")
- lcv_m ("Средний кузов")
- lcv_l ("Большой кузов")
- lcv_xl ("Кузов XL")
Точный список возможных значений для конкретной геоточки уточняйте с помощью метода получения тарифов [tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md)


**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `van`, `lcv_m`, `lcv_l`, `lcv_xl`

</div>

<div class="openapi-entity">

### CargoOptions {#entity-CargoOptions}

Список дополнительных опций тарифа.

Возможные отдельные опции:
  - auto_courier (курьер только на автомобиле)
  - thermobag (курьер с термосумкой)

Пример списка опций: ["auto_courier"].

Точный список возможных значений для конкретной геоточки
уточните с помощью метода получения тарифов [tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md)


**Type**: string[]

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  "thermobag"
]
```

{% endcut %}

</div>

<div class="openapi-entity">

### ClientRequirements {#entity-ClientRequirements}

Требования от клиента, указанные при создании или редактировании заявки

#|
|| **Name** | **Description** ||
||

_taxi_class_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тариф доставки. Возможные значения: courier, express, cargo, sdd_multislot


_Example:_{.json-schema-reset .json-schema-example} `express`
{.table-cell}
||
||

_assign_robot_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Разрешить выполнение заказа роботом

{.table-cell}
||
||

_cargo_loaders_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: integer

Число грузчиков для грузового тарифа.
Возможные значения: 0, 1, 2.

Точный список возможных значений для конкретной точки
уточняйте с помощью метода получения тарифов [tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md).


_Min value:_{.json-schema-reset .json-schema-assertion} `0`
{.table-cell}
||
||

_cargo_options_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CargoOptions](#entity-CargoOptions)

Список дополнительных опций тарифа.

Возможные отдельные опции:
  - auto_courier (курьер только на автомобиле)
  - thermobag (курьер с термосумкой)

Пример списка опций: ["auto_courier"].

Точный список возможных значений для конкретной геоточки
уточните с помощью метода получения тарифов [tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md)


{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  "thermobag"
]
```

{% endcut %}
{.table-cell}
||
||

_cargo_type_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CargoType](#entity-CargoType)

Тип (размер) кузова для грузового тарифа.
Возможные значения:
- van ("Маленький кузов")
- lcv_m ("Средний кузов")
- lcv_l ("Большой кузов")
- lcv_xl ("Кузов XL")
Точный список возможных значений для конкретной геоточки уточняйте с помощью метода получения тарифов [tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md)


_Enum:_{.json-schema-reset .json-schema-value} `van`, `lcv_m`, `lcv_l`, `lcv_xl`
{.table-cell}
||
||

_pro_courier_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Включить опцию "Профи" для тарифов "Экспресс" и "Курьер".
Поиск исполнителя будет происходить только среди опытных курьеров.

{.table-cell}
||
||

_rental_duration_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: integer

Время аренды, которое планирует клиент. Указывается в минутах.
Указывайте этот параметр только для почасового тарифа

{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "taxi_class": "express",
  "cargo_type": "lcv_m",
  "cargo_loaders": 0,
  "cargo_options": [
    "thermobag"
  ],
  "pro_courier": false,
  "assign_robot": true,
  "rental_duration": 0
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### CallbackProperties {#entity-CallbackProperties}

Параметры уведомления сервера клиента о смене статуса заявки.

Уведомление представляет собой POST-запрос по указанному url, к
которому будут добавлены информация о дате последнего изменения
заявки и идентификатора заявки в виде
'updated_ts=<ISO-8601>&claim_id=<id заявки>', то есть url вида
'https://example.com/?my_order_id=123&' будет расширен до
'https://example.com/?my_order_id=123&updated_ts=...&claim_id=...'.

Важно: параметры добавляются конкатенацией к callback_url, то есть
url вида 'https://example.com' превратится в невалидный
'https://example.comupdated_ts=...&claim_id=...'.


Поддерживаются только http и https. При https ssl-сертификат должен
быть выдан известным серверу центром сертификации.

К уведомлениям следует относиться как к push ahead of polling, как
к ускорению получения информации о смене статусов. Сервер ожидает
ответ 200, при таймаутах или любом другом ответе какое-то время
будет пытаться доставить уведомление, после чего прекратит попытки.
То есть для надежного получения статуса по заявке клиенту
необходимо запрашивать информацию с помощью метода [claims/info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md).

Клиенту следует учесть, что ответ операции [claims/info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md) может
содержать более старое состояние заявки (надо ориентироваться на
значение поля updated_ts). В этом случает необходимо повторить
вызов операции через некоторое время (от 5 до 30 секунд).


#|
|| **Name** | **Description** ||
||

_callback_url_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

URL, который вызывается при смене статусов по заявке.

Этот механизм устарел и может быть ненадежен, рекомендуем использовать в связке с [claims/journal](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsJournal.md)


_Pattern:_{.json-schema-reset .json-schema-assertion} `^https?:.*`

_Example:_{.json-schema-reset .json-schema-example} `https://www.example.com/`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "callback_url": "https://www.example.com/"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### SkipDoorToDoor {#entity-SkipDoorToDoor}

Отключить доставку до двери (выключить опцию "От двери до двери").

Возможные значения:
  - true (курьер доставит заказ только на улицу, до подъезда)
  - false (курьер доставит до двери) - значение по умолчанию


**Type**: boolean

_Default:_{.json-schema-reset .json-schema-value} `false`

</div>

<div class="openapi-entity">

### SkipClientNotify {#entity-SkipClientNotify}

Не отправлять отправителю/получателю смс-уведомления,
когда к нему направится курьер.

Значение по умолчанию: false (отправлять уведомления)


**Type**: boolean

_Default:_{.json-schema-reset .json-schema-value} `false`

</div>

<div class="openapi-entity">

### SkipEmergencyNotify {#entity-SkipEmergencyNotify}

Не отправлять уведомление запасному контактному лицу

Значение по умолчанию: false (отправлять уведомления)


**Type**: boolean

_Default:_{.json-schema-reset .json-schema-value} `false`

</div>

<div class="openapi-entity">

### SkipAct {#entity-SkipAct}

Не показывать акт приема-передачи

**Type**: boolean

</div>

<div class="openapi-entity">

### OptionalReturn {#entity-OptionalReturn}

Отключить возврат товаров в случае отмены заказа.

Возможные значения:
  - true (курьер оставляет товар себе)
  - false (по умолчанию, требуется вернуть товар)


**Type**: boolean

_Default:_{.json-schema-reset .json-schema-value} `false`

</div>

<div class="openapi-entity">

### Due {#entity-Due}

Желаемое время прибытия исполнителя на точку А (source).
В РФ отложить расчетное время прибытия исполнителя можно:
    - на 30-240 минут от текущего момента – для тарифа `express`;
    - на пять суток от текущего момента – для тарифа `cargo`.

Параметр не совместим с опциями замедления в тарифе `express` на территории РФ.
Если этот параметр не задан, то запустится поиск исполнителя на ближайшее время.


**Type**: string&lt;date-time&gt;

_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T00:00:00+00:00`

</div>

<div class="openapi-entity">

### SameDayData {#entity-SameDayData}

Дополнительная информация для заявок `В течение дня`. Недоступно в России

#|
|| **Name** | **Description** ||
||

_delivery_interval_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
{% cut "**Type**: object" %}

#|
||

_from_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Начало интервала

_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T07:00:00+00:00`
{.table-cell}
||
||

_to_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Окончание интервала (дата и время)

_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T07:00:00+00:00`
{.table-cell}
||
|#{.json-schema-properties}

{% endcut %}

Интервал забора и доставки заказа

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "from": "2020-01-01T07:00:00+00:00",
  "to": "2020-01-01T07:00:00+00:00"
}
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "delivery_interval": {
    "from": "2020-01-01T07:00:00+00:00",
    "to": "2020-01-01T07:00:00+00:00"
  }
}
```

{% endcut %}

</div>

## Responses

<div class="openapi__response__code__200">

## 200 OK

Заявка изменена

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "id": "741cedf82cd464fa6fa16d87155c636",
  "corp_client_id": "cd8cc018bde34597932855e3cfdce927",
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
  ],
  "packages": [
    {
      "package_id": "a8e5b0e6-3d67-4d6f-89a5-3b6c1a0e4f5c",
      "package_type": "other",
      "package_code": "ab10702030/?",
      "pickup_point": 1,
      "dropoff_point": 2
    }
  ],
  "route_points": [
    {
      "id": 1,
      "contact": {
        "name": "Морти",
        "phone": "+79099999998",
        "phone_additional_code": "602 17 500",
        "email": "example@yandex.ru"
      },
      "address": {
        "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
        "shortname": "Большая Монетная улица, 1к1А",
        "coordinates": [
          0.5,
          0.5
        ],
        "country": "Россия",
        "city": "Санкт-Петербург",
        "building_name": "БЦ На Большой Монетной",
        "street": "Большая Монетная улица",
        "building": "23к1А",
        "porch": "A",
        "sfloor": "1",
        "sflat": "1",
        "door_code": "169",
        "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
        "doorbell_name": "Магидович",
        "comment": "Домофон не работает",
        "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
        "description": "Санкт-Петербург, Россия"
      },
      "type": "source",
      "visit_order": 1,
      "visit_status": "pending",
      "skip_confirmation": false,
      "leave_under_door": true,
      "meet_outside": true,
      "no_door_call": true,
      "payment_on_delivery": {
        "payment_ref_id": "123e4567-e89b-12d3-a456-426614174000",
        "client_order_id": "100",
        "is_paid": false,
        "customer": {
          "full_name": "Морти",
          "inn": "3664069397",
          "email": "example@yandex.ru",
          "phone": "79000000000"
        },
        "payment_method": "card",
        "invoice_link": "https://ofd.yandex.ru/vaucher/0005312316002718/9410/2604520024"
      },
      "external_order_id": "100",
      "external_order_cost": {
        "value": "100.0",
        "currency": "RUB",
        "currency_sign": "₽"
      },
      "expected_visit_interval": {
        "from": "2020-01-01T00:00:00+00:00",
        "to": "2020-01-02T00:00:00+00:00"
      },
      "pickup_code": "893422",
      "return_reasons": [
        "example"
      ],
      "return_comment": "example",
      "visited_at": {
        "expected": "2025-01-01T00:00:00Z",
        "expected_waiting_time_sec": 0,
        "actual": "2025-01-01T00:00:00Z"
      },
      "handover_status": "pending"
    },
    {
      "id": 1,
      "contact": {
        "name": "Морти",
        "phone": "+79099999998",
        "phone_additional_code": "602 17 500",
        "email": "example@yandex.ru"
      },
      "address": {
        "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
        "shortname": "Большая Монетная улица, 1к1А",
        "coordinates": [
          0.5,
          0.5
        ],
        "country": "Россия",
        "city": "Санкт-Петербург",
        "building_name": "БЦ На Большой Монетной",
        "street": "Большая Монетная улица",
        "building": "23к1А",
        "porch": "A",
        "sfloor": "1",
        "sflat": "1",
        "door_code": "169",
        "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
        "doorbell_name": "Магидович",
        "comment": "Домофон не работает",
        "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
        "description": "Санкт-Петербург, Россия"
      },
      "type": "source",
      "visit_order": 1,
      "visit_status": "pending",
      "skip_confirmation": false,
      "leave_under_door": true,
      "meet_outside": true,
      "no_door_call": true,
      "payment_on_delivery": {
        "payment_ref_id": "123e4567-e89b-12d3-a456-426614174000",
        "client_order_id": "100",
        "is_paid": false,
        "customer": {
          "full_name": "Морти",
          "inn": "3664069397",
          "email": "example@yandex.ru",
          "phone": "79000000000"
        },
        "payment_method": "card",
        "invoice_link": "https://ofd.yandex.ru/vaucher/0005312316002718/9410/2604520024"
      },
      "external_order_id": "100",
      "external_order_cost": {
        "value": "100.0",
        "currency": "RUB",
        "currency_sign": "₽"
      },
      "expected_visit_interval": {
        "from": "2020-01-01T00:00:00+00:00",
        "to": "2020-01-02T00:00:00+00:00"
      },
      "pickup_code": "893422",
      "return_reasons": [
        "example"
      ],
      "return_comment": "example",
      "visited_at": {
        "expected": "2025-01-01T00:00:00Z",
        "expected_waiting_time_sec": 0,
        "actual": "2025-01-01T00:00:00Z"
      },
      "handover_status": "pending"
    }
  ],
  "current_point_id": 372036854775807,
  "status": "new",
  "version": 0,
  "user_request_revision": "example",
  "error_messages": [
    {
      "code": "some_error",
      "message": "Some error"
    }
  ],
  "emergency_contact": {
    "name": "Рик",
    "phone": "+79826810246",
    "phone_additional_code": "602 17 500"
  },
  "skip_door_to_door": false,
  "skip_client_notify": false,
  "skip_emergency_notify": false,
  "skip_act": false,
  "optional_return": false,
  "eta": 10,
  "created_ts": "2020-01-01T00:00:00+00:00",
  "updated_ts": "2020-01-01T00:00:00+00:00",
  "last_status_change_ts": "2020-01-01T00:00:00+00:00",
  "pricing": {
    "offer": {
      "offer_id": "28ae5f1d72364468be3f5e26cd6a66bf",
      "price": null,
      "valid_until": "2020-01-01T00:00:00+00:00",
      "price_with_vat": null
    },
    "currency": "RUB",
    "currency_rules": {
      "code": null,
      "text": "руб.",
      "template": "$VALUE$ $SIGN$$CURRENCY$",
      "sign": "₽"
    },
    "final_pricing_calc_id": "example",
    "final_price": null
  },
  "client_requirements": {
    "taxi_class": "express",
    "cargo_type": "lcv_m",
    "cargo_loaders": 0,
    "cargo_options": [
      "thermobag"
    ],
    "pro_courier": false,
    "assign_robot": true,
    "rental_duration": 0
  },
  "matched_cars": [
    {
      "taxi_class": "express",
      "client_taxi_class": "cargo",
      "cargo_type": "lcv_m",
      "cargo_type_int": "2 is equal to \"lcv_m\"",
      "cargo_loaders": 0,
      "door_to_door": false,
      "pro_courier": false
    }
  ],
  "warnings": [
    {
      "source": "client_requirements",
      "code": "not_fit_in_car",
      "message": "предупреждение"
    }
  ],
  "performer_info": {
    "courier_name": "Личность",
    "legal_name": "ИП Птичья личность",
    "car_model": "Hyundai Solaris",
    "car_number": "А100РА100",
    "car_color": "красный",
    "car_color_hex": "FF00000",
    "transport_type": "car"
  },
  "callback_properties": {
    "callback_url": "https://www.example.com/"
  },
  "due": "2020-01-01T00:00:00+00:00",
  "shipping_document": "example",
  "comment": "Ресторан",
  "revision": 1,
  "route_id": "example",
  "same_day_data": {
    "delivery_interval": {
      "from": "2020-01-01T07:00:00+00:00",
      "to": "2020-01-01T07:00:00+00:00"
    }
  },
  "performer_cancel_reasons": [
    "example"
  ]
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_created_ts_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Дата и время создания заявки

_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T00:00:00+00:00`
{.table-cell}
||
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

_items_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [V2CargoItem](#entity-V2CargoItem)[]

Параметры товаров

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

_revision_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Ревизия (int64)
{.table-cell}
||
||

_route_points_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [V2ResponseCargoRoutePoints](#entity-V2ResponseCargoRoutePoints)

Информация по точкам маршрута

_Min items:_{.json-schema-reset .json-schema-assertion} `2`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "id": 1,
    "contact": {
      "name": "Морти",
      "phone": "+79099999998",
      "phone_additional_code": "602 17 500",
      "email": "example@yandex.ru"
    },
    "address": {
      "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
      "shortname": "Большая Монетная улица, 1к1А",
      "coordinates": [
        0.5,
        0.5
      ],
      "country": "Россия",
      "city": "Санкт-Петербург",
      "building_name": "БЦ На Большой Монетной",
      "street": "Большая Монетная улица",
      "building": "23к1А",
      "porch": "A",
      "sfloor": "1",
      "sflat": "1",
      "door_code": "169",
      "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
      "doorbell_name": "Магидович",
      "comment": "Домофон не работает",
      "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
      "description": "Санкт-Петербург, Россия"
    },
    "type": "source",
    "visit_order": 1,
    "visit_status": "pending",
    "skip_confirmation": false,
    "leave_under_door": true,
    "meet_outside": true,
    "no_door_call": true,
    "payment_on_delivery": {
      "payment_ref_id": "123e4567-e89b-12d3-a456-426614174000",
      "client_order_id": "100",
      "is_paid": false,
      "customer": {
        "full_name": "Морти",
        "inn": "3664069397",
        "email": "example@yandex.ru",
        "phone": "79000000000"
      },
      "payment_method": "card",
      "invoice_link": "https://ofd.yandex.ru/vaucher/0005312316002718/9410/2604520024"
    },
    "external_order_id": "100",
    "external_order_cost": {
      "value": "100.0",
      "currency": "RUB",
      "currency_sign": "₽"
    },
    "expected_visit_interval": {
      "from": "2020-01-01T00:00:00+00:00",
      "to": "2020-01-02T00:00:00+00:00"
    },
    "pickup_code": "893422",
    "return_reasons": [
      "example"
    ],
    "return_comment": "example",
    "visited_at": {
      "expected": "2025-01-01T00:00:00Z",
      "expected_waiting_time_sec": 0,
      "actual": "2025-01-01T00:00:00Z"
    },
    "handover_status": "pending"
  },
  {
    "id": 1,
    "contact": {
      "name": "Морти",
      "phone": "+79099999998",
      "phone_additional_code": "602 17 500",
      "email": "example@yandex.ru"
    },
    "address": {
      "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
      "shortname": "Большая Монетная улица, 1к1А",
      "coordinates": [
        0.5,
        0.5
      ],
      "country": "Россия",
      "city": "Санкт-Петербург",
      "building_name": "БЦ На Большой Монетной",
      "street": "Большая Монетная улица",
      "building": "23к1А",
      "porch": "A",
      "sfloor": "1",
      "sflat": "1",
      "door_code": "169",
      "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
      "doorbell_name": "Магидович",
      "comment": "Домофон не работает",
      "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
      "description": "Санкт-Петербург, Россия"
    },
    "type": "source",
    "visit_order": 1,
    "visit_status": "pending",
    "skip_confirmation": false,
    "leave_under_door": true,
    "meet_outside": true,
    "no_door_call": true,
    "payment_on_delivery": {
      "payment_ref_id": "123e4567-e89b-12d3-a456-426614174000",
      "client_order_id": "100",
      "is_paid": false,
      "customer": {
        "full_name": "Морти",
        "inn": "3664069397",
        "email": "example@yandex.ru",
        "phone": "79000000000"
      },
      "payment_method": "card",
      "invoice_link": "https://ofd.yandex.ru/vaucher/0005312316002718/9410/2604520024"
    },
    "external_order_id": "100",
    "external_order_cost": {
      "value": "100.0",
      "currency": "RUB",
      "currency_sign": "₽"
    },
    "expected_visit_interval": {
      "from": "2020-01-01T00:00:00+00:00",
      "to": "2020-01-02T00:00:00+00:00"
    },
    "pickup_code": "893422",
    "return_reasons": [
      "example"
    ],
    "return_comment": "example",
    "visited_at": {
      "expected": "2025-01-01T00:00:00Z",
      "expected_waiting_time_sec": 0,
      "actual": "2025-01-01T00:00:00Z"
    },
    "handover_status": "pending"
  }
]
```

{% endcut %}
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

_updated_ts_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Дата и время последнего обновления заявки

_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T00:00:00+00:00`
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

Версия (int64)
{.table-cell}
||
||

_callback_properties_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CallbackProperties](#entity-CallbackProperties)

Параметры уведомления сервера клиента о смене статуса заявки.

Уведомление представляет собой POST-запрос по указанному url, к
которому будут добавлены информация о дате последнего изменения
заявки и идентификатора заявки в виде
'updated_ts=<ISO-8601>&claim_id=<id заявки>', то есть url вида
'https://example.com/?my_order_id=123&' будет расширен до
'https://example.com/?my_order_id=123&updated_ts=...&claim_id=...'.

Важно: параметры добавляются конкатенацией к callback_url, то есть
url вида 'https://example.com' превратится в невалидный
'https://example.comupdated_ts=...&claim_id=...'.


Поддерживаются только http и https. При https ssl-сертификат должен
быть выдан известным серверу центром сертификации.

К уведомлениям следует относиться как к push ahead of polling, как
к ускорению получения информации о смене статусов. Сервер ожидает
ответ 200, при таймаутах или любом другом ответе какое-то время
будет пытаться доставить уведомление, после чего прекратит попытки.
То есть для надежного получения статуса по заявке клиенту
необходимо запрашивать информацию с помощью метода [claims/info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md).

Клиенту следует учесть, что ответ операции [claims/info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md) может
содержать более старое состояние заявки (надо ориентироваться на
значение поля updated_ts). В этом случает необходимо повторить
вызов операции через некоторое время (от 5 до 30 секунд).


{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "callback_url": "https://www.example.com/"
}
```

{% endcut %}
{.table-cell}
||
||

_client_requirements_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ClientRequirements](#entity-ClientRequirements)

Требования от клиента, указанные при создании или редактировании заявки

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "taxi_class": "express",
  "cargo_type": "lcv_m",
  "cargo_loaders": 0,
  "cargo_options": [
    "thermobag"
  ],
  "pro_courier": false,
  "assign_robot": true,
  "rental_duration": 0
}
```

{% endcut %}
{.table-cell}
||
||

_comment_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Общий комментарий к заказу

_Example:_{.json-schema-reset .json-schema-example} `Ресторан`
{.table-cell}
||
||

_corp_client_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CorpClientId](#entity-CorpClientId)

Идентификатор корпоративного клиента Яндекс Доставки (из OAuth-токена)

_Min length:_{.json-schema-reset .json-schema-assertion} `32`

_Max length:_{.json-schema-reset .json-schema-assertion} `32`

_Example:_{.json-schema-reset .json-schema-example} `cd8cc018bde34597932855e3cfdce927`
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

_due_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Due](#entity-Due)

Желаемое время прибытия исполнителя на точку А (source).
В РФ отложить расчетное время прибытия исполнителя можно:
    - на 30-240 минут от текущего момента – для тарифа `express`;
    - на пять суток от текущего момента – для тарифа `cargo`.

Параметр не совместим с опциями замедления в тарифе `express` на территории РФ.
Если этот параметр не задан, то запустится поиск исполнителя на ближайшее время.


_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T00:00:00+00:00`
{.table-cell}
||
||

_emergency_contact_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ContactWithPhone](#entity-ContactWithPhone)

Информация о контактном лице с номером телефона

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "name": "Рик",
  "phone": "+79826810246",
  "phone_additional_code": "602 17 500"
}
```

{% endcut %}
{.table-cell}
||
||

_error_messages_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [HumanErrorMessage](#entity-HumanErrorMessage)[]

Список сообщений об ошибках

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "code": "some_error",
    "message": "Some error"
  }
]
```

{% endcut %}
{.table-cell}
||
||

_eta_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Eta](#entity-Eta)

Расчетное время выполнения заказа в минутах (int64)

_Example:_{.json-schema-reset .json-schema-example} `10`
{.table-cell}
||
||

_last_status_change_ts_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Дата-время последнего изменения статуса

_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T00:00:00+00:00`
{.table-cell}
||
||

_matched_cars_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [MatchedCar](#entity-MatchedCar)[]

Информация о подобранном тарифе

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "taxi_class": "express",
    "client_taxi_class": "cargo",
    "cargo_type": "lcv_m",
    "cargo_type_int": "2 is equal to \"lcv_m\"",
    "cargo_loaders": 0,
    "door_to_door": false,
    "pro_courier": false
  }
]
```

{% endcut %}
{.table-cell}
||
||

_optional_return_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [OptionalReturn](#entity-OptionalReturn)

Отключить возврат товаров в случае отмены заказа.

Возможные значения:
  - true (курьер оставляет товар себе)
  - false (по умолчанию, требуется вернуть товар)


_Default:_{.json-schema-reset .json-schema-value} `false`

_Example:_{.json-schema-reset .json-schema-example} `false`
{.table-cell}
||
||

_packages_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Package](#entity-Package)[]

Список грузомест

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

_performer_cancel_reasons_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string[]

Причины, по которым курьер отменил доставку заказа


{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  "example"
]
```

{% endcut %}
{.table-cell}
||
||

_performer_info_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [PerformerInfo](#entity-PerformerInfo)

Информация об исполнителе

Информация о курьере

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "courier_name": "Личность",
  "legal_name": "ИП Птичья личность",
  "car_model": "Hyundai Solaris",
  "car_number": "А100РА100",
  "car_color": "красный",
  "car_color_hex": "FF00000",
  "transport_type": "car"
}
```

{% endcut %}
{.table-cell}
||
||

_pricing_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ClaimPricing](#entity-ClaimPricing)

Информация о стоимости заказа

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "offer": {
    "offer_id": "28ae5f1d72364468be3f5e26cd6a66bf",
    "price": "12.50",
    "valid_until": "2020-01-01T00:00:00+00:00",
    "price_with_vat": null
  },
  "currency": "RUB",
  "currency_rules": {
    "code": "RUB",
    "text": "руб.",
    "template": "$VALUE$ $SIGN$$CURRENCY$",
    "sign": "₽"
  },
  "final_pricing_calc_id": "example",
  "final_price": null
}
```

{% endcut %}
{.table-cell}
||
||

_route_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Идентификатор машрута, в рамках которого доставляется заказ
Если несколько заказов доставляются одним курьером,
они будут иметь одинаковый route_id
(Актуально только для доставки "В течение дня")


_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_same_day_data_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [SameDayData](#entity-SameDayData)

Дополнительная информация для заявок `В течение дня`. Недоступно в России

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "delivery_interval": {
    "from": "2020-01-01T07:00:00+00:00",
    "to": "2020-01-01T07:00:00+00:00"
  }
}
```

{% endcut %}
{.table-cell}
||
||

_shipping_document_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Сопроводительные документы

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_skip_act_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [SkipAct](#entity-SkipAct)

Не показывать акт приема-передачи

_Example:_{.json-schema-reset .json-schema-example} `false`
{.table-cell}
||
||

_skip_client_notify_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [SkipClientNotify](#entity-SkipClientNotify)

Не отправлять отправителю/получателю смс-уведомления,
когда к нему направится курьер.

Значение по умолчанию: false (отправлять уведомления)


_Default:_{.json-schema-reset .json-schema-value} `false`

_Example:_{.json-schema-reset .json-schema-example} `false`
{.table-cell}
||
||

_skip_door_to_door_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [SkipDoorToDoor](#entity-SkipDoorToDoor)

Отключить доставку до двери (выключить опцию "От двери до двери").

Возможные значения:
  - true (курьер доставит заказ только на улицу, до подъезда)
  - false (курьер доставит до двери) - значение по умолчанию


_Default:_{.json-schema-reset .json-schema-value} `false`

_Example:_{.json-schema-reset .json-schema-example} `false`
{.table-cell}
||
||

_skip_emergency_notify_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [SkipEmergencyNotify](#entity-SkipEmergencyNotify)

Не отправлять уведомление запасному контактному лицу

Значение по умолчанию: false (отправлять уведомления)


_Default:_{.json-schema-reset .json-schema-value} `false`

_Example:_{.json-schema-reset .json-schema-example} `false`
{.table-cell}
||
||

_warnings_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ClaimWarning](#entity-ClaimWarning)[]

Предупреждения по ходу обработки заявки

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "source": "client_requirements",
    "code": "not_fit_in_car",
    "message": "предупреждение"
  }
]
```

{% endcut %}
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

### CorpClientId {#entity-CorpClientId}

Идентификатор корпоративного клиента Яндекс Доставки (из OAuth-токена)

**Type**: string

_Min length:_{.json-schema-reset .json-schema-assertion} `32`

_Max length:_{.json-schema-reset .json-schema-assertion} `32`

_Example:_{.json-schema-reset .json-schema-example} `cd8cc018bde34597932855e3cfdce927`

</div>

<div class="openapi-entity">

### CargoPointAddress {#entity-CargoPointAddress}

Адрес точки

#|
|| **Name** | **Description** ||
||

_fullname_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [AddressFullname](#entity-AddressFullname)

Полный адрес с указанием города, улицы и номера дома.
Номер квартиры, подъезда и этаж указывать не нужно.


_Example:_{.json-schema-reset .json-schema-example} `Санкт-Петербург, Большая Монетная улица, 1к1А`
{.table-cell}
||
||

_building_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Строение

_Example:_{.json-schema-reset .json-schema-example} `23к1А`
{.table-cell}
||
||

_building_name_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Название апартаментов (здания)

_Example:_{.json-schema-reset .json-schema-example} `БЦ На Большой Монетной`
{.table-cell}
||
||

_city_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Город

_Example:_{.json-schema-reset .json-schema-example} `Санкт-Петербург`
{.table-cell}
||
||

_comment_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Комментарий для курьера.

Для точки отправки используйте шаблон: "Доставка из магазина <>. Сообщите менеджеру, что заказ для Яндекс Доставки. Назовите номер заказа <> и заберите товар. Заказ оплачен безналично, при передаче заказа нельзя требовать с получателя деньги за доставку."

Для точек доставки в комментарии передавайте пожелания получателя. Например, "домофон не работает" / "шлагбаум закрыт, позвонить за 10 минут" / "не звонить, спит ребенок".


_Max length:_{.json-schema-reset .json-schema-assertion} `7000`

_Example:_{.json-schema-reset .json-schema-example} `Домофон не работает`
{.table-cell}
||
||

_coordinates_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: number[]

Координаты точек в виде массива из двух вещественных чисел: долгота, широта — именно в таком порядке.
Указываются округленные значения координат.


_Min items:_{.json-schema-reset .json-schema-assertion} `2`

_Max items:_{.json-schema-reset .json-schema-assertion} `2`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  0.5,
  0.5
]
```

{% endcut %}
{.table-cell}
||
||

_country_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Страна

_Example:_{.json-schema-reset .json-schema-example} `Россия`
{.table-cell}
||
||

_description_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Географическая область, уточняющая краткий адрес до глобального соответствия

_Example:_{.json-schema-reset .json-schema-example} `Санкт-Петербург, Россия`
{.table-cell}
||
||

_door_code_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Код домофона

_Example:_{.json-schema-reset .json-schema-example} `169`
{.table-cell}
||
||

_door_code_extra_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Дополнительные указания по домофонам

_Example:_{.json-schema-reset .json-schema-example} `код на вход во двор #1234, код от апартаментов #4321`
{.table-cell}
||
||

_doorbell_name_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Имя на дверном звонке

_Example:_{.json-schema-reset .json-schema-example} `Магидович`
{.table-cell}
||
||

_porch_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Подъезд (может быть A)

_Example:_{.json-schema-reset .json-schema-example} `A`
{.table-cell}
||
||

_sflat_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Квартира

_Example:_{.json-schema-reset .json-schema-example} `1`
{.table-cell}
||
||

_sfloor_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Этаж

_Example:_{.json-schema-reset .json-schema-example} `1`
{.table-cell}
||
||

_shortname_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Краткий адрес в пределах города (как на Таксометре)


_Example:_{.json-schema-reset .json-schema-example} `Большая Монетная улица, 1к1А`
{.table-cell}
||
||

_street_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Улица

_Example:_{.json-schema-reset .json-schema-example} `Большая Монетная улица`
{.table-cell}
||
||

_uri_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

URI геообъекта на картах

_Example:_{.json-schema-reset .json-schema-example} `ymapsbm1://geo?ll=38.805%2C55.084`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
  "shortname": "Большая Монетная улица, 1к1А",
  "coordinates": [
    0.5,
    0.5
  ],
  "country": "Россия",
  "city": "Санкт-Петербург",
  "building_name": "БЦ На Большой Монетной",
  "street": "Большая Монетная улица",
  "building": "23к1А",
  "porch": "A",
  "sfloor": "1",
  "sflat": "1",
  "door_code": "169",
  "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
  "doorbell_name": "Магидович",
  "comment": "Домофон не работает",
  "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
  "description": "Санкт-Петербург, Россия"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### PointVisitStatus {#entity-PointVisitStatus}

Статус посещения точки:
- pending - точка еще не посещена;
- arrived - курьер прибыл на точку;
- visited - курьер передал/забрал груз на точке;
- skipped - точка пропущена (в случае, если не смог принять товар).


**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `pending`, `arrived`, `visited`, `skipped`

</div>

<div class="openapi-entity">

### PaymentId {#entity-PaymentId}

Идентификатор оплаты

**Type**: string&lt;uuid&gt;

_Example:_{.json-schema-reset .json-schema-example} `123e4567-e89b-12d3-a456-426614174000`

</div>

<div class="openapi-entity">

### ClientOrderId {#entity-ClientOrderId}

Внешний идентификатор клиентского заказа

**Type**: string

_Example:_{.json-schema-reset .json-schema-example} `100`

</div>

<div class="openapi-entity">

### PaymentComplete {#entity-PaymentComplete}

Признак оплаты заказа

**Type**: boolean

</div>

<div class="openapi-entity">

### CustomerFiscalization {#entity-CustomerFiscalization}

Информация о клиенте(получателе)

#|
|| **Name** | **Description** ||
||

_email_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Электронная почта пользователя. Если не указано, будет использована почта получателя из точки назначения

_Example:_{.json-schema-reset .json-schema-example} `example@yandex.ru`
{.table-cell}
||
||

_full_name_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Для юридического лица — название организации, для ИП и физического лица — ФИО

_Example:_{.json-schema-reset .json-schema-example} `Морти`
{.table-cell}
||
||

_inn_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Inn](#entity-Inn)

ИНН пользователя (10 или 12 цифр)

_Pattern:_{.json-schema-reset .json-schema-assertion} `^[A-Z0-9\\-]+$`

_Example:_{.json-schema-reset .json-schema-example} `3664069397`
{.table-cell}
||
||

_phone_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Телефон пользователя в формате +X XXX XXX XX XX. Если не указано, будет использован телефон получателя из точки назначения

_Example:_{.json-schema-reset .json-schema-example} `79000000000`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "full_name": "Морти",
  "inn": "3664069397",
  "email": "example@yandex.ru",
  "phone": "79000000000"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### InvoiceLink {#entity-InvoiceLink}

Ссылка на чек

**Type**: string

_Example:_{.json-schema-reset .json-schema-example} `https://ofd.yandex.ru/vaucher/0005312316002718/9410/2604520024`

</div>

<div class="openapi-entity">

### ResponsePaymentOnDelivery {#entity-ResponsePaymentOnDelivery}

Параметры оплаты при получении

#|
|| **Name** | **Description** ||
||

_is_paid_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [PaymentComplete](#entity-PaymentComplete)

Признак оплаты заказа

_Example:_{.json-schema-reset .json-schema-example} `false`
{.table-cell}
||
||

_client_order_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ClientOrderId](#entity-ClientOrderId)

Внешний идентификатор клиентского заказа

_Example:_{.json-schema-reset .json-schema-example} `100`
{.table-cell}
||
||

_customer_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CustomerFiscalization](#entity-CustomerFiscalization)

Информация о клиенте(получателе)

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "full_name": "Морти",
  "inn": "3664069397",
  "email": "example@yandex.ru",
  "phone": "79000000000"
}
```

{% endcut %}
{.table-cell}
||
||

_invoice_link_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [InvoiceLink](#entity-InvoiceLink)

Ссылка на чек

_Example:_{.json-schema-reset .json-schema-example} `https://ofd.yandex.ru/vaucher/0005312316002718/9410/2604520024`
{.table-cell}
||
||

_payment_method_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [PaymentMethod](#entity-PaymentMethod)

Выбранный тип оплаты.
card - оплата картой;
cash - оплата наличными (пока недоступна);


_Enum:_{.json-schema-reset .json-schema-value} `card`, `cash`
{.table-cell}
||
||

_payment_ref_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [PaymentId](#entity-PaymentId)

Идентификатор оплаты

_Example:_{.json-schema-reset .json-schema-example} `123e4567-e89b-12d3-a456-426614174000`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "payment_ref_id": "123e4567-e89b-12d3-a456-426614174000",
  "client_order_id": "100",
  "is_paid": false,
  "customer": {
    "full_name": "Морти",
    "inn": "3664069397",
    "email": "example@yandex.ru",
    "phone": "79000000000"
  },
  "payment_method": "card",
  "invoice_link": "https://ofd.yandex.ru/vaucher/0005312316002718/9410/2604520024"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ExpectedVisitInterval {#entity-ExpectedVisitInterval}

Временной интервал посещения курьером точки согласно выбранному офферу

#|
|| **Name** | **Description** ||
||

_from_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Начало интервала

_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T00:00:00+00:00`
{.table-cell}
||
||

_to_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Окончание интервала

_Example:_{.json-schema-reset .json-schema-example} `2020-01-02T00:00:00+00:00`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "from": "2020-01-01T00:00:00+00:00",
  "to": "2020-01-02T00:00:00+00:00"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### PointVisitTime {#entity-PointVisitTime}

Информация о времени посещения точки

#|
|| **Name** | **Description** ||
||

_actual_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Фактическое время посещения точки.
Заполняется только для посещенных точек.


_Example:_{.json-schema-reset .json-schema-example} `2025-01-01T00:00:00Z`
{.table-cell}
||
||

_expected_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Расчетное время посещения. Может быть заполнено
только для непосещенных точек.


_Example:_{.json-schema-reset .json-schema-example} `2025-01-01T00:00:00Z`
{.table-cell}
||
||

_expected_waiting_time_sec_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: integer

Расчетное время ожидания в точке. (int64)
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "expected": "2025-01-01T00:00:00Z",
  "expected_waiting_time_sec": 0,
  "actual": "2025-01-01T00:00:00Z"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### HandoverStatusOnPoint {#entity-HandoverStatusOnPoint}

Статус передачи груза роботом доставщиком

**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `pending`, `ready`, `initializing`, `initialized`, `finishing`, `completed`, `skipped`

</div>

<div class="openapi-entity">

### V2ResponseCargoPoint {#entity-V2ResponseCargoPoint}

Информация по точкам маршрута

#|
|| **Name** | **Description** ||
||

_address_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [CargoPointAddress](#entity-CargoPointAddress)

Адрес точки

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
  "shortname": "Большая Монетная улица, 1к1А",
  "coordinates": [
    0.5,
    0.5
  ],
  "country": "Россия",
  "city": "Санкт-Петербург",
  "building_name": "БЦ На Большой Монетной",
  "street": "Большая Монетная улица",
  "building": "23к1А",
  "porch": "A",
  "sfloor": "1",
  "sflat": "1",
  "door_code": "169",
  "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
  "doorbell_name": "Магидович",
  "comment": "Домофон не работает",
  "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
  "description": "Санкт-Петербург, Россия"
}
```

{% endcut %}
{.table-cell}
||
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

_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Целочисленный идентификатор точки (int64)
{.table-cell}
||
||

_type_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [PointType](#entity-PointType)

Тип точки:
  - source - точка отправления, где курьер забирает товар
  - destination – точки назначения, где курьер передает товар
  - return - точка возврата товара (добавляется автоматически и по умолчанию совпадает с точкой отправления, но также можно определить другую точку)


_Enum:_{.json-schema-reset .json-schema-value} `source`, `destination`, `return`
{.table-cell}
||
||

_visit_order_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: integer

Порядок посещения точки (нумерация начинается с 1) (int64)
{.table-cell}
||
||

_visit_status_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [PointVisitStatus](#entity-PointVisitStatus)

Статус посещения точки:
- pending - точка еще не посещена;
- arrived - курьер прибыл на точку;
- visited - курьер передал/забрал груз на точке;
- skipped - точка пропущена (в случае, если не смог принять товар).


_Enum:_{.json-schema-reset .json-schema-value} `pending`, `arrived`, `visited`, `skipped`
{.table-cell}
||
||

_visited_at_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [PointVisitTime](#entity-PointVisitTime)

Информация о времени посещения точки

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "expected": "2025-01-01T00:00:00Z",
  "expected_waiting_time_sec": 0,
  "actual": "2025-01-01T00:00:00Z"
}
```

{% endcut %}
{.table-cell}
||
||

_expected_visit_interval_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ExpectedVisitInterval](#entity-ExpectedVisitInterval)

Временной интервал посещения курьером точки согласно выбранному офферу

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "from": "2020-01-01T00:00:00+00:00",
  "to": "2020-01-02T00:00:00+00:00"
}
```

{% endcut %}
{.table-cell}
||
||

_external_order_cost_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ExternalOrderCost](#entity-ExternalOrderCost)

Стоимость внешнего заказа, привязанного к точке

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "value": "100.0",
  "currency": "RUB",
  "currency_sign": "₽"
}
```

{% endcut %}
{.table-cell}
||
||

_external_order_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Номер заказа из системы клиента.
Передается для точки типа destination


_Example:_{.json-schema-reset .json-schema-example} `100`
{.table-cell}
||
||

_handover_status_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [HandoverStatusOnPoint](#entity-HandoverStatusOnPoint)

Статус передачи груза роботом доставщиком

_Enum:_{.json-schema-reset .json-schema-value} `pending`, `ready`, `initializing`, `initialized`, `finishing`, `completed`, `skipped`
{.table-cell}
||
||

_leave_under_door_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Оставить заказ у двери
{.table-cell}
||
||

_meet_outside_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Курьера встретят на улице у подъезда
{.table-cell}
||
||

_no_door_call_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Не звонить в дверь
{.table-cell}
||
||

_payment_on_delivery_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [ResponsePaymentOnDelivery](#entity-ResponsePaymentOnDelivery)

Параметры оплаты при получении

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "payment_ref_id": "123e4567-e89b-12d3-a456-426614174000",
  "client_order_id": "100",
  "is_paid": false,
  "customer": {
    "full_name": "Морти",
    "inn": "3664069397",
    "email": "example@yandex.ru",
    "phone": "79000000000"
  },
  "payment_method": "card",
  "invoice_link": "https://ofd.yandex.ru/vaucher/0005312316002718/9410/2604520024"
}
```

{% endcut %}
{.table-cell}
||
||

_pickup_code_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [PickupCode](#entity-PickupCode)

Код выдачи заказа курьеру.
Курьеру потребуется ввести этот код, чтобы подтвердить, что он забрал заказ.
Для этого необходимо, чтобы ваши сотрудники на точке выдачи имели возможность назвать этот код курьеру.
Актуально для точки с типом 'source'.
Формат кода: 6 цифр
&#124;
Код выдачи товара (ПВЗ)


_Example:_{.json-schema-reset .json-schema-example} `893422`
{.table-cell}
||
||

_return_comment_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Комментарий к причинам возврата груза

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_return_reasons_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string[]

Причины возврата груза

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  "example"
]
```

{% endcut %}
{.table-cell}
||
||

_skip_confirmation_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CargoPointSkipConfirmation](#entity-CargoPointSkipConfirmation)

Пропускать подтверждение по смс в данной точке

Значение по умолчанию: false (подтверждение требуется).


_Default:_{.json-schema-reset .json-schema-value} `false`

_Example:_{.json-schema-reset .json-schema-example} `false`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "id": 1,
  "contact": {
    "name": "Морти",
    "phone": "+79099999998",
    "phone_additional_code": "602 17 500",
    "email": "example@yandex.ru"
  },
  "address": {
    "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
    "shortname": "Большая Монетная улица, 1к1А",
    "coordinates": [
      0.5,
      0.5
    ],
    "country": "Россия",
    "city": "Санкт-Петербург",
    "building_name": "БЦ На Большой Монетной",
    "street": "Большая Монетная улица",
    "building": "23к1А",
    "porch": "A",
    "sfloor": "1",
    "sflat": "1",
    "door_code": "169",
    "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
    "doorbell_name": "Магидович",
    "comment": "Домофон не работает",
    "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
    "description": "Санкт-Петербург, Россия"
  },
  "type": "source",
  "visit_order": 1,
  "visit_status": "pending",
  "skip_confirmation": false,
  "leave_under_door": true,
  "meet_outside": true,
  "no_door_call": true,
  "payment_on_delivery": {
    "payment_ref_id": "123e4567-e89b-12d3-a456-426614174000",
    "client_order_id": "100",
    "is_paid": false,
    "customer": {
      "full_name": "Морти",
      "inn": "3664069397",
      "email": "example@yandex.ru",
      "phone": "79000000000"
    },
    "payment_method": "card",
    "invoice_link": "https://ofd.yandex.ru/vaucher/0005312316002718/9410/2604520024"
  },
  "external_order_id": "100",
  "external_order_cost": {
    "value": "100.0",
    "currency": "RUB",
    "currency_sign": "₽"
  },
  "expected_visit_interval": {
    "from": "2020-01-01T00:00:00+00:00",
    "to": "2020-01-02T00:00:00+00:00"
  },
  "pickup_code": "893422",
  "return_reasons": [
    "example"
  ],
  "return_comment": "example",
  "visited_at": {
    "expected": "2025-01-01T00:00:00Z",
    "expected_waiting_time_sec": 0,
    "actual": "2025-01-01T00:00:00Z"
  },
  "handover_status": "pending"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### V2ResponseCargoRoutePoints {#entity-V2ResponseCargoRoutePoints}

Информация по точкам маршрута

**Type**: [V2ResponseCargoPoint](#entity-V2ResponseCargoPoint)[]

_Min items:_{.json-schema-reset .json-schema-assertion} `2`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "id": 1,
    "contact": {
      "name": "Морти",
      "phone": "+79099999998",
      "phone_additional_code": "602 17 500",
      "email": "example@yandex.ru"
    },
    "address": {
      "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
      "shortname": "Большая Монетная улица, 1к1А",
      "coordinates": [
        0.5,
        0.5
      ],
      "country": "Россия",
      "city": "Санкт-Петербург",
      "building_name": "БЦ На Большой Монетной",
      "street": "Большая Монетная улица",
      "building": "23к1А",
      "porch": "A",
      "sfloor": "1",
      "sflat": "1",
      "door_code": "169",
      "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
      "doorbell_name": "Магидович",
      "comment": "Домофон не работает",
      "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
      "description": "Санкт-Петербург, Россия"
    },
    "type": "source",
    "visit_order": 1,
    "visit_status": "pending",
    "skip_confirmation": false,
    "leave_under_door": true,
    "meet_outside": true,
    "no_door_call": true,
    "payment_on_delivery": {
      "payment_ref_id": "123e4567-e89b-12d3-a456-426614174000",
      "client_order_id": "100",
      "is_paid": false,
      "customer": {
        "full_name": "Морти",
        "inn": "3664069397",
        "email": "example@yandex.ru",
        "phone": "79000000000"
      },
      "payment_method": "card",
      "invoice_link": "https://ofd.yandex.ru/vaucher/0005312316002718/9410/2604520024"
    },
    "external_order_id": "100",
    "external_order_cost": {
      "value": "100.0",
      "currency": "RUB",
      "currency_sign": "₽"
    },
    "expected_visit_interval": {
      "from": "2020-01-01T00:00:00+00:00",
      "to": "2020-01-02T00:00:00+00:00"
    },
    "pickup_code": "893422",
    "return_reasons": [
      "example"
    ],
    "return_comment": "example",
    "visited_at": {
      "expected": "2025-01-01T00:00:00Z",
      "expected_waiting_time_sec": 0,
      "actual": "2025-01-01T00:00:00Z"
    },
    "handover_status": "pending"
  },
  {
    "id": 1,
    "contact": {
      "name": "Морти",
      "phone": "+79099999998",
      "phone_additional_code": "602 17 500",
      "email": "example@yandex.ru"
    },
    "address": {
      "fullname": "Санкт-Петербург, Большая Монетная улица, 1к1А",
      "shortname": "Большая Монетная улица, 1к1А",
      "coordinates": [
        0.5,
        0.5
      ],
      "country": "Россия",
      "city": "Санкт-Петербург",
      "building_name": "БЦ На Большой Монетной",
      "street": "Большая Монетная улица",
      "building": "23к1А",
      "porch": "A",
      "sfloor": "1",
      "sflat": "1",
      "door_code": "169",
      "door_code_extra": "код на вход во двор #1234, код от апартаментов #4321",
      "doorbell_name": "Магидович",
      "comment": "Домофон не работает",
      "uri": "ymapsbm1://geo?ll=38.805%2C55.084",
      "description": "Санкт-Петербург, Россия"
    },
    "type": "source",
    "visit_order": 1,
    "visit_status": "pending",
    "skip_confirmation": false,
    "leave_under_door": true,
    "meet_outside": true,
    "no_door_call": true,
    "payment_on_delivery": {
      "payment_ref_id": "123e4567-e89b-12d3-a456-426614174000",
      "client_order_id": "100",
      "is_paid": false,
      "customer": {
        "full_name": "Морти",
        "inn": "3664069397",
        "email": "example@yandex.ru",
        "phone": "79000000000"
      },
      "payment_method": "card",
      "invoice_link": "https://ofd.yandex.ru/vaucher/0005312316002718/9410/2604520024"
    },
    "external_order_id": "100",
    "external_order_cost": {
      "value": "100.0",
      "currency": "RUB",
      "currency_sign": "₽"
    },
    "expected_visit_interval": {
      "from": "2020-01-01T00:00:00+00:00",
      "to": "2020-01-02T00:00:00+00:00"
    },
    "pickup_code": "893422",
    "return_reasons": [
      "example"
    ],
    "return_comment": "example",
    "visited_at": {
      "expected": "2025-01-01T00:00:00Z",
      "expected_waiting_time_sec": 0,
      "actual": "2025-01-01T00:00:00Z"
    },
    "handover_status": "pending"
  }
]
```

{% endcut %}

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

### ClaimStatus {#entity-ClaimStatus}

Статус заявки. Подробнее см. в разделе [Статусная модель](https://yandex.com/support/delivery-profile/ru/api/express/claim-process.md)

**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `new`, `estimating`, `estimating_failed`, `ready_for_approval`, `accepted`, `performer_lookup`, `performer_draft`, `performer_found`, `performer_not_found`, `pickup_arrived`, `ready_for_pickup_confirmation`, `pickuped`, `delivery_arrived`, `ready_for_delivery_confirmation`, `delivered`, `delivered_finish`, `returning`, `return_arrived`, `ready_for_return_confirmation`, `returned`, `returned_finish`, `failed`, `cancelled`, `cancelled_with_payment`, `cancelled_by_taxi`, `cancelled_with_items_on_hands`

</div>

<div class="openapi-entity">

### HumanErrorMessage {#entity-HumanErrorMessage}

Код и описание ошибки

#|
|| **Name** | **Description** ||
||

_code_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Код ошибки

_Example:_{.json-schema-reset .json-schema-example} `some_error`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание ошибки

_Example:_{.json-schema-reset .json-schema-example} `Some error`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "code": "some_error",
  "message": "Some error"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### Eta {#entity-Eta}

Расчетное время выполнения заказа в минутах (int64)

**Type**: integer

</div>

<div class="openapi-entity">

### TaxiOfferId {#entity-TaxiOfferId}

Идентификатор предложения

**Type**: string

_Example:_{.json-schema-reset .json-schema-example} `28ae5f1d72364468be3f5e26cd6a66bf`

</div>

<div class="openapi-entity">

### TaxiOffer {#entity-TaxiOffer}

Предложение от Яндекс Доставки (актуально в течение некоторого времени).

#|
|| **Name** | **Description** ||
||

_offer_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [TaxiOfferId](#entity-TaxiOfferId)

Идентификатор предложения

_Example:_{.json-schema-reset .json-schema-example} `28ae5f1d72364468be3f5e26cd6a66bf`
{.table-cell}
||
||

_price_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [Money](#entity-Money)

Цена по предложению без НДС

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
||

_valid_until_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string&lt;date-time&gt;

Время до которого действительно предложение на принятие заявки. Если значения нет, то ограничений по длительности предложения нет

_Example:_{.json-schema-reset .json-schema-example} `2020-01-01T00:00:00+00:00`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "offer_id": "28ae5f1d72364468be3f5e26cd6a66bf",
  "price": "12.50",
  "valid_until": "2020-01-01T00:00:00+00:00",
  "price_with_vat": null
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### CurrencyRules {#entity-CurrencyRules}

Правила отображения валюты

#|
|| **Name** | **Description** ||
||

_code_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [Currency](#entity-Currency)

Трехзначный код валюты, в которой ведется расчет

_Min length:_{.json-schema-reset .json-schema-assertion} `3`

_Max length:_{.json-schema-reset .json-schema-assertion} `3`

_Example:_{.json-schema-reset .json-schema-example} `RUB`
{.table-cell}
||
||

_template_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Шаблон для отображения валюты

_Example:_{.json-schema-reset .json-schema-example} `$VALUE$ $SIGN$$CURRENCY$`
{.table-cell}
||
||

_text_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Сокращенное наименование валюты

_Example:_{.json-schema-reset .json-schema-example} `руб.`
{.table-cell}
||
||

_sign_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Символ валюты

_Example:_{.json-schema-reset .json-schema-example} `₽`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "code": "RUB",
  "text": "руб.",
  "template": "$VALUE$ $SIGN$$CURRENCY$",
  "sign": "₽"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ClaimPricing {#entity-ClaimPricing}

Информация о стоимости заказа

#|
|| **Name** | **Description** ||
||

_currency_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Трехзначный код валюты, в которой ведется расчет

_Example:_{.json-schema-reset .json-schema-example} `RUB`
{.table-cell}
||
||

_currency_rules_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [CurrencyRules](#entity-CurrencyRules)

Правила отображения валюты

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "code": "RUB",
  "text": "руб.",
  "template": "$VALUE$ $SIGN$$CURRENCY$",
  "sign": "₽"
}
```

{% endcut %}
{.table-cell}
||
||

_final_price_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [Money](#entity-Money)

Окончательная цена доставки с учетом НДС.
Заполняется после окончания доставки/возврата.


Стоимость доставки в формате десятичной дроби Decimal(18, 4)

_Pattern:_{.json-schema-reset .json-schema-assertion} `^-?[0-9]{1,14}(\.[0-9]{0,4})?$`

_Example:_{.json-schema-reset .json-schema-example} `12.50`
{.table-cell}
||
||

_final_pricing_calc_id_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Идентификатор расчета стоимости

_Example:_{.json-schema-reset .json-schema-example} `example`
{.table-cell}
||
||

_offer_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [TaxiOffer](#entity-TaxiOffer)

Предложение от Яндекс Доставки (актуально в течение некоторого времени).

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "offer_id": "28ae5f1d72364468be3f5e26cd6a66bf",
  "price": "12.50",
  "valid_until": "2020-01-01T00:00:00+00:00",
  "price_with_vat": null
}
```

{% endcut %}
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "offer": {
    "offer_id": "28ae5f1d72364468be3f5e26cd6a66bf",
    "price": "12.50",
    "valid_until": "2020-01-01T00:00:00+00:00",
    "price_with_vat": null
  },
  "currency": "RUB",
  "currency_rules": {
    "code": "RUB",
    "text": "руб.",
    "template": "$VALUE$ $SIGN$$CURRENCY$",
    "sign": "₽"
  },
  "final_pricing_calc_id": "example",
  "final_price": null
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### MatchedCar {#entity-MatchedCar}

#|
|| **Name** | **Description** ||
||

_taxi_class_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Тариф доставки. Возможные значения: courier, express, cargo


_Example:_{.json-schema-reset .json-schema-example} `express`
{.table-cell}
||
||

_cargo_loaders_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: integer

Требуемое число грузчиков (int64)

_Min value:_{.json-schema-reset .json-schema-assertion} `0`
{.table-cell}
||
||

_cargo_type_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Тип кузова

_Example:_{.json-schema-reset .json-schema-example} `lcv_m`
{.table-cell}
||
||

_cargo_type_int_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: integer

Тип кузова (int64)
{.table-cell}
||
||

_client_taxi_class_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Клиентский тариф


_Example:_{.json-schema-reset .json-schema-example} `cargo`
{.table-cell}
||
||

_door_to_door_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Опция "от двери до двери" для тарифа "Экспресс"
{.table-cell}
||
||

_pro_courier_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: boolean

Включить опцию "Профи" для тарифов "Экспресс" и "Курьер".
Поиск исполнителя будет происходить только среди опытных курьеров.

{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "taxi_class": "express",
  "client_taxi_class": "cargo",
  "cargo_type": "lcv_m",
  "cargo_type_int": "2 is equal to \"lcv_m\"",
  "cargo_loaders": 0,
  "door_to_door": false,
  "pro_courier": false
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### ClaimWarningSourceApi {#entity-ClaimWarningSourceApi}

Источник предупреждения:
 - client_requirements - предупреждение связано с требованиями клиента;
 - route_points - предупреждение связано
с переданными адресами.


**Type**: string

_Example:_{.json-schema-reset .json-schema-example} `client_requirements`

</div>

<div class="openapi-entity">

### ClaimWarningCodeApi {#entity-ClaimWarningCodeApi}

Тип предупреждения:
- not_fit_in_car - груз может не поместиться в транспортное средство;
- requirement_unavailable - указанное требование недоступно и было проигнорировано;
- address_not_found - указанный адрес не найден в Яндекс Картах;
- address_too_far - координаты из Яндекс Карт по указанному адресу находятся далеко от переданных координат.


**Type**: string

_Example:_{.json-schema-reset .json-schema-example} `not_fit_in_car`

</div>

<div class="openapi-entity">

### ClaimWarning {#entity-ClaimWarning}

#|
|| **Name** | **Description** ||
||

_code_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [ClaimWarningCodeApi](#entity-ClaimWarningCodeApi)

Тип предупреждения:
- not_fit_in_car - груз может не поместиться в транспортное средство;
- requirement_unavailable - указанное требование недоступно и было проигнорировано;
- address_not_found - указанный адрес не найден в Яндекс Картах;
- address_too_far - координаты из Яндекс Карт по указанному адресу находятся далеко от переданных координат.


_Example:_{.json-schema-reset .json-schema-example} `not_fit_in_car`
{.table-cell}
||
||

_source_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [ClaimWarningSourceApi](#entity-ClaimWarningSourceApi)

Источник предупреждения:
 - client_requirements - предупреждение связано с требованиями клиента;
 - route_points - предупреждение связано
с переданными адресами.


_Example:_{.json-schema-reset .json-schema-example} `client_requirements`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Описание предупреждения

_Example:_{.json-schema-reset .json-schema-example} `предупреждение`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "source": "client_requirements",
  "code": "not_fit_in_car",
  "message": "предупреждение"
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### PerformerInfo {#entity-PerformerInfo}

Информация о курьере

#|
|| **Name** | **Description** ||
||

_courier_name_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Имя курьера, доставляющего заказ

_Example:_{.json-schema-reset .json-schema-example} `Личность`
{.table-cell}
||
||

_legal_name_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Данные о юридическом лице, которое осуществляет доставку

_Example:_{.json-schema-reset .json-schema-example} `ИП Птичья личность`
{.table-cell}
||
||

_car_color_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Цвет машины

_Example:_{.json-schema-reset .json-schema-example} `красный`
{.table-cell}
||
||

_car_color_hex_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

RGB-код цвета машины

_Example:_{.json-schema-reset .json-schema-example} `FF00000`
{.table-cell}
||
||

_car_model_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Модель машины

_Example:_{.json-schema-reset .json-schema-example} `Hyundai Solaris`
{.table-cell}
||
||

_car_number_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Номер машины

_Example:_{.json-schema-reset .json-schema-example} `А100РА100`
{.table-cell}
||
||

_transport_type_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: string

Тип транспорта курьера

_Example:_{.json-schema-reset .json-schema-example} `car`
{.table-cell}
||
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "courier_name": "Личность",
  "legal_name": "ИП Птичья личность",
  "car_model": "Hyundai Solaris",
  "car_number": "А100РА100",
  "car_color": "красный",
  "car_color_hex": "FF00000",
  "transport_type": "car"
}
```

{% endcut %}

</div>

</div>

<div class="openapi__response__code__400">

## 400 Bad Request

Неправильные параметры заявки

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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `validation_error`, `sdd_items_without_parameters_forbidden`, `items_without_parameters_forbidden`, `delay_too_long`, `address_not_found`, `bad_request`, `unknown_zone`, `too_much_claim_edits`, `invalid_destination_point`, `invalid_delivery_interval`, `due_in_past`, `invalid_phone_size_incorrect`, `country_phone_code_not_supported`, `invalid_phone_must_start_plus_symbol`, `invalid_phone_incorrect_symbol`, `item_source_point_not_found`, `item_destination_point_not_found`, `unsupported_points_count`, `address_outside_delivery_zone`, `invalid_buyout_point_type`, `payment_on_delivery_missed`, `payment_on_delivery_invalid_request`, `max_order_cost_exceeded`, `invalid_post_payment_payment_method`, `invalid_buyout_payment_method`, `invalid_point_phone`, `invalid_source_point`, `no_input_point`, `wrong_pickup_code_usage`, `empty_coordinates`, `assign_robot_not_editable`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Сообщение об ошибке, понятное человеку

_Example:_{.json-schema-reset .json-schema-example} `Неправильное тело запроса`
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

<div class="openapi__response__code__403">

## 403 Forbidden

Ошибка аутентификации или оплата при получении недоступна


<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "code": "payment_on_delivery_disabled",
  "message": "Оплата при получении недоступна"
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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `buyout_disabled`, `payment_on_delivery_disabled`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Описание ошибки

_Example:_{.json-schema-reset .json-schema-example} `Оплата при получении недоступна`
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

Конфликт: попытка изменить статус для неактуальной
версии или неподходящий статус заявки


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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `old_version`, `inappropriate_status`, `state_mismatch`
{.table-cell}
||
||

_message_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: string

Сообщение об ошибке, понятное человеку

_Example:_{.json-schema-reset .json-schema-example} `Недопустимое действие над заявкой`
{.table-cell}
||
|#{.json-schema-properties}

</div>

</div>

<div class="openapi__response__code__429">

## 429 Too Many Requests

Слишком много запросов

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