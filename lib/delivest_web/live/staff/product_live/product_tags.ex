defmodule DelivestWeb.Staff.ProductLive.ProductTags do
  use DelivestWeb, :html

  alias Delivest.Net.Product

  def label(:hit), do: gettext("Hit")
  def label(:new), do: gettext("New")
  def label(:spicy), do: gettext("Spicy")
  def label(:vegetarian), do: gettext("Vegetarian")

  def without_blank(%{"tags" => tags} = params) when is_list(tags),
    do: %{params | "tags" => Enum.reject(tags, &(&1 == ""))}

  def without_blank(params), do: params

  attr :field, Phoenix.HTML.FormField, required: true

  def tag_checkboxes(assigns) do
    assigns = assign(assigns, tags: Product.tags(), selected: selected(assigns.field.value))

    ~H"""
    <fieldset class="space-y-2">
      <legend class="label-text font-bold">{gettext("Labels")}</legend>
      <input type="hidden" name={@field.name <> "[]"} value="" />
      <div class="flex flex-wrap gap-2">
        <label
          :for={tag <- @tags}
          class="flex items-center gap-2 rounded-full border border-base-300 px-3 py-1.5 cursor-pointer has-checked:border-primary has-checked:bg-primary/10"
        >
          <input
            type="checkbox"
            name={@field.name <> "[]"}
            value={tag}
            checked={to_string(tag) in @selected}
            class="checkbox checkbox-xs checkbox-primary"
          />
          <span class="text-sm">{label(tag)}</span>
        </label>
      </div>
      <p class="text-xs text-base-content/60">
        {gettext("Shown on the product card on the website with a matching icon.")}
      </p>
    </fieldset>
    """
  end

  defp selected(values) when is_list(values), do: Enum.map(values, &to_string/1)

  defp selected(_values), do: []
end
