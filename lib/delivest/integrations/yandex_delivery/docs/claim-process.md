---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/claim-process.md
  - https://yandex.com/support/delivery-profile/ru/api/express/claim-process.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/claim-process.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

# Статусная модель

В данном разделе рассматриваются:

* этапы, которые проходит заявка на доставку в процессе обработки;

* методы АPI, доступные на конкретной стадии заказа и изменяющие его состояние.

## Схема выполнения заказа {#create}

![Схема формирования заказа1](https://yastatic.net/s3/doc-binary/src/support/delivery-profile/ru/img/status-process.png)

## Описание статусов

#|
|| **Статус** | **Описание** | **Основные методы** ||
|| `new` | Создана новая заявка. | [Создание заявки](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCreate.md) ||
|| `estimating` | Идет процедура оценки заявки: подбор типа автомобиля по параметрам товара и расчет стоимости.

Чтобы узнать результат оценки, выполните запрос [Получение информации по заявке](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md). | [Получение информации по заявке](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md) ||
|| `ready_for_approval` | Заявка успешно оценена и ожидает подтверждения.

Подтвердите заявку в течение 10 минут после присвоения заявке статуса `ready_for_approval`.
Если вы не согласны со стоимостью и условиями доставки, попробуйте изменить параметры заявки. После редактирования заявка автоматически отправится на переоценку. | [Подтверждение заявки](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsAccept.md)

[Редактирование заявки](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsEdit.md) ||
|| `accepted` | Заявка подтверждена.

Если вы не успели подтвердить заявку по истечении 10 минут с момента присвоения заявке статуса `ready_for_approval`, в ответ на подтверждение заявки вернется статус `failed`. В таком случае создайте новую заявку.| [Подтверждение заявки](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsAccept.md)

[Создание заявки](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCreate.md)  ||
|| `performer_lookup` | После подтверждения заявки формируется заказ, которому присваивается `route_id`. Начинается поиск курьера. | [Получение информации по заявке](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md) ||
|| `performer_draft` | Производится поиск курьера в соответствии с указанными в заявке требованиями. | [Получение информации по заявке](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md) ||
|| `performer_found` | Курьер найден и едет к отправителю (точка **А**).

С этого момента и до завершения заказа вы можете запрашивать следующую информацию:

* Данные о курьере и транспортном средстве (поле `performer_info` в ответе на запрос [Получение информации по заявке](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md)).

* Номер телефона курьера. Если курьер будет заменен по какой-либо причине, перезапросите номер телефона.

* Координаты текущего местоположения курьера.|
[Получение информации по заявке](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md)

[Получение номера телефона курьера](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2DriverVoiceForwarding.md)

[Получение позиции исполнителя заявки](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsPerformerPosition.md)||
|| `pickup_arrived` | Курьер приехал в точку **А**, чтобы забрать заказ. | [Получение информации по заявке](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md) ||
|| `ready_for_pickup_confirmation` | Курьер ждет, когда отправитель назовет ему код подтверждения (статус актуален только при `skip_confirmation = false`).

Код генерируется автоматически после того, как курьер сообщит системе, что он прибыл к отправителю. Получить код можно в личном кабинете, по СМС или с помощью метода API. | [Получение кода подтверждения](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsConfirmationCode.md) ||
|| `pickuped` | Курьер вводит код подтверждения в систему. Передача товара курьеру подтверждена. Запрос [Получение информации по заявке](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md) вернет информацию о посещении точки в поле `visit_status`. | [Получение информации по заявке](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md) ||
|| `delivery_arrived` | Курьер приехал к получателю (точка **Б**).

Курьер пытается дозвониться до получателя в течение 10 минут. Если получатель не отвечает, товар будет возвращен отправителю. | — ||
|| `ready_for_delivery_confirmation` | Курьер сообщает системе, что готов передать товар получателю. Автоматически генерируется код подтверждения и отправляется получателю по СМС. Получатель должен сообщить этот код курьеру. | — ||
|| `pay_waiting` | Заказ ожидает оплаты (статус актуален, если в параметрах заказа выбрана оплата при получении). | — ||
|| `delivered` | Курьер вводит код подтверждения в систему и передает товар получателю. Доставка подтверждена.

Если в заказе несколько точек, курьер отправляется к следующему получателю. | — ||
|| `delivered_finish` | Заказ завершен, курьер доставил товары всем получателям в заказе. | — ||
|| `returning` | Если хотя бы один товар в заказе невозможно передать получателю, курьер возвращает товар.

По умолчанию точка возврата совпадает с точкой **А**, при необходимости можно указать другой адрес возврата. | — ||
|| `return_arrived` | Курьер приехал в точку возврата. | — ||
|| `ready_for_return_confirmation` | Курьер ждет, когда отправитель в точке возврата назовет код подтверждения.

Код генерируется автоматически после того как курьер сообщит системе, что он прибыл на точку возврата. Получить этот код можно через личный кабинет, СМС или с помощью метода API. | [Получение кода подтверждения](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsConfirmationCode.md) ||
|| `returned` | Курьер ввел код подтверждения в систему и вернул товар отправителю. Возврат товара подтвержден. | — ||
|| `returned_finish` | Заказ завершен с возвратом товара. | — ||
|#

## Статусы при отмене заказа {#cancel}

#|
|| `cancelled_by_taxi` | Заказ отменен курьером. Курьер может отменить заказ до момента, пока не получил товар от отправителя (статус `pickuped`). ||
|| `cancelled` | Заказ отменен бесплатно. ||
|| `cancelled_with_payment` | Заказ отменен платно с возвратом товара.||
|| `cancelled_with_items_on_hands` | Заказ отменен платно без возврата товара (заявка была создана с флагом `optional_return`). ||
|#

## Статусы ошибок {#errors}

#|
|| `failed` | При выполнении заказа произошла ошибка, дальнейшее выполнение невозможно. ||
|| `estimating_failed` | Не удалось оценить заявку. Узнать причину можно по запросу [Получение информации по заявке](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md): причина будет указана в ответе в поле `error_messages`.

Отредактируйте заявку с помощью метода [Редактирование заявки](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsEdit.md), и процесс оценки запустится снова.||
|| `performer_not_found` | Не удалось найти курьера. Попробуйте создать новую заявку через некоторое время. ||
|#
