# DaData

Подсказки адресов при вводе и адрес по точке на карте (обратный геокодинг) через dadata.ru.

- Модуль: `Delivest.Integrations.Dadata`
- Настройки: общие для всех филиалов, таблица `dadata_settings` (`api_key`, `enabled`), менять может только `admin`
- Админка: `/staff/integrations/dadata`
- Для клиента: `GET /client/geo/suggest?query=&city=` и `GET /client/geo/reverse?latitude=&longitude=`, не больше 120 запросов в минуту

## Модули

| Модуль | Что делает |
|---|---|
| `Dadata` | Фасад: подсказки, геокодинг, кэш, настройки |
| `Dadata.Api` | Запросы `suggest/address` и `geolocate/address` |
| `Dadata.Address` | Подсказка DaData → наш адрес |
| `Dadata.Settings` | Ключ API и включение |

Ответы кэшируются на 7 дней (`:geo_cache`). Ключ подсказки — нормализованный запрос и город, ключ геокодинга — координаты, округлённые до 4 знаков (~10 м).

## API

База: `https://suggestions.dadata.ru/suggestions/api/4_1/rs`, заголовок `Authorization: Token <api_key>`, тело JSON.

### `POST /suggest/address`

| Параметр | У нас |
|---|---|
| `query` | Что ввёл клиент |
| `count` | 7 |
| `locations` | `[{city}]` — город филиала без «г.» |
| `restrict_value` | `true`, в подсказке не повторяется город |
| `from_bound` | `{value: "street"}` — подсказываем с улицы |

### `POST /geolocate/address`

| Параметр | У нас |
|---|---|
| `lat`, `lon` | Точка пина |
| `count` | 1 |
| `radius_meters` | 100 |

## Что берём из ответа

Обе ручки возвращают `suggestions: [{value, data}]`. `Dadata.Address.from_suggestion/1` переводит каждую подсказку в наш адрес:

| Наше поле | Из DaData |
|---|---|
| `value` (в адресе — `formatted`) | `value` |
| `city` | `data.city`, иначе `data.settlement` |
| `street` | `data.street_with_type`, иначе `data.settlement_with_type` |
| `house` | `data.house` + `data.block_type` + `data.block` («10 к 2») |
| `latitude`, `longitude` | `data.geo_lat`, `data.geo_lon` |
| `fias_id` | `data.house_fias_id`, иначе `data.fias_id` |
| `postal_code` | `data.postal_code` |
| `district` | `data.city_district_with_type` |
| `geo_precision` | `data.qc_geo`: 0 — точные координаты, 1 — ближайший дом, 2 — улица, 3 — населённый пункт, 4 — город, 5 — не определены |

Как эти поля хранятся и уходят в CRM — в [README интеграций](../README.md#единый-адрес).
