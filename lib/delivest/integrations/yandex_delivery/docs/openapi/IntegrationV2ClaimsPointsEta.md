---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/openapi/IntegrationV2ClaimsPointsEta.md
  - https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsPointsEta.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsPointsEta.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

<div class="openapi">

# Прогнозируемое время прибытия курьера

<!-- markdownlint-disable-file -->

Возвращает список точек и оценку времени прибытия на точку курьером.


## Request

<div class="openapi__requests">

<div class="openapi__request__wrapper" style="--method: var(--dc-openapi-methods-post);margin-bottom: 12px">

<div class="openapi__request">

POST {.openapi__method}
```text translate=no
b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/points-eta
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

Оценка времени прибытия курьера на точки

<div class="openapi-entity">

### Body

{% cut "application/json" %}

```json translate=no
{
  "id": "741cedf82cd464fa6fa16d87155c636",
  "route_points": [
    {
      "id": 1,
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
      "visited_at": {
        "expected": "2025-01-01T00:00:00Z",
        "expected_waiting_time_sec": 0,
        "actual": "2025-01-01T00:00:00Z"
      }
    }
  ],
  "performer_position": [
    52.569089,
    39.60258
  ]
}
```

{% endcut %}

#|
|| **Name** | **Description** ||
||

_id_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [ClaimId](#entity-ClaimId)

Идентификатор заявки

Идентификатор(ID) заявки, полученный на этапе создания заявки

_Min length:_{.json-schema-reset .json-schema-assertion} `32`

_Max length:_{.json-schema-reset .json-schema-assertion} `64`

_Example:_{.json-schema-reset .json-schema-example} `741cedf82cd464fa6fa16d87155c636`
{.table-cell}
||
||

_route_points_{.json-schema-reset .json-schema-property .json-schema-required}
{.table-cell}|
**Type**: [PointWithEta](#entity-PointWithEta)[]

Точки маршрута расчетным временем прибытия курьера.

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  {
    "id": 1,
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
    "visited_at": {
      "expected": "2025-01-01T00:00:00Z",
      "expected_waiting_time_sec": 0,
      "actual": "2025-01-01T00:00:00Z"
    }
  }
]
```

{% endcut %}
{.table-cell}
||
||

_performer_position_{.json-schema-reset .json-schema-property}
{.table-cell}|
**Type**: [PointsEtaPerformerPosition](#entity-PointsEtaPerformerPosition)

Позиция курьера, для которой был рассчитан ETA

_Min items:_{.json-schema-reset .json-schema-assertion} `2`

_Max items:_{.json-schema-reset .json-schema-assertion} `2`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  52.569089,
  39.60258
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

### AddressFullname {#entity-AddressFullname}

Полный адрес с указанием города, улицы и номера дома.
Номер квартиры, подъезда и этаж указывать не нужно.


**Type**: string

_Example:_{.json-schema-reset .json-schema-example} `Санкт-Петербург, Большая Монетная улица, 1к1А`

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

### PointType {#entity-PointType}

Тип точки:
  - source - точка отправления, где курьер забирает товар
  - destination – точки назначения, где курьер передает товар
  - return - точка возврата товара (добавляется автоматически и по умолчанию совпадает с точкой отправления, но также можно определить другую точку)


**Type**: string

_Enum:_{.json-schema-reset .json-schema-value} `source`, `destination`, `return`

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

### PointWithEta {#entity-PointWithEta}

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

Оценка времени посещения

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
|#{.json-schema-properties}

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
{
  "id": 1,
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
  "visited_at": {
    "expected": "2025-01-01T00:00:00Z",
    "expected_waiting_time_sec": 0,
    "actual": "2025-01-01T00:00:00Z"
  }
}
```

{% endcut %}

</div>

<div class="openapi-entity">

### PointsEtaPerformerPosition {#entity-PointsEtaPerformerPosition}

**Type**: number[]

_Min items:_{.json-schema-reset .json-schema-assertion} `2`

_Max items:_{.json-schema-reset .json-schema-assertion} `2`

{% cut "**Example**" %}{.json-schema-example}

```json translate=no
[
  52.569089,
  39.60258
]
```

{% endcut %}

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

Возможные причины ошибки:
 - Заявка в неактивном статусе.
 - Исполнителя еще нет.
 - Не удалось определить местоположение курьера.


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

_Enum:_{.json-schema-reset .json-schema-value} `unknown_error`, `inappropriate_status`, `no_performer_info`, `unknown_performer_position`
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