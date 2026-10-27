# Яндекс Еда

Входящий канал продаж: заказы из Яндекс Еды (и Delivery Club по тому же протоколу) приходят к нам, а мы — основная система ресторана. Модуль в разработке, что осталось — в разделе «TODO» в конце файла.

- Источник: OpenAPI «API для интеграции сервиса Яндекс Еда» v1.0-oas3, https://yandex.ru/dev/eda-vendor/doc/ru/ref/
- Ключ канала: `:yandex_eda`
- Площадки: `platform` в заказе — `YE` (Яндекс Еда) или `DC` (Delivery Club)

## Модель взаимодействия

| Направление | Кто сервер | Адрес | Что |
|---|---|---|---|
| **Pull** — основное | **мы** | наш домен | Яндекс забирает меню, стоп-лист, рестораны, график, создаёт и отменяет заказы, опрашивает статусы |
| **Push** — дополнительное | Яндекс | `https://dc-partner.eda.yandex.net` | Мы просим перечитать меню, ставим рестораны на паузу, читаем историю заказов |

Статусы заказов Яндекс **сам опрашивает** у нас (`GET /order/{id}/status`), слать их не нужно.

## Принятые решения

| Вопрос | Решение |
|---|---|
| Ресторан | Каждый наш филиал — отдельный ресторан, `restaurantId` = id филиала |
| Доступ | Один `client_id` / `client_secret` на франшизу, генерирует наша админка |
| id блюд | Наши `product.id`: меню отдаём мы, Яндекс присылает их обратно в заказе |
| Состав меню | Таблица `channel_products` (канал, товар, `enabled`, `price`) — настраивается на странице интеграции, не в товаре |
| Цена | своя цена товара для канала → иначе базовая × (1 + наценка филиала) с округлением → иначе базовая |
| Копейки | В меню отдаём целые рубли. Цены позиций из заказа округляем вниз до рубля, итог берём из `itemsCost` |
| Комбо, промо, модификаторы | Не поддерживаем: `combos`, `/promos`, `modifierGroups` не отдаём |
| Единица измерения | Поле у товара: `г` или `мл`, по умолчанию `г` |
| Схемы доставки | Все три: `yandex` (курьер Яндекса), `marketplace` (наш курьер), `pickup` (самовывоз) |
| Подтверждение | Наш статус `accepted` ↔ `ACCEPTED_BY_RESTAURANT`. Режим канала: автоматически или вручную. Вручную: срок `accept_minutes` (по умолчанию 10) считается от прихода заказа, а если филиал закрыт — от ближайшего открытия по графику (`AcceptDeadline`). В момент срока `AcceptDeadlineWorker` будит админку, и на любой её странице всплывает тревога со звуком: «Подтвердить», «Отменить» (причина «Не подтверждён вовремя») или «Пусть висит». Сами мы заказ после срока не трогаем |
| Стоп-лист | Наш ∪ Frontpad. На каждом заказе — свежий `get_stops` Frontpad с таймаутом 2 с, иначе кэш. Недоступные позиции → `406`. В `availability` — только товары из меню канала |
| Оплата | `CARD` → «оплачено онлайн», `CASH` → наличные, сдача из `change` идёт в примечание курьеру |
| Клиент | Аккаунт не создаём, адрес в «Мои адреса» не сохраняем. Имя и телефон только в заказе |
| Акции приложения | К заказам Яндекса не применяются: цены и скидки считает Яндекс |
| Приоритет статусов | Кухня (принят, готовится, готов) — от конечной CRM. Курьер и отмена — от Яндекса |
| Статусы назад | Яндексу отдаём только движение вперёд; `CANCELLED` — из любого |
| Отмена Яндексом при Frontpad | У Frontpad нет API отмены: заказ отменяем у нас, в админке тревога «отмените вручную во Frontpad №…» |
| Адрес `marketplace` | `full` → `formatted`, координаты как есть, улицу и дом достаём DaData `geolocate` по координатам |
| Журнал | Все запросы Яндекса и наши ответы пишем в лог интеграции |
| Сверка | По дню, только расхождения, нужен доступ к push-API и право `orders.read` |
| Пауза | Блок «Пауза в Яндекс Еде» на странице интеграции, нужен доступ к push-API. `/block` шлём сразу для `ddc` и `marketplace`, срок 15 мин – 4 ч или до снятия, причина `too_busy` / `technical_problem`. Активные паузы читаем через `/v2/status`, снимаем `/unblock` |

## Общие правила API

- Авторизация каждого pull-запроса: `Authorization: Bearer <access_token>` (выдаёт наш `/security/oauth/token`). Неверный или протухший токен → `401` с `{"reason": "..."}`, Яндекс перезапросит токен и повторит.
- Даты: RFC 3339 **с дробной частью секунд**, `2026-10-27T12:00:27.870000+03:00`.
- Ошибки pull-методов: `400`, `404`, `500` — тело **массив** `[{"code": <int>, "description": "..."}]`. Коды согласуются с Яндексом.
- Версии моделей передаются в типе содержимого: меню `application/vnd.eats.menu.composition.v2+json`, стоп-лист `application/vnd.eats.menu.availability.v2+json`, заказ `application/vnd.eats.order.v2+json`.
- Телефоны: `+<код страны><номер>`, может быть `доб. <номер>`.

---

# Pull: методы, которые реализуем мы

| Метод | Путь | Обязателен | Назначение |
|---|---|---|---|
| POST | `/security/oauth/token` | да | Выдать токен Яндексу |
| GET | `/restaurants` | да | Список ресторанов (филиалов) |
| GET | `/restaurants/availability` | да | Включены ли рестораны |
| GET | `/menu/{restaurantId}/composition` | да | Меню |
| GET | `/menu/{restaurantId}/availability` | да | Стоп-лист |
| GET | `/menu/{restaurantId}/promos` | нет | Блюда в подарок — не делаем |
| POST | `/order` | да | Создать заказ |
| GET | `/order/{orderId}` | да | Заказ целиком |
| PUT | `/order/{orderId}` | по согласованию | Изменение состава заказа Яндексом |
| DELETE | `/order/{orderId}` | да | Отмена заказа Яндексом |
| GET | `/order/{orderId}/status` | да | Статус заказа |
| PUT | `/order/{orderId}/status` | да | Статус от Яндекса: курьер забрал, доставлен, отменён |
| PUT | `/order/{orderId}/courier` | да | Данные курьера |
| GET | `/places/{restaurantId}/schedule` | да | График работы |
| GET | `/places/{restaurantId}/zones` | по подписке | Зоны доставки |
| GET | `/places/{restaurantId}/zone/meta` | по подписке | Обновление зон |
| POST | `/v1/feedback` | по подписке | Отзыв клиента — сделан |

## POST `/security/oauth/token`

OAuth 2.0 client credentials. Тело `application/x-www-form-urlencoded` одной строкой, без авторизации.

| Поле | Обязательное | Значение |
|---|---|---|
| `client_id` | да | Наш выданный id |
| `client_secret` | да | Наш выданный секрет |
| `grant_type` | да | `client_credentials` |
| `scope` | да | `read write` |

```
client_id=123123123&client_secret=ABCDEF&grant_type=client_credentials&scope=read%20write
```

Ответ `200`: `{"access_token": "..."}` — единственное обязательное поле, остальные поля OAuth Яндекс игнорирует. Ошибки `400`, `500` — массив ошибок.

## GET `/restaurants`

```json
{ "places": [ { "id": "<id филиала>", "title": "Пиццерия на Ленина", "address": "Тюмень, ул Ленина, 1" } ] }
```

Все три поля обязательны.

## GET `/restaurants/availability`

Включение и выключение ресторанов в Яндекс Еде.

```json
{ "places": [ { "id": "<id филиала>", "enabled": true } ] }
```

Если ресторана нет в ответе, его доступность не меняется. Включить можно только ресторан, который Яндекс не выключил сам по другим причинам.

## GET `/menu/{restaurantId}/composition`

Тип ответа `application/vnd.eats.menu.composition.v2+json`. Позиции с ошибками (слишком длинные строки, цена 0) Яндекс может пропустить.

### MenuCompositionV2

| Поле | Обязательное | Описание |
|---|---|---|
| `categories` | да | `[Category]` |
| `items` | да | `[MenuCompositionItem]` |
| `lastChange` | да | Время последнего изменения меню, RFC 3339 с дробью. Не изменилось — Яндекс может не перезагружать меню |
| `schedules` | | Типы расписаний категорий: `{ "<имя>": [ {from, till, weekdays} ] }` |
| `combos` | | Комбо — не отдаём |

### Category

| Поле | Обязательное | Описание |
|---|---|---|
| `id` | да | id категории, до 64 символов |
| `name` | да | Название |
| `parentId` | | Родительская категория. Яндекс сворачивает дерево до первого уровня |
| `sortOrder` | | По возрастанию, по умолчанию 100 |
| `schedules` | | Имена расписаний из `schedules`. Пусто — категория доступна всегда |
| `images` | | `[{url, updatedAt}]` |

Расписание: `{ "from": "08:00", "till": "09:45", "weekdays": ["monday", ...] }`, время 00:00–24:00.

### MenuCompositionItem

| Поле | Обязательное | Наше поле / решение |
|---|---|---|
| `id` | да | `product.id`, до 64 символов |
| `categoryId` | да | `product.category_id` |
| `name` | да | `product.name` |
| `price` | да | Цена канала. 0 — блюдо пропускается |
| `measure` | да | `product.weight` |
| `measureUnit` | да | `г` / `мл` (`g` / `ml` тоже можно) |
| `description` | | `product.description` |
| `vat` | | НДС в процентах, по умолчанию 0. У нас — настройка филиала «НДС в меню»: 0, 5, 7, 10, 22. 0 не отдаём |
| `images` | | `[{hash, url}]`: SHA1 содержимого файла и публичная ссылка. Новый хэш — Яндекс перекачивает фото. Ответ по ссылке — сами байты, `Content-Type` `image/png`, `image/jpeg`, `image/jpg`, `image/webp` или `image/avif`, до 24 МиБ |
| `nutrients` | | КБЖУ на 100 г: `calories`, `proteins`, `fats`, `carbohydrates` — все четыре обязательны, если блок есть. Поля товара, отдаём только если заполнены все четыре |
| `sortOrder` | | По возрастанию, по умолчанию 100 |
| `shippingType` | | `delivery` или `pickup`; не указан — доступно для обоих |
| `isCatchweight`, `weightQuantum` | | Весовой товар и минимальный шаг — не используем |
| `excise` | | `sugary_drink` / `other`, или метка `[AT]` в названии. Поле товара «Акциз» |
| `modifierGroups` | | Модификаторы — не отдаём |
| `additional_descriptions` | | `consisting_ingredients` (до 100 строк по 100 символов) и `badges`: `food_specifics` (`halal`, `meat_free`), `food_spiciness` (`spicy`), `cooking_method` (`fried`, `baked`, `grilled`, `not_cooked`), `food_portion` (`portion_for_several_people`, `big_portion`, `combo`) |
| `adult_info` | | `age_group` 18 / 21, `alcohol_percentage` — не отдаём: алкоголь не продаём |
| `needMarking`, `legalInfo` | | Маркировка по закону о платформенной экономике: при `needMarking: true` обязателен `legalInfo.gtin`. Остальное: `classificationCodes` (ТН ВЭД / ОКПД 2), `conformityInfo`, `governmentRegistrationInfo` — не отдаём: блюда собственного производства маркировке не подлежат |
| `onlyForCombo` | | Только для комбо |

### Модификаторы (для справки, не используем)

`ModifierGroups`: `id`, `name`, `minSelectedModifiers`, `maxSelectedModifiers` (0–255), `sortOrder`, `modifiers`.
`Modifiers`: `id`, `name`, `price`, `minAmount`, `maxAmount` (0–255), `originalPrice`, `vat`, `excise`. Некорректный модификатор отбрасывает и группу, и блюда, где она используется.

## GET `/menu/{restaurantId}/availability`

Тип ответа `application/vnd.eats.menu.availability.v2+json`. Перечисляем только **недоступное** из того, что отдаём в меню канала.

```json
{
  "items": [ { "itemId": "<product.id>", "stock": 0 } ],
  "modifiers": []
}
```

| Поле | Обязательное | Описание |
|---|---|---|
| `items` | да | `[{itemId, stock}]`. `stock` не передан — считается 0. При 0 блюдо пропадает из выдачи |
| `modifiers` | да | `[{modifierId, stock}]`, у нас всегда пусто |
| `combos` | | `[{comboId, stock}]` |

Позиция, которой нет в ответе, доступна. Остаток −10 и подобное Яндекс игнорирует.

## POST `/order`

Тип запроса `application/vnd.eats.order.v2+json`. Модель выбирается по `discriminator`.

### Ответы

| Код | Тело | Когда |
|---|---|---|
| `200` | `{"result": "OK", "orderId": "<наш id заказа>"}` | Принят. `orderId` обязателен, рекомендуется UUID |
| `400` | массив ошибок | Ошибка в данных |
| `401` | `{"reason": "..."}` | Токен — Яндекс повторит |
| `406` | `UnavailableGoodsResponse` | Часть блюд в стоп-листе |
| `500` | массив ошибок | Наша ошибка |

`406`:

```json
{
  "type": "unavailable_goods",
  "message": "На данный момент товар недоступен для заказа: Омлет с крем-чизом",
  "goods": { "<product.id>": "Омлет с крем-чизом" }
}
```

Яндекс ставит эти блюда в стоп, при следующем опросе `availability` снимает, если их там нет, и предлагает клиенту поправить заказ. Исправленный заказ придёт заново.

### Общие поля всех трёх моделей

| Поле | Обязательное | Описание |
|---|---|---|
| `discriminator` | да | `yandex`, `marketplace` или `pickup` |
| `eatsId` | да | Сквозной номер заказа в Яндексе, `260423-SE1234567L`. **Ключ идемпотентности** |
| `restaurantId` | да | id нашего филиала |
| `items` | да | `[OrdersItem]` |
| `deliveryInfo` | да | Своя модель на схему |
| `paymentInfo` | да | Своя модель на схему |
| `comment` | да | Комментарий клиента |
| `promos` | да | Акции на весь заказ, `[OrdersPromoItem]` |
| `platform` | | `YE` / `DC` |
| `persons` | | Количество персон (приборы) |

### OrdersItem

| Поле | Обязательное | Описание |
|---|---|---|
| `id` | да | Наш `product.id` |
| `quantity` | да | Количество, может быть дробным (весовые) |
| `price` | да | Цена **одной** позиции вместе с модификаторами |
| `modifications` | да | `[{id, group_id, name, quantity, price}]`, может быть пустым |
| `promos` | да | Акции на позицию; сейчас только «блюдо в подарок» |
| `name` | | Название |
| `comboInfo` | | `{id, componentId}` для позиций из комбо |

Одно блюдо с разными модификациями приходит разными позициями.

### OrdersPromoItem

| Поле | Обязательное | Описание |
|---|---|---|
| `type` | да | `GIFT`, `PERCENTAGE`, `COFINANCE`, `FIXED` |
| `discount` | да | Сумма скидки |
| `partner_discount` | | Часть, которую платит ресторан |
| `yandex_discount` | | Часть, которую платит Яндекс |

### `yandex` — везёт курьер Яндекса

`deliveryInfo`:

| Поле | Обязательное | Описание |
|---|---|---|
| `courierArrivementDate` | да | Когда курьер придёт в ресторан |
| `clientName` | | Имя клиента |
| `phoneNumber` | | Телефон (обычно подменный) |
| `additionalPhoneNumbers` | | Доп. телефоны |
| `realPhoneNumber` | | Реальный номер, если клиент согласился |
| `pickupCode` | | Код для идентификации курьера |
| `batches` | | Номера заказов, которые курьер везёт вместе с этим |

`paymentInfo`: `itemsCost` (стоимость блюд с учётом скидки на корзину), `paymentType` (`CARD` — оплачен, `CASH` — не оплачен) — оба обязательны.

Для кухни это «самовывоз курьером»: адреса нет.

### `marketplace` — везём мы

`deliveryInfo`:

| Поле | Обязательное | Описание |
|---|---|---|
| `clientName` | да | Имя |
| `phoneNumber` | да | Телефон |
| `deliveryDate` | да | К какому времени клиент ждёт доставку |
| `deliveryAddress` | да | `{full, latitude, longitude}` — все обязательны, координаты **строками** |
| `additionalPhoneNumbers` | | Доп. телефоны |

`full` — одна строка вида `Москва, улица Тверская, дом 1 строение 4, подъезд 2. 4-й этаж, код домофона: 123 К 4567`.

`paymentInfo`:

| Поле | Обязательное | Описание |
|---|---|---|
| `paymentType` | да | `CARD` / `CASH` |
| `itemsCost` | да | Стоимость блюд |
| `deliveryFee` | да | Стоимость доставки |
| `change` | да | С какой суммы нужна сдача |
| `total` | | `itemsCost + deliveryFee` |

### `pickup` — клиент забирает сам

`deliveryInfo`: `clientName`, `phoneNumber`, `clientArrivementDate` (когда придёт клиент) — обязательны; `additionalPhoneNumbers`.
`paymentInfo`: `paymentType`, `itemsCost`, `change` — обязательны; `total`.

## GET `/order/{orderId}`

Возвращает заказ в той же модели, в какой он пришёл (`application/vnd.eats.order.v2+json`). `404` — массив ошибок.

## PUT `/order/{orderId}`

Яндекс меняет состав заказа и присылает заказ целиком. Работает **только по согласованию с Яндексом**. Ответы: `200 {"result": "OK"}`, `422` — заказ нельзя изменить. Мы его не согласовываем: отвечаем `422`.

## DELETE `/order/{orderId}`

Отмена заказа Яндексом. Тело: `{"eatsId": "...", "comment": "Отказ клиента"}` (`comment` может быть пустым). Ответ `200` без тела, `404` — нет заказа.

## GET `/order/{orderId}/status`

```json
{ "status": "COOKING", "comment": "", "updatedAt": "2026-10-27T12:00:27.870000+03:00" }
```

| Статус | Значение | Наш |
|---|---|---|
| `NEW` | Отправлен в ресторан | `created` |
| `ACCEPTED_BY_RESTAURANT` | Подтверждён | `accepted` |
| `COOKING` | Готовится | `preparing` |
| `READY` | Готов | `ready` |
| `TAKEN_BY_COURIER` | Курьер забрал | `delivering` |
| `DELIVERED` | Завершён | `completed` |
| `CANCELLED` | Отменён | `cancelled` |

Переходы только вперёд `NEW → ACCEPTED_BY_RESTAURANT → COOKING → READY → TAKEN_BY_COURIER → DELIVERED`, в `CANCELLED` — из любого. `comment` до 500 символов.

## PUT `/order/{orderId}/status`

Яндекс сообщает статус со своей стороны. Отмену в общем случае присылает через `DELETE /order`.

| Поле | Обязательное | Описание |
|---|---|---|
| `status` | да | `TAKEN_BY_COURIER`, `DELIVERED` или `CANCELLED` |
| `reason` | | Причина отмены, только с `CANCELLED`, например `place.unable_to_call` |
| `attributes` | | Например `["paid"]` при отмене |
| `comment` | | До 500 символов |
| `updatedAt` | | Время смены |

Ответ `204` без тела.

## PUT `/order/{orderId}/courier`

```json
{
  "courier": { "name": "Василий", "type": "bicycle", "phone": "+79031111111", "status": "accepted" },
  "order": { "orderNr": "260423-SE1234567L", "batches": [] },
  "location": { "latitude": "55.681958", "longitude": "37.589487" },
  "maxPlaceArrivalTime": "2026-10-27T12:10:00.000000+03:00"
}
```

| Поле | Значения |
|---|---|
| `courier.type` | `pedestrian`, `bicycle`, `vehicle`, `motorcycle`, `electric_bicycle`, `rover` |
| `courier.status` | `accepted` — принял заказ, `arrived_to_source` — прибыл в ресторан |
| `maxPlaceArrivalTime` | Расчётное время прибытия в ресторан |

Обязательны `courier` (`name`, `type`), `order` (`orderNr`), `location`. Ответ `204`, `404` — нет ресторана.

## GET `/places/{restaurantId}/schedule`

По расписанию Яндекса. График на неделю, все дни обязательны, пустой массив — выходной, до 10 интервалов в день, время местное:

```json
{ "mon": [ { "start": "10:00", "end": "23:00" } ], "tue": [], "wed": [], "thu": [], "fri": [], "sat": [], "sun": [] }
```

Круглосуточно — `00:00`–`24:00`.

## GET `/places/{restaurantId}/zones` и `/zone/meta` (по подписке)

`zones` — раз в сутки (по умолчанию в 9:00) создаёт зоны: `[{name, coordinates: [{lt, lg}] (4–500 точек), meta}]`.
`zone/meta` — раз в 5 минут обновляет уже созданные зоны (координаты менять нельзя, только новая зона):

| Поле | Описание |
|---|---|
| `zoneId` | id зоны у нас |
| `enabled` | `false` — зона выключается |
| `intervals` | Часы работы по дням, как в графике |
| `averageDeliveryTime` | Среднее время доставки, минуты |
| `thresholds` | 1–10 условий `{orderCost: Money, deliveryCost: Money}`; `Money` = `{currency: "RUB", value}` |
| `courierType` | `pedestrian`, `bicycle`, `vehicle`, `motorcycle` |

## POST `/v1/feedback` (по подписке)

Отзыв клиента: `feedback` (`id`, `eatsId`, `orderId`, `restaurantId`, `rating` 1–5, `comment`, `predefinedComment`, `createdAt`, `takenAt`, `deliveredAt`) и `orderInfo` (схема доставки, состав, итог). Ответ `200 {"result": "OK"}`.

У нас: заказ ищем по `orderId`, затем по `eatsId`, отзыв кладём в `channel.details["feedback"]` и показываем в карточке заказа. Не нашли заказ — `404` (код 103), оценка не 1–5 — `400`. `orderInfo` не читаем.

---

# Push: методы Яндекса

База: `https://dc-partner.eda.yandex.net`. Заголовки: `Authorization` — токен от Яндекса, `Partner-Name` — наше имя партнёра (выдаёт Яндекс). Ошибки: `{"code": <int>, "message": "..."}`.

## POST `/oauth2/token`

Тело `application/x-www-form-urlencoded`: `client_id`, `client_secret` (выдаёт Яндекс). Ответ: `access_token`, `expires_in` (секунды), `scope`, `token_type`.

## POST `/menu/import/initiation`

Попросить Яндекс перечитать меню сейчас, а не при следующем опросе.

```json
{ "restaurantId": "<id филиала>", "operationType": "menu_stop_list" }
```

`operationType`: `menu` (по умолчанию), `menu_stop_list`, `promo`. Шлём `menu_stop_list` при каждом изменении стоп-листа, `menu` — при изменении меню.

## POST `/block`, `/unblock`, `/v2/status`

Пауза ресторана.

- `/block`: `vendorInfo: [{vendorId, deliveryType}]`, `from`, `to` (нет — навсегда), `message` (до 4096), `tag` — `technical_problem` или `too_busy`.
- `/unblock`: `vendorInfo`, `blockIds`.
- `/v2/status`: список блокировок (фильтр `statuses: ["enabled"]` — только активные) — `vendorId`, `blockId`, `externalBlockId`, `deliveryType` (`ddc` / `marketplace`), `status`, `from`, `to`, `source`, `message`, `availableToCancel`; пагинация `limit` / `offset`.

## POST `/platform/orders/{orderId}/codes/validate`

Проверка кода курьера: `{"code": "..."}` → `{"is_valid": true, "validation_attempts_left": 2}`. `409` с кодом 1001 — попытки кончились. `orderId` — наш id заказа. У нас — поле «Код курьера» в карточке заказа Яндекса, когда пришёл курьер и заказ не закрыт

## POST `/v1/orders-history`

История заказов за 180 дней, до 1000 в ответе. Фильтры: `origin_ids` (`[{origin_id, delivery_type}]`), `service` (`YE`, `MD`), `from`, `to`, `status` (`NEW`, `CANCELLED`, `DELIVERED`), `pagination` (`limit`, `offset`). Ответ: `eats_id`, `order_id`, `created_at`, `status`, `service`, `delivery_type` (`native` / `marketplace`), `origin_id`, `items_cost`, `cancel_reason {code, message}`.

У нас — блок «Сверка заказов с Яндексом» на странице интеграции: берём историю филиала за выбранный день (страницами по 1000) и сравниваем с нашими заказами по `eatsId`. Показываем только расхождения: заказа нет у нас; наш заказ за день не попал в историю Яндекса; отменён в Яндексе, а у нас нет; доставлен в Яндексе, а у нас отменён.

## POST `/v1/get-orders-details`

До 100 заказов: `{"eats_ids": [...]}` → `orders` (`eats_id`, `order_id`, `status`, `items` с `price`, `original_price`, `weight`, `modifications`, `items_cost`, `cancel_reason`) и `not_found_eats_ids`.

## POST `/partner-integration/v1/place-info/v1/busy-mode-status`

Рестораны с режимом «высокий спрос» (ставится в приложении Яндекс Еда Вендор). Фильтры `origin_ids` (1–100), `delivery_type`, `service`; пагинация курсором, `limit` до 500. Ответ: `busy_places` (`origin_id`, `delivery_type`, `services`, `extra_minutes`, `valid_till`) и `cursor`.

## POST `/feedback-answer` (по подписке)

Ответ на отзыв: `feedback_id`, `text`, `order_nr`, `promo` (скидка 10, 15, 20, 30 или 40 %). `200` — отправлен, `204` — отзыв неактуален, `403` — нет подписки, `404` — отзыв не найден.

---

# Вопросы к менеджеру Яндекса

1. Есть ли тестовая среда для проверки до живых заказов?
2. Как проходит приёмка интеграции и что проверяют?
3. Наш `Partner-Name` и доступы к push-API.
4. Коды ошибок `ErrorItem.code`, которые нужно согласовать.
5. Как часто опрашиваются меню, стоп-лист и статусы, сколько ждут подтверждения заказа до автоотмены?
6. IP-адреса или подсети, с которых приходят запросы.
7. Подключаем ли сразу Delivery Club (`platform: DC`).
8. Можно ли в `/block` передавать `deliveryType`, которого у ресторана нет (мы шлём и `ddc`, и `marketplace`).

---

# TODO

Готово: OAuth-токен, `/restaurants`, `/restaurants/availability`, `/menu/{id}/composition`, `/menu/{id}/availability`, `/places/{id}/schedule`, все методы `/order`, журнал запросов (`YandexEdaJournal`), таблица `channel_products`, единица измерения у товара (и в клиентском меню), КБЖУ и акциз у товара, НДС филиала, оплата `online`, страница `/staff/integrations/yandex-eda`, бейдж «Подтвердите до» и курьер Яндекса в карточке заказа, push стоп-листа и меню (`Channels.stops_changed/1`, `Channels.menu_changed/1` → `MenuReloadWorker`), ручное подтверждение с тревогой, коды оплаты и отметки Frontpad, пауза ресторана (`/block`, `/unblock`, `/v2/status`), проверка кода курьера, отзывы `/v1/feedback` в карточке заказа, сверка заказов по `/v1/orders-history`, русские переводы. Всё покрыто тестами.

1. Не сделано: `/places/{id}/zones`, `/zone/meta` — у нас нет своих зон доставки (полигонов, стоимости, минимальной суммы), отдавать нечего.
2. **Вопросы к менеджеру Яндекса** — список выше. Особенно п.5: через сколько Яндекс сам отменяет неподтверждённый заказ и шлёт ли предзаказы ночью.
