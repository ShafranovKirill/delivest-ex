import maplibregl from "maplibre-gl";

const STYLE_URL = "https://tiles.openfreemap.org/styles/liberty";
const FALLBACK = [37.6176, 55.7558];

const BLANK_IMAGE = { width: 1, height: 1, data: new Uint8Array(4) };

const HOUSE_NUMBERS = {
  id: "house-numbers",
  type: "symbol",
  source: "openmaptiles",
  "source-layer": "housenumber",
  minzoom: 16,
  layout: {
    "text-field": ["get", "housenumber"],
    "text-font": ["Noto Sans Regular"],
    "text-size": 12,
  },
  paint: { "text-color": "#4b5563", "text-halo-color": "#ffffff", "text-halo-width": 1.5 },
};

function initialPoint(el) {
  const lat = parseFloat(el.dataset.lat);
  const lng = parseFloat(el.dataset.lng);
  return Number.isFinite(lat) && Number.isFinite(lng) ? [lng, lat] : null;
}

export const LocationMap = {
  mounted() {
    const point = initialPoint(this.el);

    this.map = new maplibregl.Map({
      container: this.el,
      style: STYLE_URL,
      center: point || FALLBACK,
      zoom: point ? 17 : 10,
    });

    this.map.on("load", () => this.map.addLayer(HOUSE_NUMBERS));
    this.map.on("styleimagemissing", ({ id }) => this.map.addImage(id, BLANK_IMAGE));

    this.marker = new maplibregl.Marker({ draggable: true })
      .setLngLat(point || FALLBACK)
      .addTo(this.map);

    this.marker.on("dragend", () => this.pick(this.marker.getLngLat()));
    this.map.on("click", (event) => {
      this.marker.setLngLat(event.lngLat);
      this.pick(event.lngLat);
    });

    this.handleEvent("location:center", ({ lat, lng }) => {
      this.marker.setLngLat([lng, lat]);
      this.map.flyTo({ center: [lng, lat], zoom: 17 });
    });
  },

  pick({ lat, lng }) {
    this.pushEventTo(this.el, "location_moved", { lat, lng });
  },

  destroyed() {
    this.map?.remove();
  },
};
