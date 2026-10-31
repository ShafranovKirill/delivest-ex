defmodule DelivestWeb.Staff.IntegrationLive.YandexEdaMenu do
  use DelivestWeb, :html

  alias Delivest.Money
  alias DelivestWeb.Staff.OrderLive.OrderHelpers

  attr :menu, :list, required: true
  attr :enabled, :boolean, required: true
  attr :can_edit, :boolean, required: true

  def menu(assigns) do
    ~H"""
    <section
      id="yandex-eda-menu"
      class="space-y-4 rounded-box border border-base-300 bg-base-100 p-5 sm:p-6"
    >
      <div>
        <h2 class="font-bold">{gettext("Menu in Yandex Eda")}</h2>
        <p class="text-sm text-base-content/60">
          {gettext(
            "Every active product of the branch menu goes to Yandex. Turn off what should not be sold there or set its own price."
          )}
        </p>
      </div>

      <p :if={@menu == []} class="text-sm text-base-content/50 italic">
        {gettext("The branch menu is empty")}
      </p>

      <div :for={{category, entries} <- by_category(@menu)} class="space-y-1">
        <h3 class="pt-2 text-xs font-semibold uppercase tracking-wide text-base-content/50">
          {category.name}
        </h3>
        <form
          :for={entry <- entries}
          id={"yandex-eda-product-#{entry.product.id}"}
          phx-change="product"
          class={[
            "grid grid-cols-[auto_1fr_auto] items-center gap-3 rounded-box px-2 py-1.5 transition-colors hover:bg-base-200/60 sm:grid-cols-[auto_1fr_6rem_8rem]",
            not entry.enabled && "opacity-60"
          ]}
        >
          <input type="hidden" name="product_id" value={entry.product.id} />
          <input type="hidden" name="enabled" value="false" />
          <input
            type="checkbox"
            name="enabled"
            value="true"
            class="toggle toggle-primary toggle-sm"
            checked={entry.enabled}
            disabled={not @can_edit}
          />
          <span class="min-w-0 truncate">{entry.product.name}</span>
          <span class="hidden text-right font-mono text-sm text-base-content/50 sm:block">
            {OrderHelpers.money(entry.product.price)}
          </span>
          <input
            type="text"
            inputmode="decimal"
            name="price"
            value={entry.channel_product && Money.input(entry.channel_product.price)}
            placeholder={Money.input(entry.price)}
            phx-debounce="blur"
            class="input input-sm w-full font-mono"
            aria-label={gettext("Price in Yandex Eda")}
            disabled={not @can_edit}
          />
        </form>
      </div>

      <p :if={not @enabled and @menu != []} class="text-sm text-warning">
        {gettext("Orders from Yandex Eda are off for this branch, the menu is not sent.")}
      </p>
    </section>
    """
  end

  defp by_category(menu) do
    menu
    |> Enum.chunk_by(& &1.category.id)
    |> Enum.map(fn [first | _] = entries -> {first.category, entries} end)
  end
end
