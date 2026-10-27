import maplibregl from "maplibre-gl";
import { TerraDraw, TerraDrawPolygonMode, TerraDrawSelectMode } from "terra-draw";
import { TerraDrawMapLibreGLAdapter } from "terra-draw-maplibre-gl-adapter";

const STYLE_URL = "https://tiles.openfreemap.org/styles/liberty";
const FALLBACK = [37.6176, 55.7558];
const BLANK_IMAGE = { width: 1, height: 1, data: new Uint8Array(4) };
const DRAFT_COLOR = "#111827";

const color = (feature) => feature.properties.color || DRAFT_COLOR;
const opacity = (feature) => (feature.properties.enabled === false ? 0.08 : 0.25);

function center(el) {
  const lat = parseFloat(el.dataset.lat);
  const lng = parseFloat(el.dataset.lng);
  return Number.isFinite(lat) && Number.isFinite(lng) ? [lng, lat] : null;
}

function feature(zone) {
  return {
    id: zone.id,
    type: "Feature",
    geometry: zone.polygon,
    properties: { mode: "polygon", color: zone.color, enabled: zone.enabled },
  };
}

export const ZoneMap = {
  mounted() {
    const point = center(this.el);
    this.editable = this.el.dataset.editable === "true";
    this.zones = JSON.parse(this.el.dataset.zones || "[]");
    this.selected = this.el.dataset.selected || null;

    this.map = new maplibregl.Map({
      container: this.el,
      style: STYLE_URL,
      center: point || FALLBACK,
      zoom: point ? 12 : 10,
    });

    this.map.on("styleimagemissing", ({ id }) => this.map.addImage(id, BLANK_IMAGE));

    if (point) new maplibregl.Marker({ color: "#dc2626" }).setLngLat(point).addTo(this.map);

    this.map.on("load", () => this.setupDraw());

    this.handleEvent("zones:reset", ({ zones, selected }) => {
      this.zones = zones;
      this.selected = selected;
      this.render();
    });

    this.handleEvent("zones:draw", () => this.draw?.setMode("polygon"));
  },

  setupDraw() {
    const coordinates = this.editable
      ? { midpoints: true, draggable: true, deletable: true }
      : undefined;

    this.draw = new TerraDraw({
      adapter: new TerraDrawMapLibreGLAdapter({ map: this.map }),
      idStrategy: {
        isValidId: (id) => typeof id === "string" && id.length > 0,
        getId: () => crypto.randomUUID(),
      },
      modes: [
        new TerraDrawSelectMode({
          allowManualDeselection: true,
          flags: { polygon: { feature: { draggable: false, coordinates } } },
          styles: {
            selectedPolygonColor: color,
            selectedPolygonOutlineColor: color,
            selectedPolygonFillOpacity: 0.35,
            selectedPolygonOutlineWidth: 3,
          },
        }),
        new TerraDrawPolygonMode({
          styles: {
            fillColor: color,
            outlineColor: color,
            fillOpacity: opacity,
            outlineWidth: 2,
          },
        }),
      ],
    });

    this.draw.start();
    this.draw.setMode("select");

    this.draw.on("finish", (id, context) => {
      const snapshot = this.draw.getSnapshotFeature(id);
      if (!snapshot) return;

      if (context.action === "draw") {
        this.draw.removeFeatures([id]);
        this.draw.setMode("select");
        this.pushEvent("zone_drawn", { polygon: snapshot.geometry });
      } else if (this.editable) {
        this.pushEvent("zone_shape", { id, polygon: snapshot.geometry });
      }
    });

    this.draw.on("select", (id) => {
      if (id !== this.selected) {
        this.selected = id;
        this.pushEvent("zone_selected", { id });
      }
    });

    this.render();
    this.fit();
  },

  fit() {
    const points = this.zones.flatMap((zone) => zone.polygon.coordinates[0]);
    if (points.length === 0) return;

    const bounds = points.reduce(
      (acc, point) => acc.extend(point),
      new maplibregl.LngLatBounds(points[0], points[0]),
    );

    this.map.fitBounds(bounds, { padding: 40, duration: 0, maxZoom: 15 });
  },

  render() {
    if (!this.draw) return;

    this.draw.setMode("select");
    this.draw.clear();
    this.draw.addFeatures(this.zones.map(feature));

    if (this.selected && this.zones.some((zone) => zone.id === this.selected)) {
      this.draw.selectFeature(this.selected);
    }
  },

  destroyed() {
    this.draw?.stop();
    this.map?.remove();
  },
};
