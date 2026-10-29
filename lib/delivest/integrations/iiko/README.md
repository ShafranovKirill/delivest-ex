# iiko

CRM и POS ресторана через iikoCloud API (iikoTransport). Принимает заказы доставки и самовывоза, присылает статусы и стоп-лист вебхуком, отдаёт меню. Задача — [docs/tasks/iiko.md](../../../../docs/tasks/iiko.md).

- Спецификация OpenAPI 3.0: [docs/openapi.json](docs/openapi.json), 349 методов, получена 2026-10-29
- Ключ провайдера: `:iiko`
- `api-edi` (документооборот iiko Server с поставщиками) — не про заказы гостей, не берём

## Доступ

| Что | Значение |
|---|---|
| Хост | `https://api-ru.iiko.services` — в спецификации не указан, проверить при подключении |
| Авторизация, старая | `POST /api/1/access_token` `{apiLogin}` — ключ из iikoWeb |
| Авторизация, новая | `POST /api/v2/access_token` `{appId, clientSecret, apiKey}`. `appId` и `clientSecret` — приложение на портале разработчика https://public-api.iikoweb.ru/portal, один раз на нас. `apiKey` — ресторан генерирует в iikoWeb → «Интеграции» → «API-ключи» |
| Токен | JWT на 1 час, обновления нет — запросить новый до истечения |
| Методы | Все `POST` с JSON, заголовок `Timeout` в секундах (по умолчанию 15) |
| Лимиты | Чисел нет, при превышении `429` |
| Тестовая среда | В документации нет. Спросить у iiko демо-ресторан или тестовый `apiKey` |

## Устройство ресторана

| iiko | У нас |
|---|---|
| Организация (`organizationId`) | Юрлицо или ресторан, `POST /api/1/organizations` |
| Группа терминалов (`terminalGroupId`) | Кассы точки, куда падает заказ. Филиал = организация + группа терминалов |
| Внешнее меню (`menuId`) и ценовая категория | Меню для внешних заказов, `POST /api/2/menu`, `POST /api/menu/v3/by_id` |
| Типы оплат (`paymentTypeId`) | Справочник ресторана, `POST /api/1/payment_types` — сопоставление как `Frontpad.PaymentCodes` |
| Типы заказа (`orderTypeId`) или `orderServiceType` | `DeliveryByCourier` — доставка, `DeliveryByClient` — самовывоз |
| Источники (`marketingSourceId`), причины отмены | Справочники, `POST /api/1/marketing_sources`, `POST /api/1/cancel_causes` |

## Заказ

`POST /api/1/deliveries/create` `{organizationId, terminalGroupId, order}`. Это команда: ответ с `correlationId`, заказ создаётся асинхронно.

| Поле | Наше |
|---|---|
| `order.id` | Наш `order.id`. iiko требует уникальности — повтор с тем же id не создаст дубль |
| `externalNumber` | Наш полный номер заказа |
| `phone`, `phoneExtension` | Телефон с `+`, добавочный отдельно |
| `customer` | Имя, `type: one-time` без согласия на программу лояльности |
| `completeBefore` | Ко времени, **местное время терминала без зоны**. Пусто — как можно скорее |
| `deliveryPoint` | Адрес: `coordinates`, `address.street` (по названию и городу или id классификатора), `house`, `building`, `flat`, `entrance`, `floor`, `doorphone`, `comment` |
| `items[]` | `type: Product`, `productId`, `productSizeId` (если у товара шкала размеров), `amount`, `price`, `comment`, `modifiers[] {productId, productGroupId, amount, price}` |
| `payments[]` | `paymentTypeKind`, `paymentTypeId`, `sum`, `isProcessedExternally` (оплачено снаружи), `isFiscalizedExternally` (чек пробит снаружи), `isPrepay` |
| `tips[]` | Чаевые отдельно от оплат |
| `guests.count` | Приборы |
| `comment` | Комментарий |
| `sourceKey` | Наш маркер источника |
| `externalData` | Пары ключ–значение: наши id и ссылки |

Результат создания: `creationStatus` — `InProgress`, `Success`, `Error`. Узнать: вебхук `DeliveryOrderUpdate` / `DeliveryOrderError`, `POST /api/1/commands/status` по `correlationId` или `POST /api/1/deliveries/by_id`.

Суммы — рубли числом с копейками.

## Статусы

`deliveryStatus` заказа: `Unconfirmed`, `WaitCooking`, `ReadyForCooking`, `CookingStarted`, `CookingCompleted`, `Waiting`, `OnWay`, `Delivered`, `Closed`, `Cancelled`.

| iiko | Наш |
|---|---|
| `Unconfirmed` | `created` |
| `WaitCooking`, `ReadyForCooking` | `accepted` |
| `CookingStarted` | `preparing` |
| `CookingCompleted`, `Waiting` | `ready` |
| `OnWay` | `delivering` |
| `Delivered`, `Closed` | `completed` |
| `Cancelled` | `cancelled` |

Список фиксированный, таблица по умолчанию в коде, не настраивается как коды Frontpad.

## После отправки

В отличие от Frontpad, заказ в iiko можно менять через API — каждая операция тоже команда с `correlationId`:

| Что | Метод |
|---|---|
| Отмена | `deliveries/cancel` (с причиной из `cancel_causes`) |
| Добавить позиции | `deliveries/add_items` |
| Оплаты | `deliveries/change_payments`, `add_payments` |
| Время, адрес, тип, комментарий | `change_complete_before`, `change_delivery_point`, `change_service_type`, `change_comment` |
| Подтверждение | `deliveries/confirm`, `cancel_confirmation` |
| Курьер, статус доставки, трекинг | `update_order_courier`, `update_order_delivery_status` (`Waiting`, `OnWay`, `Delivered`), `update_tracking_link` |
| Закрыть | `deliveries/close` |

## Вебхуки

Настраиваются через API: `POST /api/1/webhooks/update_settings` `{organizationId, webHooksUri, authToken, webHooksFilter}` — нашу ссылку и токен ставит админка, руками в iiko ничего не вводится.

| Событие | Зачем |
|---|---|
| `DeliveryOrderUpdate` | Статус, состав, оплаты заказа |
| `DeliveryOrderError` | Заказ не создался или не сохранился |
| `StopListUpdate` | Стоп-лист изменился — перечитать `stop_lists` |
| `TableOrderUpdate`, `ReserveUpdate`, `PersonalShift` | Зал, брони, смены — не используем |

Вебхук — сигнал: по нему перечитываем заказ `deliveries/by_id`. Пропуски закрывает опрос `deliveries/by_revision`.

## Меню и стоп-лист

- Меню v3 (`/api/menu/v3/by_id`): группы, товары, `sizePrices[]` (шкала размеров с ценами), группы модификаторов с `min`/`max`. Товар может встречаться в нескольких группах — это один товар.
- Для сверки — артикулы товаров (`productId` UUID) в `product_external_ids` с провайдером `iiko`.
- Стоп-лист: `POST /api/1/stop_lists` по организации и группе терминалов, `balance` по товару и размеру.

## Отличия от Frontpad

| | Frontpad | iiko |
|---|---|---|
| Создание | Синхронно, ответ с номером | Асинхронно, подтверждение вебхуком или опросом |
| Идемпотентность | Нет | Наш `order.id` |
| Отмена и правка через API | Нет | Есть |
| Статусы | Коды ресторана, настраиваются | Фиксированный список |
| Размеры | Отдельные товары | Шкала размеров `productSizeId` |
| Модификаторы | Товары с `product_mod` | Группы с `min`/`max` |
| Токен | Секрет в каждом запросе | JWT на час |
| Вебхуки | Ссылка вводится в Frontpad | Ставим сами через API |
