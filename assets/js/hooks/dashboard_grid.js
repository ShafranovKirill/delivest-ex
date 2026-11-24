import { GridStack } from "gridstack";

const parseLayout = (el) => {
  try { return JSON.parse(el.dataset.layout || "[]"); } catch { return []; }
};

const widthColumns = (width, editing) =>
  width < 640 ? 1 : width < (editing && window.innerWidth >= 1280 ? 680 : 1100) ? 6 : 12;
const byPosition = (a, b) => a.y - b.y || a.x - b.x || a.order - b.order;
const mobileHeight = (item, editing, el, extraNarrow) => {
  if (item.id === "attention") return editing || extraNarrow ? 3 : 2;
  if (item.id === "quick_actions") {
    const actions = el.querySelectorAll(".dashboard-action-link").length;
    return editing || extraNarrow || actions > 4 ? 3 : 2;
  }
  return ({ revenue: 3, orders: 3, avg_check: 3, in_work: 3 })[item.id] || item.h;
};

export const DashboardGrid = {
  mounted() {
    this.container = document.getElementById("dashboard-grid");
    this.editing = this.el.dataset.editing === "true";
    this.defaultLayout = this.el.dataset.defaultLayout === "true";
    this.serverLayout = this.el.dataset.layout;
    this.canonical = parseLayout(this.el);
    this.minimumHeights = new Map([...this.container.children].map((el) =>
      [el.dataset.widgetId, Number(el.getAttribute("gs-min-h"))]));
    this.columns = widthColumns(this.container.clientWidth, this.editing);
    this.extraNarrow = this.container.clientWidth < 340;
    this.silent = true;
    this.grid = GridStack.init({
      column: 12,
      cellHeight: 72,
      margin: 12,
      float: true,
      alwaysShowResizeHandle: true,
      animate: !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
      draggable: { handle: ".dashboard-drag-handle", scroll: true },
      resizable: { handles: "se" },
      disableDrag: !this.editing || this.columns !== 12,
      disableResize: !this.editing || this.columns !== 12,
    }, this.container);
    this.applyLayout();
    this.grid.on("change", () => {
      if (this.silent || this.gestureActive) return;
      this.commitGeometry();
    });
    for (const name of ["dragstart", "resizestart"]) {
      this.grid.on(name, () => { this.gestureActive = true; });
    }
    for (const name of ["dragstop", "resizestop"]) {
      this.grid.on(name, () => {
        this.gestureActive = false;
        this.commitGeometry();
        if (this.patchDuringGesture) {
          this.patchDuringGesture = false;
          this.updated();
        }
      });
    }
    this.resizeObserver = new ResizeObserver(() => {
      if (this.container.clientWidth !== this.lastWidth) this.resize();
    });
    this.resizeObserver.observe(this.container);
    this.lastWidth = this.container.clientWidth;
    this.silent = false;
  },

  updated() {
    if (this.gestureActive) {
      this.patchDuringGesture = true;
      return;
    }
    const editing = this.el.dataset.editing === "true";
    const next = this.el.dataset.layout;
    if (next !== this.serverLayout) {
      this.serverLayout = next;
      this.canonical = parseLayout(this.el);
    }
    this.editing = editing;
    this.defaultLayout = this.el.dataset.defaultLayout === "true";
    this.applyLayout();
  },

  destroyed() {
    this.resizeObserver?.disconnect();
    this.grid?.destroy(false);
  },

  commitGeometry() {
    if (!this.editing || this.columns !== 12) return;
    const next = this.readDesktop();
    if (JSON.stringify(next) === JSON.stringify(this.canonical)) return;
    this.canonical = next;
    this.pushEvent("dashboard_layout_change", { widgets: next });
  },

  // GridStack knows only cards mounted in this scope. Keep inaccessible cards intact.
  readDesktop() {
    const changed = this.canonical.map((item, order) => {
      const node = this.grid.engine.nodes.find((entry) => entry.id === item.id);
      return node
        ? { id: item.id, x: node.x, y: node.y, w: node.w, h: node.h, order }
        : { ...item, order };
    });
    const visible = changed.filter((item) => this.grid.engine.nodes.some((node) => node.id === item.id))
      .sort(byPosition);
    let index = 0;
    return changed.map((item) => {
      const value = this.grid.engine.nodes.some((node) => node.id === item.id) ? visible[index++] : item;
      const { order, ...layout } = value;
      return layout;
    });
  },

  applyLayout() {
    this.silent = true;
    const present = [...this.container.querySelectorAll(":scope > .grid-stack-item")];
    const known = new Set(this.grid.engine.nodes.map((node) => node.el));
    this.grid.batchUpdate();
    for (const node of [...this.grid.engine.nodes]) {
      if (!present.includes(node.el)) this.grid.removeWidget(node.el, false, false);
    }
    for (const el of present) {
      if (!this.minimumHeights.has(el.dataset.widgetId)) {
        this.minimumHeights.set(el.dataset.widgetId, Number(el.getAttribute("gs-min-h")));
      }
      if (!known.has(el)) this.grid.makeWidget(el);
    }
    if (this.grid.opts.column === 12) {
      for (const item of this.canonical) {
        const el = present.find((entry) => entry.dataset.widgetId === item.id);
        if (el) this.grid.update(el, { ...item, minH: this.minimumHeights.get(item.id) });
      }
    }
    this.grid.batchUpdate(false);
    this.resize(true);
    this.silent = false;
  },

  orderedVisible() {
    const elements = new Map([...this.container.children].map((el) => [el.dataset.widgetId, el]));
    return this.canonical
      .filter((item) => elements.has(item.id))
      .map((item) => ({ item, el: elements.get(item.id) }));
  },

  applyCompactOrder() {
    let y = 0;
    let halfRowHeight = 0;
    this.grid.batchUpdate();
    for (const { item, el } of this.orderedVisible()) {
      const isKpi = ["revenue", "orders", "avg_check", "in_work"].includes(item.id);
      const w = isKpi ? 3 : 6;
      const h = item.id === "quick_actions" && el.querySelectorAll(".dashboard-action-link").length > 4
        ? Math.max(3, item.h) : item.h;
      if (isKpi) {
        const x = halfRowHeight ? 3 : 0;
        this.grid.update(el, { x, y, w, h });
        if (halfRowHeight) {
          y += Math.max(halfRowHeight, h);
          halfRowHeight = 0;
        } else {
          halfRowHeight = h;
        }
      } else {
        if (halfRowHeight) y += halfRowHeight;
        halfRowHeight = 0;
        this.grid.update(el, { x: 0, y, w, h });
        y += h;
      }
    }
    this.grid.batchUpdate(false);
  },

  applyMobileOrder() {
    let y = 0;
    this.grid.batchUpdate();
    for (const { item, el } of this.orderedVisible()) {
      const h = mobileHeight(item, this.editing, el, this.extraNarrow);
      this.grid.update(el, { x: 0, y, w: 1, h });
      y += h;
    }
    this.grid.batchUpdate(false);
  },

  applyDefaultView() {
    const visible = new Map([...this.container.children].map((el) => [el.dataset.widgetId, el]));
    const groups = this.canonical.filter((item) => visible.has(item.id)).reduce((map, item) => {
      if (!map.has(item.y)) map.set(item.y, []);
      map.get(item.y).push(item);
      return map;
    }, new Map());
    const hasQuickActions = visible.has("quick_actions");
    let y = 0;
    this.grid.batchUpdate();
    for (const [, items] of [...groups].sort((a, b) => a[0] - b[0])) {
      let rowHeight = 0;
      for (const item of items) {
        const el = visible.get(item.id);
        const empty = el.dataset.dashboardEmpty === "true";
        const h = empty && item.id === "attention" ? 1
          : empty && ["hourly", "latest_orders", "top_products"].includes(item.id) ? 2
            : item.h;
        const w = item.id === "attention" && !hasQuickActions ? 12 : item.w;
        this.grid.update(el, { x: item.x, y, w, h, minH: Math.min(h, this.minimumHeights.get(item.id)) });
        rowHeight = Math.max(rowHeight, h);
      }
      y += rowHeight;
    }
    this.grid.batchUpdate(false);
  },

  resize(force = false) {
    const width = this.container.clientWidth;
    const columns = widthColumns(width, this.editing);
    const extraNarrow = width < 340;
    if (!force && columns === this.columns && this.grid.opts.column === columns && extraNarrow === this.extraNarrow) return;
    this.silent = true;
    this.lastWidth = width;
    this.columns = columns;
    this.extraNarrow = extraNarrow;
    this.container.classList.toggle("dashboard-grid-compact", columns < 12);
    this.container.classList.toggle("dashboard-grid-mobile", columns === 1);
    for (const item of this.canonical) {
      const el = [...this.container.children].find((entry) => entry.dataset.widgetId === item.id);
      if (el) this.grid.update(el, { minH: this.minimumHeights.get(item.id) });
    }
    if (this.grid.opts.column !== columns) this.grid.column(columns, "compact");
    this.grid.enableMove(this.editing && columns === 12);
    this.grid.enableResize(this.editing && columns === 12);
    if (columns === 12) {
      this.grid.batchUpdate();
      for (const item of this.canonical) {
        const el = [...this.container.children].find((entry) => entry.dataset.widgetId === item.id);
        if (el) this.grid.update(el, { ...item, minH: this.minimumHeights.get(item.id) });
      }
      this.grid.batchUpdate(false);
      if (!this.editing && this.defaultLayout) this.applyDefaultView();
    } else if (columns === 1) {
      this.applyMobileOrder();
    } else {
      this.applyCompactOrder();
    }
    this.silent = false;
  },
};
