---
metadata:
  - name: generator
    content: Diplodoc Platform v5.64.0
alternate:
  - https://yandex.com/support/delivery-profile/en/api/express/errors.md
  - https://yandex.com/support/delivery-profile/ru/api/express/errors.md
  - href: https://yandex.com/support/delivery-profile/ru/api/express/errors.md
    type: text/markdown
    title: Markdown version
  - href: https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422
    rel: describedby
---
> **Documentation Index:** Fetch the complete configuration index at https://yandex.com/support/delivery-profile/ru/llms.txt?revision=r21772422

# Справочник ошибок

|Код ошибки | Сообщение | Описание |
|:--- |:--- |:--- |
|401|`unauthorized`|Указан неверный токен. Получите правильный токен в личном кабинете.|
|500|`Internal server error`|Попробуйте еще раз или измените запрос.|
|409|`inappropriate_status`|Недопустимое действие. Заявка уже была подтверждена, отменена или действие невозможно.|
|400|`Parse error`|Проверьте корректность составленного JSON.|
|400|`unknown_zone`|Неверные координаты. Проверьте порядок: [долгота, широта] и попробуйте найти место на Яндекс Картах.|
|400|`invalid_destination_point`|Точка есть, а отправлений нет.|
|400|`invalid_phone_must_start_plus_symbol`|Неверный формат телефона. Проверьте, что формат номера правильный: +79123456789.|
|400|`invalid_phone_size_incorrect`|Неверный формат телефона. Проверьте, что формат номера правильный: (+79123456789), номер содержит символ «+» и верное количество цифр.|
|400|`required_tariffs_disabled_for_user`|Недоступны тарифы. Закончился срок тестового кабинета или указанный тариф отключен.|
|400|`too_many_loaders`|Максимальное количество грузчиков — 2.|
|400|`delay_too_long`|Максимальное количество дней для поля `due` — 3.|
