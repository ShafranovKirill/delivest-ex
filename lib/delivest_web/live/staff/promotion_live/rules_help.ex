defmodule DelivestWeb.Staff.PromotionLive.RulesHelp do
  use DelivestWeb, :html

  use Gettext, backend: DelivestWeb.Gettext

  @examples [
    {gettext_noop("10% off orders from 1500 ₽"),
     "when subtotal >= 1500\nthen discount 10% max 500"},
    {gettext_noop("Gift for two pizzas"), "when has \"pepperoni\" x2\nthen gift \"cola\""},
    {gettext_noop("Lunch on weekdays for pickup"),
     "when time 11:00..16:00 and weekday in (mon, tue, wed, thu, fri)\n  and fulfillment in (pickup, dine_in)\nthen discount 15%"},
    {gettext_noop("Sale prices shown in the menu"),
     "then price \"margarita\" 399\n     discount 20% on (\"cola\", \"juice\")"},
    {gettext_noop("Fixed discount"), "then discount 300 rub"}
  ]

  def render_help(assigns) do
    assigns = assign(assigns, :examples, @examples)

    ~H"""
    <details id="rules-help" class="rounded-box border border-base-300 bg-base-200/40 text-sm">
      <summary class="cursor-pointer select-none px-3 py-2 font-bold">
        {gettext("Rules syntax")}
      </summary>
      <div class="space-y-3 px-3 pb-3">
        <p class="text-base-content/70">
          {gettext(
            "Rules are «when <condition> then <effects>». The «when» part is optional. Products are referenced by their slug in quotes."
          )}
        </p>
        <div class="grid gap-2 sm:grid-cols-2">
          <div>
            <p class="font-bold mb-1">{gettext("Conditions")}</p>
            <ul class="space-y-0.5 font-mono text-xs" phx-no-curly-interpolation>
              <li>subtotal >= 1500</li>
              <li>quantity >= 3</li>
              <li>has "slug" x2</li>
              <li>fulfillment in (delivery, pickup, dine_in)</li>
              <li>time 11:00..16:00</li>
              <li>weekday in (mon, ..., sun)</li>
              <li>and · or · not · ( )</li>
            </ul>
          </div>
          <div>
            <p class="font-bold mb-1">{gettext("Effects")}</p>
            <ul class="space-y-0.5 font-mono text-xs" phx-no-curly-interpolation>
              <li>discount 10% [max 500]</li>
              <li>discount 300 rub</li>
              <li>discount 20% on "slug"</li>
              <li>discount 50 rub on ("a", "b")</li>
              <li>gift "slug" x1</li>
              <li>price "slug" 399</li>
            </ul>
          </div>
        </div>
        <p class="text-xs text-base-content/60">
          {gettext(
            "«subtotal» is the cart total at menu prices. Unconditional automatic sales are shown in the menu as crossed-out prices."
          )}
        </p>
        <div class="space-y-2">
          <p class="font-bold">{gettext("Examples")}</p>
          <div :for={{title, code} <- @examples}>
            <p class="text-xs text-base-content/60">{gettext_example(title)}</p>
            <pre class="rounded bg-base-100 border border-base-300 p-2 text-xs overflow-x-auto">{code}</pre>
          </div>
        </div>
      </div>
    </details>
    """
  end

  defp gettext_example(title), do: Gettext.gettext(DelivestWeb.Gettext, title)
end
