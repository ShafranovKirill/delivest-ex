# F04: Яндекс Директ и Метрика

**Статус 2026-11-17:** подготовка API-документации завершена, runtime-реализация не начата. Примеры запросов статические; подключений, записи в Яндекс и проверки контрактов на реальном аккаунте не было. [ТЗ F04](https://app.notion.com/p/41b31ec95e448171a833ee7fa73547bc), [аудит](https://app.notion.com/p/41b31ec95e448113921bd76cba9f5b75), [локальный справочник](../README.md).

Стартовая база ветки `codex/yandex-direct-metrika`: root `02c4bf0`, server `94a127a`, client `9fe1ed7`. Эта карточка не обновляет текущие gitlinks и не объявляет прохождение проверок.

## Пакеты внедрения

- [x] Справочник первичных API, границы F04 и статические примеры Direct/Метрики.
- [ ] Устранить блокеры HTTP-слоя и маскирования, реализовать OAuth code/refresh и безопасное хранение токенов.
- [ ] Direct read-only: кампании, `CounterIds`/цели, отчет TSV, очереди и периодическая сверка исправлений.
- [ ] Метрика: доступы счетчика, согласованная цель, загрузка офлайн-конверсий и сверка обработки.
- [ ] Использовать готовые receipts/attribution как источник заказа и атрибуции: сохранить неизменяемый первый источник, для конкретного заказа брать последний достоверный переход за семь суток; не строить второй движок атрибуции.
- [ ] Общий public-offer builder и single-product API с branch scope; прямые ссылки на товары/категории, совместимые с `?product=slug` и `?product=UUID`, и SEO.
- [ ] Клиент: метки, `ClientID`, SPA hit, `reachGoal`, ecommerce data layer; событие `purchase` по подтвержденному серверному `completed`.
- [ ] YML-фид и устойчивые offer ID; регистрация фида без управления бюджетами или запуском кампаний. Пилот на разрешенном аккаунте, адресные тесты, ревью privacy и rollout.

## Блокеры до сетевого пилота

1. `Delivest.HTTP.Client.request/4` сейчас возвращает `{:ok, body}` для всех 2xx. Для Direct Reports необходимо различать 200/201/202 и читать `retryIn`, `RequestId`, `reportsInQueue`, `Units`/`Units-Used-Login`. Добавить opt-in контракт с raw response/metadata, сохранив поведение остальных интеграций. Прямой Req в обход общего клиента не использовать. [Режим отчетов](https://yandex.ru/dev/direct/doc/ru/mode), [заголовки](https://yandex.ru/dev/direct/doc/ru/headers), [единицы](https://yandex.ru/dev/direct/doc/ru/concepts/units).
2. Logger текущего клиента пишет полный URL и error body до `Journal.Mask`; `ms` не входит в маску, multipart/raw body непрозрачен. Перед OAuth/MP и загрузкой файлов адресно усилить маскирование URL, тела и ответа с `measurement_tokens`; не допускать записи токенов. [Управление MP](https://yandex.ru/dev/metrika/ru/data-import/manage-protocol), [MP](https://yandex.ru/dev/metrika/ru/data-import/measurement-upload).
3. `Integrations.TokenCache` не реализует OAuth code flow, refresh, отзыв доступа и повторное подключение. Эти сценарии требуют отдельной реализации и тестов. [OAuth code](https://yandex.ru/dev/id/doc/ru/codes/code-url), [refresh](https://yandex.ru/dev/id/doc/ru/tokens/refresh-client).

## Решения и приемка будущих пакетов

Согласовать политику приватности и сбора ClientID/yclid, сумму `completed` при скидке/возврате/наличных, единый optimization target, offer ID, поведение landing при 404/410, выключение сбора и reconnect destination. Неизменяемый первый источник пользователя хранить отдельно; для заказа выбирать последний достоверный переход за семь суток. Не считать внешние UTM/yclid доверенным источником без серверной проверки. [ТЗ F04](https://app.notion.com/p/41b31ec95e448171a833ee7fa73547bc), [аудит](https://app.notion.com/p/41b31ec95e448113921bd76cba9f5b75).

Будущая адресная приемка: тесты статусов и заголовков Reports, pagination/замена исчезнувших строк, права и 429, фиксация неопределенного исхода upload, повтор после reconnect без дубля, отсутствие секретов в логах, реальные ответы sandbox/пилотного счетчика с явным отличием от подготовленных примеров. До команды «Пуш в Девелоп» полный preflight/E2E и отправка не выполняются. [Direct](direct.md), [Метрика](metrika.md).
