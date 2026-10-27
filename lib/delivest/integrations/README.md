# Интеграции

Все внешние сервисы живут в `lib/delivest/integrations/<сервис>/`. У каждого своя папка, свои настройки и свой `README.md` с документацией API.

| Сервис | Папка | Зачем | Настройки | Документация |
|---|---|---|---|---|
| Frontpad | `frontpad/` | CRM: заказы, статусы, сверка меню | на филиал, `branch_info.crm.frontpad` | [frontpad/README.md](frontpad/README.md) |
| Zvonok | `zvonok/` | Вход клиента по звонку | общие, таблица `zvonok_settings` | [zvonok/README.md](zvonok/README.md) |
| DaData | `dadata/` | Подсказки адресов, геокодинг | общие, таблица `dadata_settings` | [dadata/README.md](dadata/README.md) |

Все HTTP-запросы идут через `Delivest.HTTP.Client`. В тестах он подменяется через `Req.Test.stub(Delivest.HTTP.Client, ...)`.

---

## CRM

Слой `crm/` ничего не знает о конкретной CRM. Он отвечает за доставку заказа, повторы, статусы и сверку меню, а всё специфичное делает модуль провайдера.

```
Заказ в приложении
  │  Crm.create_order: заказ со статусом :crm + Oban-задача в той же транзакции
  ▼
Crm.SyncWorker ── Crm.deliver ── Throttle ── Provider.deliver_order(order, settings)
  │                                              │
  │  ok    → SyncState.sent (external_id, номер, предупреждения)
  │  error → Provider.classify_error → :permanent | :retry | {:snooze, сек}
  ▼
CRM меняет статус → POST /integrations/crm/:provider/:token
  │  CrmWebhookController → Crm.handle_webhook → Provider.handle_webhook
  ▼
SyncState.remote_status → статус заказа в приложении
```

### Модули

| Модуль | Отвечает за |
|---|---|
| `Crm` | Фасад: создание заказа, доставка, классификация ошибок, вебхуки, URL вебхука |
| `Crm.Registry` | Единственный список провайдеров. Из него строятся настройки филиала, Enum провайдеров и карточки в админке |
| `Crm.Provider` | Behaviour, который реализует каждая CRM |
| `Crm.BranchSettings` | Настройки CRM филиала: `enabled`, `provider` и по embed на каждого провайдера из реестра |
| `Crm.SyncWorker` | Oban-задача доставки заказа, backoff 10–130 с, до 7 попыток |
| `Crm.SyncState` | Запись результата в `order.crm` и в аудит |
| `Crm.Lookup` | Поиск филиала по токену вебхука и заказа по внешнему id, общий для всех CRM |
| `Crm.OrderNotes` | Примечание для курьера: домофон, комментарий к адресу, комментарий к заказу |
| `Crm.Throttle` | Интервал между запросами к одному аккаунту CRM |
| `Crm.Catalog`, `Crm.CatalogCheck` | Снимок меню CRM и сверка с меню приложения |

### Единый адрес

Адрес хранится в одном формате, `Delivest.Oms.Order.Address`. В заказе он лежит JSON в `orders.address`, у клиента — колонками в `client_addresses`.

| Поле | Что это |
|---|---|
| `city`, `street`, `house` | Город, улица с типом («ул Ленина»), дом с корпусом («10 к 2») |
| `entrance`, `floor`, `apartment`, `intercom` | Подъезд, этаж, квартира, домофон |
| `comment` | Комментарий к адресу («вход со двора») |
| `latitude`, `longitude` | Координаты |
| `formatted` | Полная строка адреса от DaData |
| `fias_id` | ФИАС дома: один и тот же дом у разных клиентов совпадает |
| `postal_code`, `district` | Индекс, район города |
| `geo_precision` | Точность координат DaData `qc_geo`: 0 — точные, 5 — не определены |

Поля DaData заполняются, только когда адрес выбран из подсказки или пином на карте. Если адрес изменили руками, клиент присылает их пустыми.

Каждая CRM переводит этот адрес в свой формат сама, в своей папке. Пример — `frontpad/address_fields.ex`. Всё, для чего у CRM нет поля, уходит в примечание через `Crm.OrderNotes`.

### Как добавить CRM

1. Создать `lib/delivest/integrations/<crm>/` с модулем `Delivest.Integrations.<Crm>` и `@behaviour Delivest.Integrations.Crm.Provider`.
2. Реализовать обязательные колбэки:
   - `key/0` — атом провайдера, он же ключ настроек и сегмент URL вебхука (`:iiko`);
   - `name/0` — название для админки;
   - `settings_schema/0` — embedded-схема настроек с `changeset(settings, attrs, required?)`;
   - `configured?/1` — подключена ли CRM (обычно задан ключ API);
   - `deliver_order/2` — отправка заказа, `{:ok, %{external_id: ...}}`;
   - `classify_error/1` — какие ошибки повторять;
   - `rate_limit/1` — `{ключ_аккаунта, интервал_мс}` или `nil`.
3. Если CRM присылает статусы: `handle_webhook/2`. Поле `webhook_token` в настройках находит `Crm.Lookup`, ссылка строится через `Crm.webhook_url(key(), token)`.
4. Если CRM отдаёт меню: `catalog_source/1` и `fetch_catalog/1`.
5. Добавить модуль в `@modules` в `crm/registry.ex`. Embed в настройках филиала, значение Enum и карточка на странице интеграций появятся сами.
6. Админка: LiveView настроек в `lib/delivest_web/live/staff/integration_live/`, маршрут в `router.ex` и клауза `provider_path/1` в `integration_live/index.ex`.
7. Написать `README.md` по образцу Frontpad: API, лимиты и таблица соответствия наших полей полям CRM.

Новая CRM ничего не меняет у других. Её настройки лежат в отдельном embed, вебхук идёт на свой сегмент URL, а ошибки классифицирует она сама.

### Артикулы товаров

Артикулы CRM хранятся в таблице `product_external_ids`: товар, филиал, `provider` и `external_id`. У товара может быть по артикулу на каждую CRM. Поэтому артикулы новой CRM можно заполнить заранее, пока работает старая, и переключиться без простоя.

- База запрещает повторять артикул одной CRM внутри филиала: `unique (branch_id, provider, external_id)`.
- `Net.ProductCrmIds.by_product(product_ids, provider)` возвращает артикулы товаров для отправки заказа и сверки меню, `by_external_id(branch_id, provider)` делает обратный поиск, например для стоп-листа.
- В форме товара поле артикула строится для каждой CRM из `Crm.Registry`, а колонка «CRM ID» массового импорта пишет в активную CRM филиала.

### Ограничения

- `Throttle` ждёт через `Process.sleep` внутри задачи Oban, и ожидающая задача занимает слот очереди. Сейчас очередь `:crm` берёт 2 задачи одновременно (`config/config.exs`). Когда филиалов станет больше, её стоит расширить, иначе ожидание одного аккаунта будет тормозить заказы других.
