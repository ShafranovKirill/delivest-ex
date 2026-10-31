self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("fetch", () => {});

self.addEventListener("push", (event) => {
  const message = event.data ? event.data.json() : {};

  event.waitUntil(
    self.registration.showNotification(message.title || "", {
      body: message.body,
      icon: "/images/admin/icon-192.png",
      tag: message.tag,
      renotify: Boolean(message.tag),
      requireInteraction: true,
      data: { url: message.url || "/staff" },
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = new URL(event.notification.data?.url || "/staff", self.location.origin).href;

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((windows) => {
      const open = windows.find((client) => client.url.startsWith(self.location.origin + "/staff"));
      if (!open) return self.clients.openWindow(url);
      if (!open.navigate) return open.focus();
      return open.navigate(url).then((client) => (client || open).focus());
    }),
  );
});
