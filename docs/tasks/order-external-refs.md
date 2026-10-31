# Задача: внешние связи заказа

Сейчас `orders.crm` и `orders.channel` — по одному embed. Доставки уже отдельной таблицей (`deliveries`), оплаты и чеки тоже будут таблицами. Заказ из Яндекс Еды, ушедший во Frontpad, с оплатой ЮKassa и чеком АТОЛ — четыре внешних id в трёх разных формах. Уникальность канала держится индексом по JSON (`orders_channel_external_id_index`).

## Решение

Не плодить новые embed в `orders`. Каждая новая связь — своя таблица со ссылкой на заказ, `provider` и `external_id` с уникальностью по паре, как у `deliveries`, `order_payments`, `fiscal_receipts`.

Когда понадобится вторая CRM на заказ или поиск заказа по любому внешнему id — общая таблица `order_external_refs` (`provider`, `role`, `external_id`, `status`, `payload`), уникально `(provider, role, external_id)`, и перенос `crm` и `channel` в неё.

Сейчас не делаем.
