# ЮKassa

Онлайн-оплата (пока не подключена) и чеки по ней. Задача — [docs/tasks/fiscal-receipts.md](../../../../docs/tasks/fiscal-receipts.md).

- Источник: https://yookassa.ru/developers/using-api/openapi-specification
- Спецификация OpenAPI: [docs/openapi.yaml](docs/openapi.yaml), скачана 2026-10-29

## Доступ

| Что | Значение |
|---|---|
| Хост | `https://api.yookassa.ru/v3` |
| Авторизация | Basic: `shopId` и секретный ключ из кабинета |
| Идемпотентность | Заголовок `Idempotence-Key` у всех `POST`, до 64 символов, рекомендуют UUID v7 |
| Уведомления | Вебхуки на события (`payment.succeeded` и др.), настраиваются в кабинете или `POST /webhooks` |
| Тестовая среда | Тестовый магазин в кабинете: свой `shopId` и ключ, тестовые карты, у объектов `test: true` |

## Чеки

`GET /me` → `fiscalization.provider`: чем магазин отправляет чеки.

| Решение | `provider` | Как |
|---|---|---|
| Чеки от ЮKassa | `avanpost`, `yoo_receipt` | Касса ЮKassa, наша не нужна |
| Сторонняя онлайн-касса | `atol` и др. | Аккаунт АТОЛ подключается в кабинете ЮKassa. Мы передаём данные чека ЮKassa, она сама шлёт их в АТОЛ |

Сценарии со сторонней кассой:

- **Платёж и чек вместе**: объект `receipt` в `POST /payments`. Статус чека — `receipt_registration` у платежа: `pending`, `succeeded`, `canceled`.
- **Сначала платёж, потом чек**: `POST /receipts` с `type: payment` и `payment_id`.
- **Второй чек** (полный расчёт при передаче заказа): `POST /receipts`, `settlements` с зачётом предоплаты.
- **Возврат**: `receipt` в `POST /refunds` или `POST /receipts` с `type: refund` и `refund_id`.

Поля чека свои, не как у АТОЛ: `customer`, `items[].vat_code`, `payment_subject`, `payment_mode`, `measure`, `tax_system_code` (для АТОЛ на ФФД 1.2 обязателен). До 100 позиций для сторонней кассы, 80 — для Чеков от ЮKassa.

## Офлайн

`/pos_links` — платёжные таблички с QR и NFC для оплаты в точке. Вариант оплаты картой и СБП курьеру и в зале без терминала.
