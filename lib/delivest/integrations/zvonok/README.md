# Zvonok

Вход клиента по номеру телефона через zvonok.com: клиент звонит на выданный номер, Zvonok сбрасывает звонок и сообщает нам о нём вебхуком.

- Модуль: `Delivest.Integrations.Zvonok`
- Настройки: общие для всех филиалов, таблица `zvonok_settings`, менять может только `admin`
- Админка: `/staff/integrations/zvonok`
- Галочка «Вход клиентов» (`enabled`). Когда она снята, входа на сайте нет совсем: `POST /client/auth/*` отвечает `403 auth_disabled`, токены клиентов не принимаются, все заказывают как гости. Сайт узнаёт об этом по полю `client_auth` в `GET /client/franchise`.

## Модули

| Модуль | Что делает |
|---|---|
| `Zvonok` | Фасад: запрос звонка, проверка токена вебхука, настройки |
| `Zvonok.Api` | Запрос подтверждения номера и разбор ответа |
| `Zvonok.Settings` | `enabled`, `public_key`, `campaign_id`, `webhook_token` |
| `DelivestWeb.Integrations.ZvonokWebhookController` | Приём вебхука о звонке |

Логика входа живёт не здесь, а в `Delivest.Identity.ClientAuth`. Zvonok только запрашивает звонок и сообщает, что он был.

## Как проходит вход

1. Клиент вводит номер → `POST /client/auth/call` → `ClientAuth.start` → `Zvonok.request_call(phone)`.
2. Zvonok возвращает `call_id` и номер, на который нужно позвонить. Мы создаём `PhoneConfirmation` и показываем номер клиенту.
3. Клиент звонит. Zvonok шлёт `GET /integrations/zvonok/<webhook_token>?call_id={ct_call_id}&phone={ct_phone}`.
4. `ClientAuth.confirm_call` помечает подтверждение и отправляет событие в сокет.
5. Клиент получает событие или опрашивает `POST /client/auth/call/:id/complete` и получает токены.

Подтверждение живёт 10 минут (`PhoneConfirmations.ttl_minutes/0`).

## API

`GET https://zvonok.com/manager/cabapi_external/api/v1/phones/confirm/`

| Параметр | Значение |
|---|---|
| `public_key` | Ключ API кабинета |
| `campaign_id` | Кампания «подтверждение номера» |
| `phone` | Номер клиента |

Успешный ответ: `status: "ok"`, `data.call_id` и номер для звонка в `allowed_phones_for_call`. Мы берём первый номер из списка.

## Вебхук

Ссылку для кабинета Zvonok выдаёт `Zvonok.webhook_url/1`. В ней уже есть плейсхолдеры `{ct_call_id}` и `{ct_phone}`, которые Zvonok подставляет сам. Неизвестный токен → `404`, звонок без ожидающего входа → `200 {"result": "ignored"}`.

## Разработка

В `dev` звонок не нужен: `config :delivest, auto_confirm_phone: true` в `config/dev.exs`. `ClientAuth` не вызывает Zvonok и сразу подтверждает вход. Флаг читается при компиляции, поэтому в прод-сборке этой ветки кода нет.
