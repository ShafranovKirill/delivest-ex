# Задача: iiko как CRM

Вторая CRM после Frontpad через слой `crm/`: заказ уходит в iiko, статусы и стоп-лист приходят обратно. Документация API — [integrations/iiko/README.md](../../lib/delivest/integrations/iiko/README.md).

Делать после рефактора [фундамента заказа](order-foundation.md): iiko опирается на копейки, модификаторы, оплаты, снимок клиента и часовой пояс филиала.

## Решения

| Вопрос | Решение |
|---|---|
| Через что | `Crm.Provider`, как Frontpad. Модуль `Delivest.Integrations.Iiko`, ключ `:iiko`, embed в `Crm.BranchSettings` |
| Авторизация | Новая, v2: `appId` и `clientSecret` — наши, в общих настройках; `apiKey` — у филиала. Старый `apiLogin` — запасной вариант, если ресторан на старой версии |
| Филиал | `organizationId` + `terminalGroupId` выбираются в админке из списков iiko после ввода ключа |
| id заказа | Наш `order.id` — повтор после таймаута не создаёт дубль |
| Чеки | Пробивает iiko на кассе: `fiscalization: external`, онлайн-оплата — `isProcessedExternally`, чек ЮKassa — `isFiscalizedExternally` |
| Доставка | Заказ в iiko доставляет iiko, как с Frontpad |
| Меню | Импорт из iiko, см. [menu-import.md](menu-import.md). Стоп-лист — из iiko |

## Что нужно от слоя CRM

Делается заранее в [crm-layer.md](crm-layer.md). Для iiko из него:

- Состояние `crm.status = confirming`: отправлено, ждём `creationStatus`. Подтверждение — вебхук `DeliveryOrderUpdate`/`DeliveryOrderError` или опрос `commands/status`. Не подтвердилось за N минут — ошибка и повтор с тем же id.
- Необязательный колбэк `cancel_order/2`: у iiko отмена через API, тревога «отмените вручную» (`Crm.manual_cancel_required?/1`) не нужна.
- Необязательный `update_order/3` для правок: комментарий, время, оплаты. Какие правки заказа в CRM разрешены — решает `OrderLock`, см. [order-changes.md](order-changes.md).
- Фиксированная таблица статусов в провайдере вместо таблицы кодов филиала.
- Токен с жизнью час: кэш по `apiKey`, обновление заранее.

## Позиции и модификаторы

- Товар → `productId` из `product_external_ids` (`iiko`).
- Размер: в iiko — шкала размеров (`productSizeId`), у нас — обязательная группа модификаторов. У модификатора группы «Размер» артикул iiko — это id размера, а не товара. В группе модификаторов нужен признак «это размер для iiko» — заложить в [модификаторах](modifiers.md).
- Остальные модификаторы → `modifiers[] {productId, productGroupId, amount, price}`.
- Сверка меню: товары, размеры и модификаторы без артикула — на вкладке «Сверка», как у Frontpad.

## Оплаты

| Наша оплата | iiko |
|---|---|
| Наличные курьеру | `Cash`, сумма, `cash_given` — в комментарий или `paymentAdditionalData` |
| Карта курьеру | `Card` |
| Онлайн (ЮKassa) | `External` или тип ресторана, `isProcessedExternally: true` |
| Сертификат | `Voucher` |

Тип оплаты ресторана (`paymentTypeId`) сопоставляется в настройках, как коды оплат Frontpad.

## Вебхуки

- Админка сама вызывает `webhooks/update_settings` с нашей ссылкой `/integrations/crm/iiko/:token` и `authToken`.
- Вход — через inbox, см. [order-events.md](order-events.md). По вебхуку перечитываем заказ `deliveries/by_id`, пропуски закрываем опросом `deliveries/by_revision`.
- `StopListUpdate` → `Crm.StopSync` для филиала сразу, плюс опрос раз в 10 минут как сейчас.

## Адрес

`Order.Address` → `deliveryPoint`: координаты, улица по названию и городу, дом, корпус, квартира, подъезд, этаж, домофон, комментарий. Перевод — `iiko/address_fields.ex`, как у Frontpad.

## Время

`completeBefore` — местное время терминала без зоны: переводить из UTC по зоне филиала, см. [timezone.md](timezone.md).

## Админка

- Страница `/staff/integrations/iiko`: ключ, выбор организации и группы терминалов, проверка связи (`terminal_groups/is_alive`), типы оплат, сверка, стоп-лист, журнал запросов.
- Карточка на странице интеграций и строка в маршрутах источников.

## Тесты

- Юнит: заказ → тело `deliveries/create` с размером, модификаторами, оплатами, адресом; статусы; ошибки и повторы; вебхуки. Через `Req.Test.stub(Delivest.HTTP.Client, ...)`.
- Контрактный тест `@moduletag :iiko_contract` на демо-ресторане, если iiko его даст.

## До начала

- Тестовый ресторан или `apiKey` у iiko для разработки.
- Регистрация приложения на портале разработчика: `appId` и `clientSecret`.
- Версия iiko у первого ресторана: часть полей с 7.x–9.x (`externalNumber` с 8.0.6, `phoneExtension` с 9.2.5).
