import maplibregl from "maplibre-gl";

const STYLE_URL = "https://tiles.openfreemap.org/styles/liberty";
const BLANK_IMAGE = { width: 1, height: 1, data: new Uint8Array(4) };

function point(el, prefix) {
  const lat = parseFloat(el.dataset[`${prefix}Lat`]);
  const lng = parseFloat(el.dataset[`${prefix}Lng`]);
  return Number.isFinite(lat) && Number.isFinite(lng) ? [lng, lat] : null;
}

function label(name) {
  const el = document.createElement("div");
  el.className = "rounded-full bg-success px-2 py-0.5 text-xs font-bold text-success-content shadow";
  el.textContent = name;
  return el;
}

export const CouriersMap = {
  mounted() {
    this.only = this.el.dataset.courierId || null;
    this.markers = new Map();
    this.fitted = false;
    const branch = point(this.el, "from");
    const target = point(this.el, "to");
    this.fixed = [branch, target].filter(Boolean);

    this.map = new maplibregl.Map({
      container: this.el,
      style: STYLE_URL,
      center: target || branch || [37.62, 55.75],
      zoom: 13,
      attributionControl: false,
    });

    this.map.on("styleimagemissing", ({ id }) => this.map.addImage(id, BLANK_IMAGE));
    if (branch) new maplibregl.Marker({ color: "#6b7280" }).setLngLat(branch).addTo(this.map);
    if (target) new maplibregl.Marker({ color: "#2563eb" }).setLngLat(target).addTo(this.map);

    this.place(JSON.parse(this.el.dataset.positions || "[]"));
    this.handleEvent("courier_positions", ({ positions }) => this.place(positions));
  },

  place(positions) {
    const shown = positions.filter((p) => !this.only || p.id === this.only);
    const ids = new Set(shown.map((p) => p.id));

    for (const [id, marker] of this.markers) {
      if (!ids.has(id)) {
        marker.remove();
        this.markers.delete(id);
      }
    }

    for (const p of shown) {
      const lngLat = [p.lng, p.lat];
      const marker = this.markers.get(p.id) || new maplibregl.Marker({ element: label(p.name) }).addTo(this.map);
      marker.setLngLat(lngLat);
      this.markers.set(p.id, marker);
    }

    if (!this.fitted) this.fit(shown.map((p) => [p.lng, p.lat]));
  },

  fit(points) {
    const all = [...this.fixed, ...points];
    if (all.length < 2) return;
    const bounds = all.reduce((b, p) => b.extend(p), new maplibregl.LngLatBounds(all[0], all[0]));
    this.map.fitBounds(bounds, { padding: 40, maxZoom: 16, duration: 0 });
    this.fitted = points.length > 0;
  },

  destroyed() {
    this.map?.remove();
  },
};
