# Яндекс Доставка

Исходящий курьерский провайдер: вызываем курьера Яндекса на заказ филиала. Пока не реализован, задача — [docs/tasks/courier-delivery.md](../../../../docs/tasks/courier-delivery.md).

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
| Тестовая среда | В документации нет — уточнить у менеджера |
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
