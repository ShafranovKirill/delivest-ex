# Задача: r_keeper как CRM

Третья CRM через слой `crm/`: заказ уходит на кассу r_keeper 7 ресторана через облачный шлюз White Server (WS API v2 для агрегаторов). Документация — [integrations/rkeeper/README.md](../../lib/delivest/integrations/rkeeper/README.md).

Делать после рефактора [фундамента заказа](order-foundation.md) и после [iiko](iiko.md): r_keeper использует те же доработки слоя CRM (отмена и правка через API, фиксированные статусы), плюс опрос статусов.

## Решения

| Вопрос | Решение |
|---|---|
| Через что | `Crm.Provider`, модуль `Delivest.Integrations.Rkeeper`, ключ `:rkeeper`, embed в `Crm.BranchSettings` |
| Доступ | Токен агрегатора `AggregatorAuthentication` — наш, один на франшизу, в общих настройках. У филиала — `objectId` ресторана |
| Подключение ресторана | Ресторан у себя в WS r_keeper подключает нас как агрегатора и сообщает `objectId` |
| Чеки | Пробивает касса r_keeper: `fiscalization: external` |
| Доставка | Везёт ресторан или наш курьер — `pickup.taker` и `pickup.courier` |
| Меню | Основное — наше. Из r_keeper — сверка кодов блюд и стоп-лист |

## Что нужно от слоя CRM

Общее — в [crm-layer.md](crm-layer.md), опрос — в [integration-kit.md](integration-kit.md). Для r_keeper:

- **Опрос статусов.** Вебхуков у WS API нет. `Rkeeper.StatusPollWorker` раз в 30–60 с опрашивает `GetOrderState` по активным заказам филиала, найденное отдаёт в `Crm.handle_webhook`-подобный путь. Останавливается на финальном статусе.
- **Ожидание ответа кассы.** `CreateOrder` с `sync.timeout`: ответ пришёл — `orderGuid` сразу; не пришёл — `taskGuid`, состояние `confirming`, как у iiko, и опрос `GetTaskResponse`.
- **Касса недоступна.** `IsMainSystemAvailable` перед отправкой и в проверке связи. Касса выключена — `{:snooze, …}`, тревога у оператора, если не ушёл за N минут.
- Отмена (`CancelOrder` с причиной) и правка (`PatchOrder`, `UpdateOrder`) — те же необязательные колбэки, что для iiko.

## Позиции и модификаторы

- Блюдо → `products[].id` — код r_keeper в `product_external_ids` (`rkeeper`).
- Модификаторы → `products[].ingredients[]` с кодами r_keeper. Размер — обычно отдельное блюдо или модификатор, смотря как настроен ресторан: артикул r_keeper у модификатора-размера может указывать на блюдо. Решить по меню первого ресторана.
- Весовые блюда — дробное `quantity`.

## Оплаты

| Наша оплата | r_keeper |
|---|---|
| Наличные | `payment.type: cash`, сдача — `ChangeBackFrom` |
| Карта курьеру | `payment.type: card` |
| Онлайн | `payment.type: online` + `prePayments[] {amount, currency}` — GUID валюты ресторана, выбирается в настройках филиала |

## Справочники ресторана

В настройках филиала выбираются из ответов r_keeper: категория и тип заказа (`orderCategoryCode`, `orderTypeCode`) для доставки и самовывоза, валюта предоплаты, причина отмены по умолчанию (`GetVoidReasons`).

## Админка

- Страница `/staff/integrations/rkeeper`: `objectId`, проверка связи (`GetRestaurantInfo`, `IsMainSystemAvailable`), справочники, сверка меню (`GetMenu`), стоп-лист (`GetStopList`), журнал запросов.
- Карточка на странице интеграций и строка в маршрутах источников.

## Тесты

- Юнит: заказ → `CreateOrder` с модификаторами, оплатами, адресом; `taskGuid` и ожидание; статусы опросом; касса недоступна. Через `Req.Test.stub(Delivest.HTTP.Client, ...)`.
- Контрактный тест `@moduletag :rkeeper_contract` на `ws-test.ucs.ru` с тестовым рестораном `199990377` и нашим тестовым токеном.

## До начала — у UCS

- Наш токен агрегатора: тестовый и боевой.
- Документация WS API v2: поля ответов, значения статусов `GetOrderState`, коды ошибок, лимиты.
- Защищает ли `originalOrderId` от дубля при повторе.
- Есть ли уведомления об изменении заказа вместо опроса.
