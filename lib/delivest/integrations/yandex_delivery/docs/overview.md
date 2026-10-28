---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/overview.md
  - https://yandex.com/support/delivery-profile/ru/api/express/overview.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/overview.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422


# Список методов

## Базовые методы

#|
|| **Операция** | **Описание** ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/offers/calculate](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2OfferCalculate.md) | Возвращает доступные варианты доставки. ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/create](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCreate.md) | Cоздает заявку с переданными параметрами. Заявка попадает в систему логистики и запускает процесс заказа. ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md) | Возвращает основную информацию по заявке. ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/accept](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsAccept.md) | Подтверждает заявку при успешной оценке. После подтверждения заявка перейдет в статус `accepted` и сервис запустит процесс поиска исполнителя. ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/cancel-info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCancelInfo.md) | Возвращает информацию об условиях отмены. ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/cancel](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCancel.md) | Отменяет заявку, которая была подтверждена. Операция может быть выполнена в течение ограниченного времени. ||
|#

## Дополнительные методы

### 1. Стоимость и тарифы

#|
|| **Операция** | **Описание** ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/check-price](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2CheckPrice.md) | Возвращает первичную оценку стоимости без создания заявки. ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/tariffs](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2Tariffs.md) | Возвращает тарифы, доступные в точке. ||
|#

### 2. Отслеживание заявки {#track-order}

#|
|| **Операция** | **Описание** ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/driver-voiceforwarding](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2DriverVoiceForwarding.md) | Возвращает номер телефона для звонка курьеру, который выполняет заявку в настоящий момент. ||
|| [GET /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/performer-position](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsPerformerPosition.md) | Возвращает координаты, скорость и направления движения исполнителя заявки. ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/points-eta](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsPointsEta.md) | Возвращает список точек и оценку времени прибытия на точку курьером. ||
|| [GET /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/tracking-links](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsTrackingLinks.md) | Возвращает ссылки для отслеживания курьера. ||
|#

### 3. Код подтверждения
#|
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/confirmation_code](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsConfirmationCode.md) | Возвращает код подтверждения в текущей точке (если это возможно). ||
|#

### 4. Подтверждение доставки
#|
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/proof-of-delivery/info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsProofOfDeliveryInfo.md) | Возвращает данные, подтверждающие доставку. ||
|#

### 5. Редактирование заказа
#|
|| **Операция** | **Описание** ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/edit](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsEdit.md) | Изменяет параметры заявки. Операция доступна до принятия оффера клиентом. ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/apply-changes/request](https://yandex.com/support/delivery-profile/ru/api/express/openapi/ClaimsApplyChangesRequest.md) | Частичное редактирование заявки после ее подтверждения. ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/apply-changes/result](https://yandex.com/support/delivery-profile/ru/api/express/openapi/ClaimsApplyChangesResult.md) | Получает результат применения изменений. ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/return](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsReturn.md) | Инициирует возврат заказа курьером в точку получения.  ||
|#

### 6. Информация по заявкам {#claims-info}

#|
|| **Операция** | **Описание** ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/search](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsSearch.md) | Выполняет поиск произвольных заявок с учетом мультиточек. ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/bulk_info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsBulkInfo.md) | Возвращает информацию по нескольким заявкам с учетом мультиточек. ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/claims/journal](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsJournal.md) | Возвращает историю изменения заявки. ||
|#

### 7. Доставка в течение дня

#|
|| **Операция** | **Описание** ||
|| [POST /b2b.taxi.yandex.net/b2b/cargo/integration/v2/delivery-methods](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2DeliveryMethods.md) | Возвращает список услуг, доступных в точке, с учетом их опций. ||
|#
