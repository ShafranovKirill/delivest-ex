# Direct: кампании и отчет о расходах

Проверено **2026-11-17**. Запросы [direct.http](examples/direct.http) — статические шаблоны, к API не отправлялись. В F04 доступ только на чтение. Никаких примеров изменения бюджета или кампаний. [Доступ](https://yandex.ru/dev/direct/doc/ru/concepts/access), [быстрый старт](https://yandex.ru/dev/direct/doc/ru/best-practice/quick-start).

## Доступ и окружения

Production endpoint текущей документации: `https://api.direct.yandex.com/json/v501/campaigns` и `https://api.direct.yandex.com/json/v501/reports`. Передается `Authorization: Bearer <DIRECT_OAUTH_TOKEN>`, агентский запрос дополнительно содержит `Client-Login: <CLIENT_LOGIN>`. До первого вызова нужны OAuth-приложение, одобренная заявка на API и соглашение. Ошибки доступа не следует пытаться исправить заменой версии пути на старую `v5`. [Campaigns.get](https://yandex.ru/dev/direct/doc/ru/campaigns/get), [Reports](https://yandex.ru/dev/direct/doc/ru/reports), [доступ](https://yandex.ru/dev/direct/doc/ru/concepts/access).

Песочница документирована отдельно и на английской странице использует `/json/v5/...`; отчеты там моделируются только для одной кампании. Поддержка `/json/v501/...` в sandbox не подтверждена. Версию, URL и результаты песочницы нельзя переносить на production без проверки. [Sandbox](https://yandex.ru/dev/direct/doc/en/concepts/sandbox).

## Кампании

`POST /json/v501/campaigns` с `method: get`: `SelectionCriteria: {}`, `FieldNames: [Id, Name, Type, State, Currency, TimeZone]`, `UnifiedCampaignFieldNames: [CounterIds, PriorityGoals]`, `Page: {Limit, Offset}`. `result.LimitedBy` сигнализирует о следующей странице; сохранять положение и повторять до завершения. Связь со счетчиком и цели читать из кампании, но для пилота сверить их с правами токена и настройками Метрики. Не предполагать одинаковую валюту или часовой пояс всех кампаний. [Campaigns.get](https://yandex.ru/dev/direct/doc/ru/campaigns/get).

## Отчет

`POST /json/v501/reports` с объектом `params`: `SelectionCriteria.DateFrom/DateTo`, `FieldNames: [Date, CampaignId, CampaignName, Impressions, Clicks, Cost]`, `ReportName`, `ReportType: CAMPAIGN_PERFORMANCE_REPORT`, `DateRangeType: CUSTOM_DATE`, `Format: TSV`, `IncludeVAT: YES`. Необязательный `IncludeSubscriptionDiscount` выбирать после проверки условий аккаунта. `IncludeDiscount` устарел с 2015 года, поэтому в новом запросе не используется. [Reports](https://yandex.ru/dev/direct/doc/ru/reports), [спецификация](https://yandex.ru/dev/direct/doc/ru/spec).

Заголовки `processingMode: auto`, `skipReportHeader: true`, `skipReportSummary: true`; **не** ставить `skipColumnHeader`, поскольку имена колонок нужны для проверки и чтения TSV. Без `returnMoneyInMicros: false` денежные значения по умолчанию приходят целыми микродолями валюты (делитель 1 000 000). Парсить как целое/Decimal, не float; значение `Cost` трактовать с учетом `Currency` и `IncludeVAT`. [Заголовки](https://yandex.ru/dev/direct/doc/ru/headers), [формат](https://yandex.ru/dev/direct/doc/ru/format).

| HTTP | Действие |
|---|---|
| 200 | Сохранить TSV с заголовком колонок, проверить порядок и типы, атомарно заменить выбранный период. |
| 201 | Отчет поставлен в очередь; дождаться `retryIn`, повторить **тот же** body. |
| 202 | Еще формируется; дождаться `retryIn`, повторить **тот же** body. |
| 400 | Разобрать ошибку и лимит; не считать каждый 400 временным. |
| 500/502 | Ограниченный повтор с диагностикой `RequestId`; при повторении — разбор причины. |

Для диагностики сохранить `RequestId` и `reportsInQueue` без токена или чувствительных данных. Лимиты: не более 20 запросов за 10 секунд на пользователя; не более 5 офлайн-отчетов в очереди на пользователя; готовый офлайн-отчет хранится 5 часов. Общий лимит Direct включает единицы и не более 5 одновременных запросов к рекламодателю; учитывать `Units`/`Units-Used-Login`. Планировщик должен уважать `retryIn` и освобождать очередь задач на время ожидания. [Режим](https://yandex.ru/dev/direct/doc/ru/mode), [коды](https://yandex.ru/dev/direct/doc/ru/codes), [ограничения отчетов](https://yandex.ru/dev/direct/doc/ru/restrictions), [единицы](https://yandex.ru/dev/direct/doc/ru/concepts/units), [заголовки](https://yandex.ru/dev/direct/doc/ru/headers).

Отчет может содержать до 1 млн строк по умолчанию. При росте данных использовать `Page.Limit/Offset` вместе с устойчивым `OrderBy` или детерминированно разбивать период; проверять полноту каждой части до замены. [Спецификация](https://yandex.ru/dev/direct/doc/ru/spec), [список полей](https://yandex.ru/dev/direct/doc/ru/fields-list).

Статистика обычно меняется в течение трех дней. Для более старых данных использовать `Changes.check` с `BorderDate` или `AUTO`, затем **целиком заменить** затронутый период, включая строки, исчезнувшие из нового отчета. Запись только существующих строк оставит устаревшие расходы. [Актуальность](https://yandex.ru/dev/direct/doc/ru/actual).
