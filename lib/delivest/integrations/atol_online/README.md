# АТОЛ Онлайн

Облачная касса: регистрирует фискальные чеки (54-ФЗ, ФФД 1.2) на арендованных у АТОЛ ККТ. Задача — [docs/tasks/fiscal-receipts.md](../../../../docs/tasks/fiscal-receipts.md).

- Источник: личный кабинет https://online.atol.ru/lk/, документы прислала поддержка АТОЛ, получены 2026-10-29
- Протокол v5 (ФФД 1.2), документ 3.16 от 21.08.2026: [docs/api-v5.pdf](docs/api-v5.pdf), текст для поиска — [docs/api-v5.txt](docs/api-v5.txt)
- Информация о ККТ и ФН (заполненность ФН, срок замены, ошибки касс): [docs/kkt-info-api.pdf](docs/kkt-info-api.pdf), [docs/kkt-info-api.txt](docs/kkt-info-api.txt)
- v4 (ФФД 1.05) не берём: новые кассы регистрируются только на 1.2

## Доступ

| Что | Значение |
|---|---|
| Хост | `https://online.atol.ru/possystem/v5/` |
| Учётные данные | Логин, пароль и код группы — из «Настроек интегратора» в личном кабинете. Одна группа ККТ = один магазин (место расчётов) |
| Авторизация | `POST getToken` `{login, pass, source}` → токен на 24 часа. Новый просить только на ошибке `ExpiredToken` (11) |
| Токен в запросах | Заголовок `Token: <token>` |
| Content-Type | `application/json; charset=utf-8`, иначе `415` |
| Время | `timestamp` в формате `dd.mm.yyyy HH:MM:SS` |
| Суммы | Рубли числом, до 2 знаков после запятой. У нас пока целые рубли, переход на копейки — [order-foundation.md](../../../../docs/tasks/order-foundation.md) |
| Хранение результатов | `report` отдаёт чек 30 суток, дальше только через поддержку |

## Тестовая среда

Хост `https://testonline.atol.ru/possystem/v5/`. Общие данные от АТОЛ, чеки не уходят в ФНС:

| Что | Без ТС ПИоТ | С ТС ПИоТ |
|---|---|---|
| ИНН | `5544332219` | `5544332219` |
| Место расчётов | `https://v5.online.atol.ru` | `https://v5.online.atol.ru/;https://testonline.atol.ru/` |
| Код группы | `v5-online-atol-ru_5179` | `group_code_5115` |
| Логин | `v5-online-atol-ru` | `5bb41423-6da8-4729-b714-c65e2d8a80e4` |
| Пароль | `zUr0OxfI` | `Bd0NEmkD` |

`company.inn` и `company.payment_address` в чеке должны совпадать с данными группы, иначе ошибка.

Чек на тестовом ОФД: `https://consumer.1-ofd-test.ru/v1?fn=<fn_number>&fp=<fiscal_document_attribute>&i=<fiscal_document_number>` — поля из `payload` результата.

## Сценарий

| Шаг | Метод | Что важно |
|---|---|---|
| 1 | `POST getToken` | Кэшировать токен, обновлять на `ExpiredToken` |
| 2 | `POST <group_code>/<operation>` | Ответ сразу: `uuid` и `status: wait`. Чек ещё не пробит |
| 3 | Callback на `service.callback_url` или `GET <group_code>/report/<uuid>` | Callback может не прийти: если за 300 с его нет, опрашивать `report` |
| — | `status` | `wait` — в очереди, `done` — пробит, `fail` — ошибка, чек не пробит |

Операции: `sell` (приход), `sell_refund` (возврат прихода), `sell_correction`, `sell_refund_correction`. `buy*` — расход, нам не нужен.

## Идемпотентность

- `external_id` — до 128 символов, уникален в группе ККТ. Это наш ключ «один платёж — один чек».
- Повтор с тем же `external_id` → ошибка `IncomingExternalIdAlreadyExists` (33), статус `wait`: чек уже в работе, второй не пробьётся.
- `report` ищет только по `uuid`. Если ответ на регистрацию потерян (таймаут), `uuid` не узнать. **Проверить на тестовой среде**, отдаёт ли ошибка 33 `uuid` существующего чека.
- Ошибки до регистрации (`ValidationException` 13, `IncomingValidationException` 32, токен, `group_code`) — чек не создан, повторять можно с тем же `external_id`.

## Чек `sell`

```json
{
  "timestamp": "29.10.2026 18:00:00",
  "external_id": "<id платежа>",
  "service": {"callback_url": "https://.../integrations/fiscal/atol/<token>"},
  "receipt": {
    "client": {"phone": "+79990001122"},
    "company": {"email": "chek@pizza.ru", "sno": "usn_income", "inn": "5544332219", "payment_address": "https://v5.online.atol.ru"},
    "items": [
      {"name": "Маргарита", "price": 590, "quantity": 1, "measure": 0, "sum": 590,
       "payment_method": "full_payment", "payment_object": 1, "vat": {"type": "none"}}
    ],
    "payments": [{"type": 0, "sum": 590}],
    "total": 590
  }
}
```

| Поле | Значения |
|---|---|
| `client.email` / `client.phone` | Нужно одно из двух, `+79990001122` без пробелов. Если оба — ОФД пришлёт на email |
| `company.sno` | `osn`, `usn_income`, `usn_income_outcome`, `esn`, `patent` (`envd` отменён) |
| `company.email` | Адрес отправителя чека |
| `items[].name` | До 128 символов |
| `items[].sum` | Ровно `price × quantity`. Скидку распределять в цену позиции |
| `items[].measure` | `0` — штуки, `10` — граммы, `11` — кг, `41` — литры |
| `items[].payment_method` | `full_prepayment` — предоплата 100%, `full_payment` — полный расчёт, `advance`, `prepayment`, `partial_payment`, `credit`, `credit_payment` |
| `items[].payment_object` | `1` — товар, `4` — услуга (доставка), `10` — аванс/предоплата, `33` — маркированный товар с кодом |
| `items[].vat.type` | `none`, `vat0`, `vat5`, `vat7`, `vat10`, `vat20`, `vat22`, расчётные `vat105`, `vat107`, `vat110`, `vat120`, `vat122` |
| `payments[].type` | `0` — наличные, `1` — безналичные, `2` — зачёт предоплаты, `3` — кредит. До 10 оплат |
| `vats` | Налог на чек. Если передан и на чек, и на позицию — берётся чек. Можно не передавать, касса посчитает |
| `total` | Сумма `items[].sum` |
| `cashier`, `cashier_inn` | ФИО кассира до 64 символов, ИНН кассира 12 цифр |
| `internet` | `true` для оплаты онлайн (тег 1125) |
| `mark_code` | Код маркировки «Честного знака», base64 в `gs1m`. С ним обязательны `mark_processing_mode: "0"` и `planned_status` |

## Две ступени при предоплате

| Когда | Операция | `payment_method` | `payments` |
|---|---|---|---|
| Клиент оплатил онлайн | `sell` | `full_prepayment` | `type: 1` |
| Заказ передан клиенту | `sell` | `full_payment` | `type: 2` (зачёт предоплаты) |

Оплата курьеру наличными или картой — один чек `full_payment` в момент передачи с `type: 0` или `1`.

## Результат

```json
{
  "uuid": "...", "status": "done", "external_id": "...",
  "payload": {
    "total": 590, "fn_number": "9999078902010421", "fiscal_document_number": 1545,
    "fiscal_document_attribute": 2680485228, "fiscal_receipt_number": 6, "shift_number": 23,
    "receipt_datetime": "29.10.2026 18:00:00", "ecr_registration_number": "...",
    "ofd_inn": "7709364346", "ofd_receipt_url": "https://consumer.1-ofd.ru/v1?...", "fns_site": "www.nalog.ru"
  },
  "error": null
}
```

Хранить весь `payload`: ФН, ФД и ФПД нужны для ссылки на чек, возврата и сверки. `ofd_receipt_url` приходит только у Платформы ОФД, Первого ОФД и Такском.

## Ошибки

Тело ошибки: `{error: {error_id, code, text, type}, status, timestamp}`. Полная таблица — раздел 7 [api-v5.txt](docs/api-v5.txt).

| Код | Ошибка | Что делать |
|---|---|---|
| 1 | `IncomingChequeProcessingFailed` | Повторять с тем же `external_id` |
| 11 | `ExpiredToken` | Новый токен и повтор |
| 12 | `WrongLoginOrPassword` | Постоянная, настройки филиала |
| 13, 32 | Валидация | Постоянная, ошибка в нашем чеке |
| 14 | `UserBlocked` | Постоянная, в поддержку |
| 20 | `GroupCodeAndTokenDontMatch` | Постоянная, настройки |
| 21 | Группа на ФФД 1.05 | Постоянная, группа не переведена на v5 |
| 33 | `IncomingExternalIdAlreadyExists` | Чек уже есть, не дубль. Ждать результат |
| 34 | `StateCheckNotFound` | В `report`: ещё не обработан, опросить позже |
| 42 | `TSPIOTRequired` | Постоянная, нет касс с ТС ПИоТ |
| 50 | `ErrorServerConfiguration` | Повторять |
| 56 | `KKTRequired` | Кассы группы выключены, тревога и повтор позже |
| —, type `timeout` | Чек 300 с в очереди | `fail`, чек не пробит. Повторить с новым `external_id` |
| type `driver` | Ошибки ККТ, раздел 7.2 | По коду: часть — смена, ФН, ОФД |

## Чеки коррекции

`sell_correction`: тело `correction` вместо `receipt`, плюс `correction_info` — `type` (`self` — самостоятельно, `instruction` — по предписанию), `base_date`, `base_number`. Для исправления ошибочного или непробитого чека.

## Маркировка

Вода, соки, пиво в бутылках маркируются «Честным знаком». Для них в позиции `mark_code` и `payment_object: 33`. Разрешительный режим (`permissive_mode`, `use_tspiot`) требует касс с ТС ПИоТ — отдельный документ «API сервиса работы с ТС ПИоТ», у нас его нет.
