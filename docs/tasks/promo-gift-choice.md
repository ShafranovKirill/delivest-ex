# Задача: акции «N из списка» и выбор подарка клиентом

Сейчас акции умеют требовать конкретный товар (`has "slug" x3`) и дарить конкретный товар (`gift "slug" x1`). Нужно расширить обе стороны списками и дать клиенту выбрать подарок в интерфейсе.

Пример: акция «3 + 1». Клиент покупает 3 любые пиццы из списка, вводит промокод, и ему сразу открывается модалка с бонусными товарами. Он выбирает 1 позицию, она попадает в корзину и в заказ бесплатной строкой.

Основа: `Delivest.Promo` (DSL, движок, корзина), universal-модалки клиента (`client/src/modules/widgets/modal`).

## Решения

| Вопрос | Решение |
|---|---|
| Условие «N из списка» | Суммарное количество по списку. 3 любые пиццы, в том числе 3 одинаковые |
| Награда при N > 1 | Только разные позиции. Для 6 + 2 клиент выбирает 2 разных товара из списка |
| Автоакция без кода | В корзине блок «Доступен подарок» и модалка по кнопке. Сама модалка не открывается |
| Ввод промокода | Если условия уже выполнены — модалка выбора подарка открывается сразу после применения кода |
| Подарок не выбран | Подарок не добавляется. Скидка по акции, если она есть, продолжает работать |
| Модификаторы подарка | Не учитываем. Работаем только по товару, подарочная строка без модификаторов |
| Списки условия и награды | Независимые. Для 3 + 1 можно указать один и тот же список |

## DSL

Старые правила остаются валидными. Добавляются формы со списком в скобках:

```text
# 3 + 1: три любые пиццы из списка, одна пицца в подарок на выбор
when has ("pepperoni", "margherita", "hawaii") x3
then gift ("pepperoni", "margherita", "hawaii") x1

# 6 + 2: шесть товаров из списка, два разных подарка на выбор
when has ("pepperoni", "margherita", "hawaii", "four_cheese") x6
then gift ("pepperoni", "margherita", "hawaii", "four_cheese", "cola") x2
```

- `has ("a", "b") x3` — минимум 3 единицы суммарно по списку.
- `gift ("a", "b") x1` — клиент выбирает 1 позицию из списка.
- `has "a" x3` и `gift "a" x1` работают как раньше.
- `xN` и `x N` равнозначны, без `x` количество равно 1.
- В списке награды должно быть не меньше N уникальных товаров: выбираем только разные позиции.
- Не больше одного `gift (...)` на акцию. Если нужно два разных выбора — это две акции.
- Дубли товаров в списке схлопываются с сохранением порядка.

## Как это работает сейчас

- Правила акции хранятся текстом в `promotions.rules`, парсятся в `Delivest.Promo.Strategy` (`server/src/promo_parser.yrl`, `promo_lexer.xrl`, `lib/delivest/promo/dsl/semantics.ex`).
- `Promo.Engine` при каждом пересчёте корзины выбирает подходящие акции и применяет эффекты.
- Подарки не хранятся в позициях корзины: `Effects.Gifts` каждый раз добавляет виртуальные строки `Line.gift/3` с ценой 0. В заказ они попадают при пересчёте (`Orders.Pricing` → `Lines.from_pricing`).
- Поэтому выбор клиента нужно хранить в контексте корзины и передавать в движок, иначе он исчезнет при любом пересчёте.
- Корзина кешируется (`Cachex`, `:cart_cache`), при изменении контекста пересчитывается и кладётся заново.

Ключевые файлы:

- `server/lib/delivest/promo/{strategy.ex,condition.ex,effects/gifts.ex,result.ex,context.ex,compiled.ex,catalog.ex}`
- `server/lib/delivest/oms/{cart.ex,cart_view.ex,carts.ex,cart_pricing.ex,cart_promo.ex}`
- `server/lib/delivest/oms/orders/pricing.ex`
- `server/lib/delivest_web/controllers/client/cart/*`
- `client/src/modules/cart/*`
- `server/lib/delivest_web/live/staff/promotion_live/*`

## Бэкенд

### 1. DSL и стратегия

`server/src/promo_parser.yrl`:

```text
atom -> 'has' string amount : {has, located('$2'), '$3'}.
atom -> 'has' '(' strings ')' amount : {has_any, '$3', '$4'}.

effect -> 'gift' string amount : {gift, located('$2'), '$3'}.
effect -> 'gift' '(' strings ')' amount : {gift_any, '$3', '$4'}.
```

`strings` уже есть в грамматике и возвращает список `{slug, location}`.

`server/lib/delivest/promo/dsl/semantics.ex`:

- `condition({:has_any, items, quantity})` → `{:has_any, [slug], quantity}`, количество проверяется диапазоном 1..99, ошибка привязывается к локации первого товара.
- `effect({:gift_any, items, quantity})` → `{:gift_any, [slug], quantity}`.
- Ошибка, если `quantity` больше числа уникальных товаров в списке награды.
- Ошибка, если в эффектах больше одного `gift_any`.

`server/lib/delivest/promo/strategy.ex`:

- В типы `condition` и `effect` добавить `{:has_any, [slug], pos_integer()}` и `{:gift_any, [slug], pos_integer()}`.
- `slugs/1`: `has_any` и `gift_any` возвращают весь список.

### 2. Условие «N из списка»

`server/lib/delivest/promo/condition.ex`:

```elixir
def evaluate({:has_any, slugs, quantity}, facts, compiled) do
  # все slug должны найтись в compiled.products, иначе :other
  # have = сумма facts.quantities по product_id из списка
  # missing = quantity - have
end
```

- Считаются только платные позиции: `Facts.quantities` строится из `Basket.quantities/1`, подарки туда не попадают.
- Если условие не выполнено, вернуть причину:

```elixir
%{
  type: :products,
  missing: missing,
  product_ids: [uuid],
  names: ["Пепперони", "Маргарита"]
}
```

- Старый `has` продолжает возвращать причину `:product`.

### 3. Награда и выбор клиента

`server/lib/delivest/promo/context.ex`:

- Новое поле `promo_gifts`: карта `promotion_id => [product_id]`.
- `Context.new/1` нормализует карту: строковые ключи, только непустые списки UUID, дубли убираются.
- Поле необязательное: старые вызовы `Promo.price/2` работают без него.

`server/lib/delivest/promo/effects/gifts.ex`:

- `apply(basket, selected, promo_gifts)` вместо `apply(basket, selected)`.
- `{:gift, slug, quantity}` — без изменений.
- `{:gift_any, slugs, quantity}`:
  - разрешённые товары — `Compiled.product/2` по каждому slug;
  - из `promo_gifts[promotion.id]` берутся только product_id, входящие в разрешённые;
  - дубли убираются, берётся не больше `quantity` позиций;
  - на каждую позицию создаётся `Line.gift(product, 1, promotion.id)`.
- Если выбора нет — подарков нет, но акция остаётся в применённых (см. `gift_choice` ниже), чтобы клиент увидел кнопку выбора.

Цепочка вызова: `Promo.Engine.run/2` → `Effects.apply(basket, selected, context.promo_gifts)`.

### 4. Хранение выбора в корзине

Миграция `server/priv/repo/migrations/<timestamp>_add_promo_gifts_to_carts.exs`:

```elixir
alter table(:carts) do
  add :promo_gifts, :map, null: false, default: %{}
end
```

- `Delivest.Oms.Cart` — поле `promo_gifts`, `context_changeset/2` кастит его вместе с `promo_code`, `fulfillment_type`, `client_id`.
- `Delivest.Oms.CartView` — поле `promo_gifts: %{}`.
- `Carts.build_cart_view/1` — переносит `cart.promo_gifts || %{}`.
- `Carts.update_context/2` уже пересчитывает и кеширует корзину, отдельный путь не нужен.
- `CartPricing.context/2` — добавляет `promo_gifts: view.promo_gifts`.
- Запись невалидного выбора в БД не валидируется на уровне changeset: проверка делается в OMS перед сохранением (см. API), движок дополнительно фильтрует неизвестные id.

### 5. Ответ корзины

`Delivest.Promo.Result`:

- В применённую акцию добавить `gift_choice`:

```elixir
%{
  required: 1,                    # количество из эффекта gift_any
  selected: ["product-uuid"],     # текущий выбор из promo_gifts
  options: [
    %{
      product_id: "product-uuid",
      name: "Пепперони",
      price: 55_000,             # цена в копейках для зачёркивания
      image_url: "https://..."
    }
  ]
}
```

- `gift_choice` равен `nil`, если в акции нет `gift_any`.
- `options` строятся из `compiled.products` по слагам эффекта; неактивные и удалённые товары туда не попадают.
- `selected` фильтруется по допустимым product_id и обрезается до `required` на уровне движка.
- `effective?/1` в `Result`: акция попадает в `applied`, если есть код, скидка, подарки **или `gift_choice`**. Это нужно, чтобы автоакция с невыбранным подарком пришла на клиент.

`PromoJSON.applied/1` и схема `AppliedPromotion` в `server/lib/delivest_web/schemas/cart_schemas.ex`:

- добавить `gift_choice` (nullable);
- новая схема `PromoGiftChoice` и `PromoGiftOption`.

`PromoReason`:

- добавить тип `products` в enum;
- добавить `names: [string]` и `product_ids: [uuid]`.

### 6. API выбора подарка

Маршрут в `server/lib/delivest_web/router.ex` (scope `/client/cart`, pipeline `:cart_rate_limit`):

```text
put "/:cart_id/promotions/:promotion_id/gifts", CartController, :choose_promotion_gifts
```

Контроллер `DelivestWeb.Client.Cart.CartController`:

- `operation(:choose_promotion_gifts, ...)`;
- проверка владельца корзины через существующий `authorize_cart/2`;
- вызов `Oms.choose_promotion_gifts(cart_id, promotion_id, product_ids)`;
- ответ — обычный `CartResponse` с пересчитанной корзиной.

Новая схема запроса:

```elixir
defmodule PromoGiftChoiceRequest do
  # product_ids: [uuid], обязательное, может быть пустым для сброса
end
```

`Delivest.Oms.CartPromo.choose_gifts/3`:

1. `Carts.get_cart_by_id/1` → `CartView`.
2. `CartPricing.apply(view)` → в `view.promotions` найти акцию по `promotion_id`.
3. Если акции нет или у неё нет `gift_choice` → `{:error, {:promo, :gift_not_available}}`.
4. Проверить `product_ids`: уникальные, все входят в `gift_choice.options`, длина от 0 до `required`.
5. Пустой список — удалить ключ из `promo_gifts`, иначе записать новый список.
6. `Carts.update_context(cart_id, %{promo_gifts: updated})`.

Ошибки API:

| Код | Когда |
|---|---|
| `404 promo_gift_not_available` | акция не применена, условие не выполнено или у неё нет выбора подарка |
| `422 promo_gift_invalid` | товар не из списка, дубли, выбрано больше N |
| `404 cart_not_found` | корзина не найдена или чужая |

После изменения схем — `make schema` (обновить `client/src/api/docs/swagger.json` и `client/src/api/types.ts`).

### 7. Заказ

`Delivest.Oms.Orders.Pricing.run/4`:

```elixir
Promo.price(items, %{
  branch_id: ...,
  client_id: ...,
  fulfillment_type: ...,
  code: cart.promo_code,
  promo_gifts: cart.promo_gifts,
  except_order_id: ...
})
```

- Подарочные строки уже попадают в `Result.lines`, `Lines.from_pricing/1` превращает их в позиции заказа с `gift: true` и ценой 0.
- `AppliedPromotion` в заказе менять не обязательно: состав подарков виден по позициям заказа.
- Ограничение: повтор заказа (`Orders.DraftCart`) переносит `promo_code`, но не `promo_gifts`. После повтора выбор нужно сделать заново, в корзине появится блок выбора. Это осознанно; если понадобится — хранить выбор в `orders.promotions`.

## Staff-конструктор акций

`server/lib/delivest_web/live/staff/promotion_live/rules_builder.ex`:

- `@condition_types` + `has_any`;
- `@effect_types` + `gift_any`;
- строки:

```elixir
%{"type" => "has_any", "products" => [], "count" => "1", "add" => ""}
%{"type" => "gift_any", "products" => [], "count" => "1", "add" => ""}
```

- `normalize_condition/1` должен обрабатывать `products` и `add` так же, как `normalize_effect/1`.
- `condition_text/1` → `has ("a", "b") xN`, `effect_text/1` → `gift ("a", "b") xN`.
- `condition_row/1` для `{:has_any, slugs, count}`, `effect_row/1` для `{:gift_any, slugs, count}`.
- Ошибки:
  - список пустой → «Выберите хотя бы один товар»;
  - количество не 1..99 → «Количество должно быть от 1 до 99»;
  - для `gift_any` количество больше числа товаров → «Подарков не может быть больше, чем товаров в списке».

`promotion_form_component.ex`:

- подписи и иконки для новых типов (`has_any` — «N товаров из списка», `gift_any` — «Подарок из списка»);
- поля условия и эффекта: чипы выбранных товаров + селект «+ Добавить товар» + количество. Переиспользовать разметку выбора товаров у скидки на товары;
- событие удаления товара должно знать, где удалять: добавить параметр `kind` (`condition`/`effect`) в `remove_product` или отдельные события.

`rules_text.ex`:

- условие: «в корзине N товаров из списка: A, B»;
- эффект: «подарок на выбор: N из A, B».

`rules_help.ex`:

- в синтаксис добавить `has ("a", "b") x3` и `gift ("a", "b") x1`;
- пример «3 + 1».

Тексты — в `server/priv/gettext/{ru,en}/LC_MESSAGES/default.po`, извлечь и перевести.

## Клиент

### API и стор

`client/src/modules/cart/api/cart.service.ts`:

```ts
async choosePromoGifts(cartId: string, promotionId: string, productIds: string[]): Promise<Cart> {
  const { data } = await api.put<CartResponse>(
    `/client/cart/${cartId}/promotions/${promotionId}/gifts`,
    { product_ids: productIds },
  )
  return data.data
}
```

`client/src/modules/cart/stores/cart.store.ts` — действие `choosePromoGifts(promotionId, productIds)` через существующий `withCart`.

### Модалка

Новый `client/src/modules/cart/components/PromoGiftChoiceModal.vue`, открывается через существующие universal-модалки (desktop drawer / mobile dialog), как `useOpenCart`.

- props: применённая акция с `gift_choice`;
- список вариантов: фото, название, зачёркнутая цена и «Бесплатно»;
- N = 1 — выбор как radio; N > 1 — чекбоксы, нельзя выбрать больше N;
- счётчик «Выбрано X из N»;
- кнопка подтверждения активна при X = N;
- при открытии подставляется текущий `selected`;
- подтверждение → `cartStore.choosePromoGifts`, затем `@close`;
- ошибка API показывается в модалке.

Хелпер `useOpenPromoGiftChoice()` выбирает `useMobileModalStore` или `useDesktopModalStore` по `useViewportStore().isMobile`, заголовок «Выберите подарок».

### Корзина

`client/src/modules/cart/components/PromoCodeInput.vue`:

- после успешного `applyPromoCode` найти в `cartStore.promotions` акцию с тем же `code` и `gift_choice`, где выбрано меньше `required`;
- если найдена — сразу открыть модалку.

`client/src/modules/cart/components/CartPromotions.vue`:

- если у применённой акции есть `gift_choice` и выбрано меньше `required` — блок «Доступен подарок» с кнопкой «Выбрать» (открывает модалку);
- если выбрано ровно `required` — строка «Подарок выбран» и кнопка «Изменить»;
- подарки продолжают отображаться существующими зелёными gift-строками.

Поведение:

- Автоакция: блок в корзине, модалка только по кнопке.
- Промокод: если условия выполнены — модалка сразу после ввода.
- Промокод был `pending`, условия выполнились позже — блок в корзине, без автоматического открытия.
- Подарок не выбран — заказ оформляется без подарка, оформление не блокируется.

### Тексты

`client/src/i18n/locales/ru.ts` и `en.ts`:

- `promo.giftChoice.title`, `hint`, `counter`, `choose`, `change`, `confirm`, `free`, `error`;
- причина `products`: «добавьте ещё {count} из: {names}» / «add {count} more from: {names}»;
- обновить `promoText.ts` для нового типа причины.

## Тесты

Сервер:

- `test/delivest/promo/dsl_test.exs` — парсинг списков, обратная совместимость, ошибки «подарков больше, чем товаров», «два gift_any».
- `test/delivest/promo/engine_test.exs` — `has_any` считает сумму и повторные товары; причина `products`; `gift_any` без выбора не даёт строк, но акция в `applied` с `gift_choice`; выбор даёт подарки; чужой/лишний товар отбрасывается; N ограничивает количество; фиксированный `gift` не сломан.
- `test/delivest/promo/order_flow_test.exs` — выбор из корзины попадает в позиции заказа как gift с ценой 0; повторный пересчёт не теряет выбор.
- `test/delivest_web/controllers/client/cart_promo_controller_test.exs` — новый эндпоинт: успех, сброс пустым списком, чужой товар, больше N, невыполненное условие, чужая корзина, `gift_choice` в ответе.
- `test/delivest_web/live/staff/promotion_live/rules_builder_test.exs` — новые строки, сериализация, ошибки.

Клиент: `pnpm type-check`, `pnpm lint`. Проверить сценарии вручную/e2e: 3 + 1 через код, 6 + 2 через автоакцию, изменение выбора, удаление товара из корзины.

## Крайние случаи

- Условие перестало выполняться после выбора: акция снимается, подарок исчезает, выбор остаётся в корзине и применится снова, когда условие вернётся.
- Товар из списка подарков стал неактивным: он пропадает из `options`; если выбранный набор стал неполным, снова показывается блок выбора.
- Несколько акций с выбором (комбинируемые): выбор хранится отдельно по `promotion_id`, в корзине несколько блоков.
- `gift_any` вместе со скидкой в одной акции: работают оба эффекта.
- Лимиты и выдача промокодов не меняются: выбор подарка не влияет на `Eligibility` и списание использований.
- Временная стоп-лист товара: опции строятся из активного каталога филиала; фильтрацию по стоп-листу можно добавить отдельно, если понадобится.
- Подарки без модификаторов — принятое ограничение.

## Порядок работ

1. DSL и семантика + тесты.
2. Движок: `has_any`, `gift_any`, `gift_choice`, `promo_gifts` в контексте + тесты.
3. Миграция, `Cart`/`CartView`/`Carts`/`CartPricing`, API и схемы + тесты.
4. `Orders.Pricing` и сквозной тест заказа.
5. Staff-конструктор, тексты, gettext.
6. Клиент: сервис, стор, модалка, корзина, i18n.
7. `make check`, `make schema`, ручная проверка сценариев.

## Что не делаем

- Выбор модификаторов для подарочной позиции.
- Несколько независимых списков наград в одной акции.
- Автоматическую подстановку подарка, если клиент не выбрал.
- Сохранение выбора при повторе заказа.
- Автоматическое открытие модалки для автоакции при входе в корзину.

## Открытые вопросы

Нет, решения зафиксированы выше.
