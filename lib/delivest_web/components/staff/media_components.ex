defmodule DelivestWeb.Staff.MediaComponents do
  use DelivestWeb, :html

  attr :label, :string, required: true
  attr :media, :any, default: nil
  attr :url, :string, default: nil
  attr :readonly, :boolean, default: false
  attr :target, :any, required: true

  def image_field(assigns) do
    ~H"""
    <fieldset class="fieldset w-full">
      <legend class="fieldset-legend">{@label}</legend>
      <div class="flex flex-wrap items-center gap-4">
        <div class="avatar">
          <div class="flex size-24 items-center justify-center overflow-hidden rounded-box border border-base-300 bg-base-200">
            <img :if={@url} src={@url} alt={@label} class="size-full object-cover" />
            <span :if={!@url} class="text-xs text-base-content/60">{gettext("No image")}</span>
          </div>
        </div>
        <div :if={!@readonly} class="flex-1">
          <button
            type="button"
            phx-click="open_upload_modal"
            phx-target={@target}
            class="btn btn-outline btn-sm"
          >
            <.icon name="hero-photo" class="size-4" />
            {if @media, do: gettext("Change Image"), else: gettext("Upload Image")}
          </button>
          <p class="mt-1 text-xs text-base-content/60">{gettext("PNG, JPG, WEBP up to 5MB")}</p>
        </div>
      </div>
    </fieldset>
    """
  end
end
