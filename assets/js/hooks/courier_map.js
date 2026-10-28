import maplibregl from "maplibre-gl";

const STYLE_URL = "https://tiles.openfreemap.org/styles/liberty";
const BLANK_IMAGE = { width: 1, height: 1, data: new Uint8Array(4) };

function point(el, prefix) {
  const lat = parseFloat(el.dataset[`${prefix}Lat`]);
  const lng = parseFloat(el.dataset[`${prefix}Lng`]);
  return Number.isFinite(lat) && Number.isFinite(lng) ? [lng, lat] : null;
}

export const CourierMap = {
  mounted() {
    const from = point(this.el, "from");
    const to = point(this.el, "to");
    if (!to) return;

    this.map = new maplibregl.Map({
      container: this.el,
      style: STYLE_URL,
      center: to,
      zoom: 15,
      attributionControl: false,
    });

    this.map.on("styleimagemissing", ({ id }) => this.map.addImage(id, BLANK_IMAGE));

    new maplibregl.Marker({ color: "#2563eb" }).setLngLat(to).addTo(this.map);

    if (from) {
      new maplibregl.Marker({ color: "#6b7280" }).setLngLat(from).addTo(this.map);
      this.map.fitBounds(new maplibregl.LngLatBounds(from, from).extend(to), {
        padding: 40,
        maxZoom: 16,
        duration: 0,
      });
    }
  },

  destroyed() {
    this.map?.remove();
  },
};
