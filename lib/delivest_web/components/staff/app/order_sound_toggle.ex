defmodule DelivestWeb.OrderSoundToggle do
  use DelivestWeb, :html

  def order_sound_toggle(assigns) do
    ~H"""
    <button
      id="orders-sound-toggle"
      type="button"
      phx-hook=".OrderSoundToggle"
      phx-update="ignore"
    >
      <span class="sound-on">
        <.icon name="hero-speaker-wave" class="size-4 mr-2 align-text-bottom" /> {gettext(
          "Sound is on"
        )}
      </span>
      <span class="sound-off hidden">
        <.icon name="hero-speaker-x-mark" class="size-4 mr-2 align-text-bottom" /> {gettext(
          "Sound is off"
        )}
      </span>
    </button>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".OrderSoundToggle">
      export default {
        mounted() {
          this.render()
          this.el.addEventListener("click", () => {
            localStorage.setItem("orders-sound", this.enabled() ? "off" : "on")
            this.render()
          })
        },
        enabled() {
          return localStorage.getItem("orders-sound") !== "off"
        },
        render() {
          this.el.querySelector(".sound-on").classList.toggle("hidden", !this.enabled())
          this.el.querySelector(".sound-off").classList.toggle("hidden", this.enabled())
          this.el.setAttribute("aria-pressed", String(this.enabled()))
        }
      }
    </script>
    """
  end
end
