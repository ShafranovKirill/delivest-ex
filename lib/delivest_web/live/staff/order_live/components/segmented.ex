defmodule DelivestWeb.Staff.OrderLive.Components.Segmented do
  use DelivestWeb, :html

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :options, :list, required: true
  attr :stacked, :boolean, default: false

  def segmented(assigns) do
    ~H"""
    <div
      id={@id}
      role="radiogroup"
      class={["grid gap-1 rounded-box bg-base-200 p-1", columns(length(@options))]}
    >
      <label
        :for={{value, label, icon} <- @options}
        class={[
          "flex min-w-0 items-center justify-center rounded-field px-2 py-2 text-sm font-medium cursor-pointer text-base-content/70 transition-colors hover:text-base-content has-checked:bg-base-100 has-checked:text-primary has-checked:shadow-sm",
          @stacked && "flex-col gap-1",
          !@stacked && "gap-1.5"
        ]}
      >
        <input
          type="radio"
          name={@name}
          value={value}
          checked={to_string(@value) == value}
          class="sr-only"
        />
        <.icon name={icon} class="size-4 shrink-0" />
        <span class="min-w-0 whitespace-normal text-center leading-tight">{label}</span>
      </label>
    </div>
    """
  end

  defp columns(2), do: "grid-cols-2"
  defp columns(_count), do: "grid-cols-3"
end
