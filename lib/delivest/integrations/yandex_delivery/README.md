# Яндекс Доставка

Исходящий курьерский провайдер: вызываем курьера Яндекса на заказ филиала. Задача — [docs/tasks/courier-delivery.md](../../../../docs/tasks/courier-delivery.md).

- Источник: https://yandex.com/support/delivery-profile/ru/api/express/quickstart, раздел «Экспресс-доставка / Доставка в течение дня»
- Полная копия документации: [docs/](docs/), скачана 2026-10-28 из `llms.txt`. Методы — `docs/openapi/*.md`
- Ключ провайдера: `:yandex`

## Доступ

| Что | Значение |
|---|---|
| Хост | `https://b2b.taxi.yandex.net`, префикс `/b2b/cargo/integration/v2/` |
| Авторизация | `Authorization: Bearer <OAuth>`. Токен — в кабинете dostavka.yandex.ru, вкладка «Интеграции». Бессрочный. Логин выдаёт менеджер |
| Язык | Заголовок `Accept-Language: ru` обязателен |
| TLS | 1.2 и выше |
| Тестовая среда | `https://b2b.taxi.tst.yandex.net`, общий токен из [документации «в другой день»](https://yandex.com/support/delivery-profile/ru/api/other-day/access), только Москва. Проверено 2026-10-29: `tariffs`, `check-price`, `offers/calculate`, `claims/search`, `claims/info`, `claims/journal`, `claims/cancel-info` отвечают, `claims/create` — `403 no_permissions`. Полный путь заявки там не проверить, проверять на боевом с отменой до назначения курьера |
| Лимиты | Чисел нет, при превышении `429` |

## Сценарий для России

| Шаг | Метод | Что важно |
|---|---|---|
| 1 | `offers/calculate` | Варианты с ценой и интервалами. `payload` варианта живёт до `offer_ttl` |
| 2 | `claims/create?request_id=` | `request_id` — идемпотентность: при таймауте или `5xx` повторять с тем же значением |
| 3 | `claims/info?claim_id=` | Ждём `ready_for_approval` с ценой |
| 4 | `claims/accept` | Подтвердить за 10 минут, иначе `failed`. Только после него начинается поиск курьера |
| 5 | `claims/journal` | Статусы опросом по `cursor`. `callback_url` Яндекс называет устаревшим |
| — | `claims/cancel-info`, `claims/cancel` | Бесплатно до `pickup_arrived` |

## Заявка

- Координаты `[долгота, широта]`.
- `address.fullname` — только город, улица, дом. Подъезд, этаж, квартира — отдельными полями.
- `contact.email` обязателен для точки `source`.
- `client_requirements.taxi_class`: `courier` (до 10 кг) или `express` (до 20 кг).
- `due` — время подачи к точке А, для `express` от 30 до 240 минут вперёд. Без него поиск сразу.
- `external_order_id` — наш номер заказа.
- `route_points[].skip_confirmation` — отключить код подтверждения на точке.
- Оплата при получении: `payment_on_delivery`, работает только `card`. **Наличные курьер Яндекса не принимает.**

## Статусы

| Яндекс | Попытка доставки у нас |
|---|---|
| `new`, `estimating`, `ready_for_approval`, `accepted`, `performer_lookup`, `performer_draft` | `searching` |
| `performer_found`, `pickup_arrived`, `ready_for_pickup_confirmation` | `assigned` |
| `pickuped`, `delivery_arrived`, `ready_for_delivery_confirmation`, `pay_waiting`, `delivered` | `picked_up` |
| `delivered_finish` | `delivered` |
| `performer_not_found`, `cancelled_by_taxi`, `failed`, `estimating_failed` | закрыта, новая попытка |
| `cancelled`, `cancelled_with_payment`, `cancelled_with_items_on_hands` | `cancelled` |
| `returning` … `returned_finish` | тревога оператору: заказ возвращается |

Финальные: `delivered_finish`, `returned_finish`, все `cancelled*`, `failed`, `performer_not_found`.

## Курьер

| Что | Метод |
|---|---|
| Имя, машина, компания | `performer_info` в `claims/info` |
| Подменный телефон | `driver-voiceforwarding` |
| Координаты | `claims/performer-position` |
| Время прибытия по точкам | `claims/points-eta` |
| Ссылка отслеживания для клиента | `claims/tracking-links` (помечен устаревшим) |

## Как сделано

| Модуль | Отвечает за |
|---|---|
| `YandexDelivery` | Провайдер `:yandex` для `Couriers.Registry`: заявка, отмена, опрос, данные курьера, настройки филиала |
| `YandexDelivery.Api` | Методы `claims/*` и `driver-voiceforwarding`. Ошибка — `{:yandex_delivery, http_status, code}` |
| `YandexDelivery.Claim` | Тело `claims/create` из заказа и филиала |
| `YandexDelivery.Settings` | Настройки филиала, `branch_info.yandex_delivery` |
| `YandexDelivery.Poller` | `Integrations.Poller` `yandex_delivery`: журнал филиала раз в 10 с, пока есть активные заявки, на 429 пауза 30 с. Cron раз в минуту поднимает оборвавшиеся цепочки |
| `YandexDelivery.Journal` | Курсор журнала филиала, таблица `yandex_delivery_journals` |

### Настройки филиала

Страница `/staff/b/:slug/integrations/yandex-delivery`. Источник курьеров «Яндекс Доставка» выбирается в настройках филиала, там же режим поиска.

| Поле | Что это |
|---|---|
| `token` | OAuth-токен. Пустое поле в форме токен не стирает |
| `contact_name`, `contact_phone`, `contact_email` | Контакт точки А. Пустые имя и телефон — название и телефон филиала. Email обязателен |
| `taxi_class` | `courier` или `express` |
| `vat` | Ставка НДС позиций при оплате курьеру |
| `confirm_codes` | Коды из СМС на точках. По умолчанию выключены (`skip_confirmation`) |
| `auto_accept` | Заявка подтверждается Яндексом сразу после создания. Только по согласованию менеджера |

Подключено, когда заданы токен и email. Для заявки у филиала нужны адрес, координаты и телефон, у заказа — улица, дом и телефон клиента.

### Заявка

- `request_id` — id попытки доставки (`deliveries.id`), `claim_id` пишется в `deliveries.external_id`.
- Точка А — филиал, точка Б — адрес заказа. `external_order_id` и `extra_id` — номер заказа.
- Позиции заказа с ценой. При оплате курьеру (наличные и «Картой курьеру») добавляется `payment_on_delivery: card`, фискализация с НДС из настроек и строка «Доставка» как услуга. Если сумма позиций не сходится с итогом заказа (скидка), позиции пересчитываются пропорционально: каждая строка одной штукой, остаток копеек — в последнюю.
- Наличный заказ после создания заявки переводится на `card_offline` через `Orders.update_payment_method`, изменение пишется в аудит заказа.
- `due` не передаётся: поиск курьера начинается сразу, момент запуска задаёт режим поиска филиала.
- `auto_accept` — галочка «Подтверждать заявку автоматически» в настройках, по умолчанию выключена. Включать, только если менеджер Яндекса подключил её для договора. Без неё заявку в `ready_for_approval` подтверждает опрос через `claims/accept` с `version` из `claims/info`.
- `claims/tracking-links` и `claims/performer-position` — `GET`, остальные методы — `POST`.

### Опрос

`claims/journal` с курсором филиала. По заявкам из событий и по тем, что не обновлялись минуту, запрашивается `claims/info`, статус переводится в попытку через `Couriers.report/3`:

| Яндекс | `Couriers.report` |
|---|---|
| поиск | обновляются детали |
| курьер найден | попытка `assigned` без сотрудника |
| курьер забрал | заказ в `delivering` с источником `delivery`, попытка `picked_up` |
| `delivered_finish` | заказ в `completed`, попытка `delivered` |
| `performer_not_found`, `cancelled_by_taxi` | попытка закрыта `not_found`, новая заявка. После трёх таких — без новой, оператор жмёт «Найти курьера» |
| `failed`, `estimating_failed` | попытка закрыта `provider_error`, в карточке «Яндекс Доставка не приняла последнюю заявку» |
| `cancelled*` | попытка закрыта `provider_cancelled` |
| возврат | тревога в карточке «Курьер везёт заказ обратно» |

Источник `delivery` может перескакивать этапы, как CRM: если курьер забрал заказ, который кухня не отметила готовым, недостающие переходы дописываются.

В `deliveries.details`: `status`, `price`, `eta`, `performer` (имя, машина), `phone` (подменный номер, добавочный через `,,`), `tracking_url` (ссылка точки Б), `synced_at`. Телефон и ссылка перезапрашиваются, когда меняется курьер.

### Ограничения

- Таймаут на `claims/create` закрывает попытку `provider_error`. Повтор кнопкой создаёт новую попытку с новым `request_id`, поэтому при таймауте, после которого Яндекс всё же создал заявку, возможен второй курьер.
- Отмена после `pickup_arrived` платная, `cancel_state` берётся из `claims/cancel-info` без подтверждения оператора.
