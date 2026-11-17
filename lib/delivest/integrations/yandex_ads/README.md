# Яндекс Директ и Метрика

Реализация добавлена **2026-11-17** в рабочую ветку: настройки и OAuth, независимые потоки Метрики, серверные конверсии, расходы, товарные фиды и отчёты с переиспользованием F04. Все возможности по умолчанию выключены. Настоящий кабинет и production не подключались. Примеры в `docs/examples/` остаются синтетическими; они не являются результатами сетевого пилота. Подключение, ограничения и проверки — в [карточке реализации](docs/implementation.md).

| Задача F04 | Документ | Граница |
|---|---|---|
| Прочитать кампании и расходы | [Direct](docs/direct.md) | Только чтение; без изменения бюджета, ставок, кампаний |
| Цели, офлайн-конверсии, Measurement Protocol | [Метрика](docs/metrika.md) | Запись только для согласованных целей и событий |
| Каталог и клиентские события | [Каталог и события](docs/catalog-and-events.md) | Спецификация для будущего пилота |
| Проверяемые первоисточники | [Источники](docs/sources.md) | Ссылки и статус проверки |
| Пакеты внедрения и приёмка | [Карточка F04](docs/implementation.md) | Локальная реализация; внешняя приёмка отдельно |

## Доступ и обращение с данными

Для Direct сначала зарегистрировать OAuth-приложение, получить одобрение заявки на API и принять соглашение. [Шаблон OAuth](docs/examples/oauth.http) показывает code flow и refresh со значениями-заглушками. OAuth-токен Direct передавать как `Authorization: Bearer ...`; для агентского доступа нужен `Client-Login`. Для Метрики токен передается как `Authorization: OAuth ...` с пробелом и минимальными scope: `metrika:read` для чтения, `metrika:write` для целей/настроек, `metrika:offline_data` для импорта. Токен Measurement Protocol (`ms`) отдельный секрет, не OAuth-токен. Проверять TLS; токены и `ms` не писать в журнал и не включать в примеры. [Direct access](https://yandex.ru/dev/direct/doc/ru/concepts/access), [Direct quick start](https://yandex.ru/dev/direct/doc/ru/best-practice/quick-start), [Метрика: авторизация](https://yandex.ru/dev/metrika/ru/intro/authorization), [Measurement Protocol](https://yandex.ru/dev/metrika/ru/data-import/measurement-upload).

HTTP-запросы идут через `Delivest.HTTP.Client` на базе Req с `journal:`. Опция `response: :full` сохраняет статус и заголовки (`retryIn`, `RequestId`, `Units`), не меняя стандартный контракт других интеграций. URL, OAuth-коды, токены и исключения маскируются до журналирования; чувствительное содержимое MP также исключено из журнала запроса. OAuth реализован отдельно от `Integrations.TokenCache`. [Локальные правила интеграций](../README.md), [OAuth code flow](https://yandex.ru/dev/id/doc/ru/codes/code-url), [refresh](https://yandex.ru/dev/id/doc/ru/tokens/refresh-client).

Параметры меток/`yclid` из URL — внешние данные. Неизменяемый первый источник пользователя хранится отдельно; атрибуция конкретного заказа — последний достоверный переход за семь суток, вычисленный сервером. Интеграции `yandex_eda` и `yandex_delivery` к рекламному API не относятся. [Макросы и метки Direct](https://yandex.ru/support/direct/ru/statistics/url-tags), [контекст F04](https://app.notion.com/p/41b31ec95e448171a833ee7fa73547bc).

## Пилот и открытые решения

1. На тестовом аккаунте с разрешенным доступом проверить чтение кампаний, пагинацию, отчет TSV и выбранную семантику НДС/скидок; зафиксировать валюту и часовой пояс кампании. [Campaigns.get](https://yandex.ru/dev/direct/doc/ru/campaigns/get), [Reports](https://yandex.ru/dev/direct/doc/ru/reports), [спецификация](https://yandex.ru/dev/direct/doc/ru/spec).
2. Согласовать с владельцем счетчика единый optimization target и жизненный цикл цели, доступы к `ClientID` и политику приватности на старте. Для отложенного `completed` использовать офлайн-цель; MP не считать единственным надежным источником финальной конверсии. [Офлайн-конверсии](https://yandex.ru/dev/metrika/ru/management/offline-conv), [Measurement Protocol](https://yandex.ru/dev/metrika/ru/data-import/measurement-about).
3. Решить правила суммы: скидка, возврат, наличная оплата, частичная отмена; фиксировать конвертацию копеек в десятичные рубли без float. Согласовать идентификатор товарного предложения между YML, событиями и заказом. [Поля отчета](https://yandex.ru/dev/direct/doc/ru/format), [ecommerce Метрики](https://yandex.ru/support/metrica/ru/data/e-commerce).
4. Согласовать поведение server landing при 404/410, выключение сборщика и повторное подключение destination. Перед запуском отдельно проверить, что отключение прекращает новые отправки и что неопределенный исход загрузки разрешается сверкой. [Загрузка](https://yandex.ru/dev/metrika/ru/management/openapi/offline_conversions/upload_1), [статус загрузки](https://yandex.ru/dev/metrika/ru/management/openapi/offline_conversions/findById_1).

Локальные материалы проекта: [F04](https://app.notion.com/p/41b31ec95e448171a833ee7fa73547bc), [аудит](https://app.notion.com/p/41b31ec95e448113921bd76cba9f5b75). Они задают продуктовый контекст; параметры HTTP ниже сверены с документацией Яндекса.
