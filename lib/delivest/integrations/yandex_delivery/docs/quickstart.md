---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/quickstart.md
  - https://yandex.com/support/delivery-profile/ru/api/express/quickstart.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/quickstart.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

# Начало работы


API Яндекс Доставки предоставляет бизнесу возможность использовать HTTP-запросы для создания заказа.


## Доступ к API {#access}

  Перед началом работы с API получите токен:

  1\. Войдите в [личный кабинет](https://dostavka.yandex.ru/auth/). Для входа используйте логин и пароль, полученные от менеджера Яндекс Доставки.

  2\. Перейдите на вкладку **Интеграции**.

  3\. В разделе **Активируйте интеграцию** нажмите **Получить токен**.

  4\. Используйте этот токен для взаимодействия с API Яндекс Доставки. Для этого в каждом запросе передавайте токен в заголовке `Authorization`:

  ```html
  Authorization: Bearer <OAuth-токен>
  ```
  OAuth-токен действует неограниченное время.
  
## Способы доставки и алгоритм заказа {#methods}


### В России {#russia}

  Для заказов на территории России доступны:

  * Экспресс-доставка: 

    * с вызовом курьера на ближайшее время. Варианты доставки могут отличаться в зависимости от сроков прибытия курьера.

    * с отложенным заказом (если необходимо указать желаемое время прибытия курьера к отправителю). 

  * Грузовая доставка: 

    * с вызовом курьера на ближайшее время;

    * с отложенным заказом.

  Все запросы к API Яндекс Доставки выполняются к хосту `https://b2b.taxi.yandex.net`.

  #|
  || **Этапы заказа** | **Описание** | **Метод API** ||
  ||
  1\. Получите варианты доставки. | Вы отправляете запрос, система рассчитывает предварительную стоимость доступных вариантов доставки. | [offers/calculate](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2OfferCalculate.md)
  ||
  ||
  2\. Создайте заявку на доставку. | Вы создаете заявку на выбранный вариант доставки по конкретному адресу. | [claims/create](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCreate.md) ||
  ||
  3\. Узнайте результат оценки заказа. | Вы отправляете запрос. Если заявка может быть выполнена, в ответ придет актуальная стоимость заказа.
  Если нет — в ответе будут причины, по которым заявка не может быть выполнена. | [claims/info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md) ||
  ||
  4\. Подтвердите заявку. | Если вы согласны с условиями доставки, вы подтверждаете заявку. После этого запускается поиск исполнителя.| [claims/accept](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsAccept.md) ||
  ||
  5\. Отслеживайте статусы заявки. | Вы отправляете запрос по одной или нескольким заявкам и получаете по ним информацию.| Подробнее читайте в разделе **Методы API**:

  * [Отслеживание заявки](https://yandex.com/support/delivery-profile/ru/api/express/overview.md#track-order)

  * [Информация по заявкам](https://yandex.com/support/delivery-profile/ru/api/express/overview.md##claims-info)
  ||
  |#

  В случае проблем обратитесь к менеджеру Яндекс Доставки.



### В других странах {#other}

  Для заказов на территории других стран доступны:


  * Экспресс-доставка: 

    * с вызовом курьера на ближайшее время. Варианты доставки могут отличаться в зависимости от сроков прибытия курьера.

    * с отложенным заказом (если необходимо указать желаемое время прибытия курьера к отправителю). 
  
  * Грузовая доставка: 

    * с вызовом курьера на ближайшее время;

    * с отложенным заказом.
  
  * Доставка в течение дня: отправление будет доставлено в выбранный временной интервал.

  Все запросы к API Яндекс Доставки выполняются к хосту `https://b2b.taxi.yandex.net`.

  #|
  || **Этапы заказа** | **Описание** | **Метод API** ||
  
   ||  1\. Получите первичную оценку стоимости доставки. | Вы отправляете запрос, система рассчитывает первичную стоимость доставки без создания заявки. | [check-price](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2CheckPrice.md) ||
  ||
  2\. Создайте заявку на доставку. | Вы создаете заявку на выбранный вариант доставки по конкретному адресу. | [claims/create](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCreate.md) ||
  ||
  3\. Узнайте результат оценки заказа. | Вы отправляете запрос. Если заявка может быть выполнена, в ответ придет актуальная стоимость заказа.
  Если нет — в ответе будут причины, по которым заявка не может быть выполнена. | [claims/info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsInfo.md) ||
  ||
  4\. Подтвердите заявку. | Если вы согласны с условиями доставки, вы подтверждаете заявку. После этого запускается поиск исполнителя.| [claims/accept](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsAccept.md) ||
  ||
  5\. Отслеживайте статусы заявки. | Вы отправляете запрос по одной или нескольким заявкам и получаете по ним информацию.| Подробнее читайте в разделе **Методы API**:

  * [Отслеживание заявки](https://yandex.com/support/delivery-profile/ru/api/express/overview.md#track-order)

  * [Информация по заявкам](https://yandex.com/support/delivery-profile/ru/api/express/overview.md#claims-info)
  ||
  |#
    
  В случае проблем обратитесь к менеджеру Яндекс Доставки.

## Отмена заказа {#cancel}

При необходимости заявку можно отменить:

1. Узнайте условия отмены с помощью метода [claims/cancel-info](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCancelInfo.md).

   Бесплатная отмена заказа доступна до прибытия курьера к отправителю ([статус](https://yandex.com/support/delivery-profile/ru/api/express/claim-process.md#описание-статусов) `pickup_arrived`). После прибытия курьера отмена заказа будет платной.

2. Отмените заявку с помощью метода [claims/cancel](https://yandex.com/support/delivery-profile/ru/api/express/openapi/IntegrationV2ClaimsCancel.md).

   {% note warning %}

   После передачи товара курьеру отменить заказ можно только через службу поддержки.

   {% endnote %}