defmodule DelivestWeb.NewOrdersBell do
  use DelivestWeb, :html

  attr :count, :integer, required: true
  attr :branch, :map, required: true

  def new_orders_bell(assigns) do
    ~H"""
    <.link
      id="header-new-orders"
      phx-hook=".NewOrdersBell"
      data-count={@count}
      data-notice={gettext("New order")}
      data-notice-body={@branch.name}
      navigate={~p"/staff/b/#{@branch}/orders?status=created"}
      class="btn btn-ghost btn-sm btn-square relative"
      title={gettext("Orders awaiting confirmation")}
    >
      <.icon name="hero-bell" class="size-5" />
      <span
        :if={@count > 0}
        id="header-new-orders-count"
        class="badge badge-error badge-xs absolute -top-1 -right-1 min-w-5 px-1 font-bold"
      >
        {@count}
      </span>
    </.link>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".NewOrdersBell">
      const titlePrefix = /^\(\d+\) /
      let audio = null

      const unlock = () => {
        audio ??= new AudioContext()
        audio.resume()
        if ("Notification" in window && Notification.permission === "default")
          Notification.requestPermission()
      }

      const chime = () => {
        if (localStorage.getItem("orders-sound") === "off" || !audio) return
        const now = audio.currentTime
        ;[880, 1320].forEach((frequency, index) => {
          const oscillator = audio.createOscillator()
          const gain = audio.createGain()
          const start = now + index * 0.18
          oscillator.frequency.value = frequency
          gain.gain.setValueAtTime(0.0001, start)
          gain.gain.exponentialRampToValueAtTime(0.25, start + 0.02)
          gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.16)
          oscillator.connect(gain).connect(audio.destination)
          oscillator.start(start)
          oscillator.stop(start + 0.17)
        })
      }

      export default {
        mounted() {
          this.count = this.current()
          window.addEventListener("pointerdown", unlock, { once: true })
          this.observer = new MutationObserver(() => this.retitle())
          this.observer.observe(document.querySelector("title"), { childList: true })
          this.retitle()
        },
        updated() {
          const count = this.current()
          if (count > this.count) this.announce()
          this.count = count
          this.retitle()
        },
        destroyed() {
          this.observer.disconnect()
          this.count = 0
          this.retitle()
        },
        current() {
          return Number(this.el.dataset.count)
        },
        announce() {
          chime()
          if (document.hidden && "Notification" in window && Notification.permission === "granted")
            new Notification(this.el.dataset.notice, { body: this.el.dataset.noticeBody, tag: "new-order" })
        },
        retitle() {
          const base = document.title.replace(titlePrefix, "")
          const title = this.count > 0 ? `(${this.count}) ${base}` : base
          if (document.title !== title) document.title = title
        }
      }
    </script>
    """
  end
end
