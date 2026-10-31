const INTERVAL_MS = 20_000;
const MIN_METERS = 30;
const EARTH_METERS = 6_371_000;

function distance([lat1, lng1], [lat2, lng2]) {
  const rad = (deg) => (deg * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_METERS * Math.asin(Math.sqrt(a));
}

export const CourierLocation = {
  mounted() {
    if (!navigator.geolocation) return this.status("unsupported");
    this.sent = null;
    this.sentAt = 0;
    this.watch = navigator.geolocation.watchPosition(
      (position) => this.update(position),
      (error) => this.status(error.code === error.PERMISSION_DENIED ? "denied" : "unavailable"),
      { enableHighAccuracy: true, maximumAge: 10_000 },
    );
  },
  reconnected() {
    this.sent = null;
  },
  destroyed() {
    if (this.watch != null) navigator.geolocation.clearWatch(this.watch);
  },
  update({ coords }) {
    const point = [coords.latitude, coords.longitude];
    const now = Date.now();
    if (this.sent && (now - this.sentAt < INTERVAL_MS || distance(this.sent, point) < MIN_METERS)) return;
    this.sent = point;
    this.sentAt = now;
    this.status("on");
    this.pushEvent("location", { lat: point[0], lng: point[1] });
  },
  status(state) {
    this.el.dataset.state = state;
  },
};
