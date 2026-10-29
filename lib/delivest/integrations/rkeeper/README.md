# r_keeper

POS ресторана r_keeper 7 через облачный шлюз White Server (WS API v2 для агрегаторов, UCS). Заказ уходит на кассу ресторана, статус и стоп-лист читаем опросом. Задача — [docs/tasks/rkeeper.md](../../../../docs/tasks/rkeeper.md).

- Коллекция Postman «WS API v2 prod template for agg-s»: [docs/ws-api-v2.postman_collection.json](docs/ws-api-v2.postman_collection.json), получена 2026-10-29. Токен из неё убран — переменная `{{token}}`
- Публичной документации WS API нет: https://docs.rkeeper.ru/rk7/latest/ru/api-19597826.html — XML-интерфейс локального сервера r_keeper 7, не шлюз. Описание методов и статусов просить у UCS
- Ключ провайдера: `:rkeeper`

## Доступ

| Что | Значение |
|---|---|
| Хост, боевой | `https://ws.ucs.ru` |
| Хост, тестовый | `https://ws-test.ucs.ru`, тестовый ресторан `objectId` `199990377` (лояльность — `199990232`) |
| Метод | Один: `POST /wsserverlp/api/v2/aggregators/Create`, тело `{taskType, params}` |
| Авторизация | Заголовок `AggregatorAuthentication: <токен>`. Токен выдаёт UCS агрегатору (нам), один на все рестораны |
| Ресторан | `params.sync.objectId` — код объекта r_keeper. Ресторан подключает нас у себя в WS |
| Ожидание | `params.sync.timeout` — сколько секунд шлюз ждёт ответ кассы. Без ответа — `taskGuid`, результат — `GetTaskResponse {taskGuid}` |
| Ответ | `taskResponse` с результатом, ошибка — `error.wsError.desc` |

Касса ресторана может быть выключена: заказ доходит, только когда агент r_keeper в ресторане на связи. Проверка — `IsMainSystemAvailable`, `GetRestaurantInfo`.

## Заказ

`taskType: CreateOrder`, `params.order`:

| Поле | Наше |
|---|---|
| `originalOrderId` | Наш полный номер или id. Защищает ли от дубля — **проверить** |
| `customer.name`, `customer.phone` | Снимок клиента |
| `customer.loyalty.clientId` | Карта лояльности r_keeper — не используем |
| `expeditionType` | `delivery` или `pickup` |
| `delivery.expectedTime`, `pickup.expectedTime` | ISO 8601 с зоной: `2026-10-29T21:00:00+03:00` |
| `pickup.taker` | `customer` — забирает клиент, `courier` — курьер |
| `pickup.courier` | Имя и телефон курьера, если везёт наш |
| `delivery.address` | `fullAddress`, `city.name`, `street.name`, `houseNumber`, `flatNumber`, `entrance`, `floor`, `intercom`, `coordinates`, `region`, `subway` |
| `products[]` | `id` — код блюда r_keeper, `name`, `price`, `quantity` (дробное для весовых) |
| `products[].ingredients[]` | Модификаторы: `id`, `name`, `quantity`, `price`. Лимит `maxAmountForDish` проверяет касса |
| `payment.type` | `cash`, `card`, `online` |
| `prePayments[]` | Предоплата: `amount`, `currency` — GUID валюты оплаты ресторана |
| `price.total` | Итог |
| `personsQuantity` | Приборы |
| `comment` | Комментарий |
| `orderCategoryCode`, `orderTypeCode` | Категория и тип заказа из справочников ресторана |
| `tableCode` | Стол — для зала, нам не нужен |

Ответ: `taskResponse.order.orderGuid` — id заказа в r_keeper, по нему все остальные операции.

Суммы — рубли числом с копейками.

## После создания

| Что | `taskType` |
|---|---|
| Статус | `GetOrderState {orderGuid}` — опросом, вебхуков в WS API нет |
| Заказ целиком | `GetOrder {orderGuid, allExtendedProperties}`, список — `GetOrderList` |
| Правка состава | `UpdateOrder` |
| Правка без состава | `PatchOrder`: комментарий, адрес, курьер, время, сдача (`ChangeBackFrom`), приборы, способ оплаты |
| Отмена | `CancelOrder {orderGuid, voidReasonCode}`, причины — `GetVoidReasons` |
| Оплата и закрытие | `PayOrder`, `AddPrepayOrder`, `RemovePrepayOrder`, `CompleteOrder` |
| Проверка до создания | `ValidateOrder` |

Значения статусов `GetOrderState` в коллекции нет — **просить у UCS**.

## Меню и стоп-лист

- `GetMenu`, `GetMenuByParams` (по категории заказа) — блюда, модификаторы, комбо, цены. Для сверки артикулов.
- `GetStopList` — стоп-лист, опросом.
- Остальное в коллекции (сотрудники, залы, склад StoreHouse, SQL, создание блюд) нам не нужно.

## Отличия от Frontpad и iiko

| | Frontpad | iiko | r_keeper |
|---|---|---|---|
| Где живёт | Облако | Облако iikoCloud | Касса в ресторане, через облачный шлюз |
| Создание | Синхронно | Асинхронно, команда | Синхронно с ожиданием до `timeout`, иначе `taskGuid` |
| Статусы | Вебхук | Вебхук | Опрос `GetOrderState` |
| Стоп-лист | Опрос | Вебхук и опрос | Опрос |
| Отмена и правка | Нет | Есть | Есть |
| Модификаторы | Товары с `product_mod` | Группы, размеры отдельно | `ingredients` у блюда |
| Авторизация | Ключ ресторана | Ключ ресторана | Наш токен агрегатора + `objectId` ресторана |
