defmodule DelivestWeb.StaffPushToggle do
  use DelivestWeb, :html

  attr :id, :string, required: true
  attr :class, :string, default: nil

  def staff_push_toggle(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-hook=".StaffPushToggle"
      phx-update="ignore"
      data-state="loading"
      class={["group", @class]}
    >
      <span class="hidden items-center gap-2 group-data-[state=off]:flex">
        <.icon name="hero-bell-slash" class="size-4" /> {gettext("Turn on notifications")}
      </span>
      <span class="hidden items-center gap-2 group-data-[state=on]:flex">
        <.icon name="hero-bell-alert" class="size-4" /> {gettext("Notifications are on")}
      </span>
      <span class="hidden items-center gap-2 group-data-[state=denied]:flex">
        <.icon name="hero-bell-slash" class="size-4" />
        {gettext("Notifications are blocked in the browser settings")}
      </span>
      <span class="hidden items-center gap-2 group-data-[state=install]:flex">
        <.icon name="hero-device-phone-mobile" class="size-4" />
        {gettext("Add the app to the home screen to get notifications")}
      </span>
      <span class="hidden items-center gap-2 group-data-[state=unsupported]:flex">
        <.icon name="hero-bell-slash" class="size-4" />
        {gettext("This browser does not support notifications")}
      </span>
    </button>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".StaffPushToggle">
      const csrf = () => document.querySelector("meta[name='csrf-token']").content
      const vapidKey = () => document.querySelector("meta[name='vapid-key']")?.content

      const decode = (key) => {
        const base64 = (key + "=".repeat((4 - (key.length % 4)) % 4)).replace(/-/g, "+").replace(/_/g, "/")
        return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0))
      }

      const send = (method, body) =>
        fetch("/staff/push/subscriptions", {
          method,
          headers: { "content-type": "application/json", "x-csrf-token": csrf() },
          body: JSON.stringify(body),
        })

      export default {
        async mounted() {
          this.el.addEventListener("click", () => this.toggle())
          window.addEventListener("staff-push:changed", () => this.refresh())
          await this.refresh()
        },
        async registration() {
          return navigator.serviceWorker.register("/staff/sw.js", { scope: "/staff/" })
        },
        async refresh() {
          this.el.dataset.state = await this.state()
        },
        async state() {
          const ios = /iPad|iPhone|iPod/.test(navigator.userAgent)
          if (!("serviceWorker" in navigator) || !("PushManager" in window) || !vapidKey())
            return ios ? "install" : "unsupported"
          if (Notification.permission === "denied") return "denied"
          const subscription = await (await this.registration()).pushManager.getSubscription()
          return subscription ? "on" : "off"
        },
        async toggle() {
          const state = this.el.dataset.state
          if (state === "on") await this.unsubscribe()
          if (state === "off") await this.subscribe()
          window.dispatchEvent(new Event("staff-push:changed"))
        },
        async subscribe() {
          if ((await Notification.requestPermission()) !== "granted") return
          const registration = await this.registration()
          const subscription = await registration.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: decode(vapidKey()),
          })
          await send("POST", subscription.toJSON())
        },
        async unsubscribe() {
          const subscription = await (await this.registration()).pushManager.getSubscription()
          if (!subscription) return
          await send("DELETE", { endpoint: subscription.endpoint })
          await subscription.unsubscribe()
        },
      }
    </script>
    """
  end
end
