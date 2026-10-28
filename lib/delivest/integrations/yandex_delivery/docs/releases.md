---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/ru/api/express/releases.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/releases.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

# История изменений

| Раздел | Описание | Дата обновления |
| :--- | :--- | :--- |
| [Получение вариантов доставки](../express/openapi/IntegrationV2OfferCalculate.md) | Добавлен новый метод [Получение вариантов доставки](../express/openapi/IntegrationV2OfferCalculate.md), при помощи которого вы можете рассчитать и выбрать подходящий вам по стоимости и скорости вариант доставки. Метод возвращает уникальный `payload`, который вам нужно будет не позднее чем через 2 минуты после получения ответа передать в методе [Создание заявки](../express/openapi/IntegrationV2ClaimsCreate.md). | 17.07.2023 |
| [Создание заявки](../express/openapi/IntegrationV2ClaimsCreate.md) | В тело запроса метода [Создание заявки](../express/openapi/IntegrationV2ClaimsCreate.md) добавлен параметр `offer_payload`, в нем нужно передавать полученный идентификатор оффера из ответа метода [Получение вариантов доставки](../express/openapi/IntegrationV2OfferCalculate.md). | 17.07.2023 |
| [Получение информации по заявке](../express/openapi/IntegrationV2ClaimsInfo.md) | В ответ метода [Получение информации по заявке](../express/openapi/IntegrationV2ClaimsInfo.md) добавлен параметр `expected_visit_interval` который вы сможете получать для точек `source` и `destination`. В нем будут зафиксированы интервалы посещения курьером точек согласно офферу, который вы выбрали для осуществления доставки и передали при создании заявки. | 17.07.2023 |
