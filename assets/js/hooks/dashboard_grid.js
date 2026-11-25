import { GridStack } from "gridstack";

const parseLayout = (el) => {
  try { return JSON.parse(el.dataset.layout || "[]"); } catch { return []; }
};

const widthColumns = (width, editing) =>
  width < 640 ? 2 : width < (editing && window.innerWidth >= 1280 ? 680 : 1100) ? 6 : 12;
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
    this.manualHeights = new Map();
    this.autoShift = new Map();
    this.onDetailsToggle = (event) => {
      if (event.target instanceof HTMLDetailsElement) this.scheduleFit();
    };
    this.container.addEventListener("toggle", this.onDetailsToggle, true);
    this.minimumHeights = new Map([...this.container.children].map((el) =>
      [el.dataset.widgetId, Number(el.getAttribute("gs-min-h"))]));
    this.widthLimits = new Map([...this.container.children].map((el) =>
      [el.dataset.widgetId, {
        minW: Number(el.getAttribute("gs-min-w")), maxW: Number(el.getAttribute("gs-max-w")),
      }]));
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
      this.grid.on(name, (_event, el) => {
        this.gestureActive = false;
        if (name === "resizestop" && el) {
          const node = this.grid.engine.nodes.find((entry) => entry.el === el);
          if (node) this.manualHeights.set(node.id, node.h);
        }
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
    this.contentObserver = new ResizeObserver(() => this.scheduleFit());
    this.observeContent();
    this.lastWidth = this.container.clientWidth;
    this.silent = false;
    this.scheduleFit();
    this.readyTimer = window.setTimeout(() => this.showGrid(), 1800);
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
      this.manualHeights.clear();
    }
    this.editing = editing;
    this.defaultLayout = this.el.dataset.defaultLayout === "true";
    this.applyLayout();
    this.observeContent();
    this.scheduleFit();
  },

  destroyed() {
    this.resizeObserver?.disconnect();
    this.container.removeEventListener("toggle", this.onDetailsToggle, true);
    this.contentObserver?.disconnect();
    cancelAnimationFrame(this.fitFrame);
    clearTimeout(this.readyTimer);
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
        ? { id: item.id, x: node.x,
            y: Math.max(0, node.y - (this.autoShift.get(item.id) || 0)), w: node.w,
            h: this.manualHeights.get(item.id) ?? item.h, order }
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
        this.widthLimits.set(el.dataset.widgetId, {
          minW: Number(el.getAttribute("gs-min-w")),
          maxW: Number(el.getAttribute("gs-max-w")),
        });
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
    let halfRowHeight = 0;
    this.grid.batchUpdate();
    for (const { item, el } of this.orderedVisible()) {
      const h = mobileHeight(item, this.editing, el, this.extraNarrow);
      const isKpi = ["revenue", "orders", "avg_check", "in_work"].includes(item.id);
      if (isKpi) {
        this.grid.update(el, { x: halfRowHeight ? 1 : 0, y, w: 1, h, minW: 1, maxW: 2 });
        if (halfRowHeight) {
          y += Math.max(halfRowHeight, h);
          halfRowHeight = 0;
        } else halfRowHeight = h;
      } else {
        if (halfRowHeight) y += halfRowHeight;
        halfRowHeight = 0;
        this.grid.update(el, { x: 0, y, w: 2, h, minW: 2, maxW: 2 });
        y += h;
      }
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
    this.container.classList.toggle("dashboard-grid-mobile", columns === 2);
    for (const item of this.canonical) {
      const el = [...this.container.children].find((entry) => entry.dataset.widgetId === item.id);
      if (el) this.grid.update(el, {
        minH: this.minimumHeights.get(item.id),
        ...(columns === 2 ? { minW: 1, maxW: 2 } : this.widthLimits.get(item.id)),
      });
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
    } else if (columns === 2) {
      this.applyMobileOrder();
    } else {
      this.applyCompactOrder();
    }
    this.silent = false;
    this.scheduleFit();
  },

  observeContent() {
    this.contentObserver.disconnect();
    for (const card of this.container.querySelectorAll(".dashboard-widget-card")) {
      this.contentObserver.observe(card);
      for (const child of card.children) this.contentObserver.observe(child);
    }
  },

  scheduleFit() {
    if (this.fitting) return;
    cancelAnimationFrame(this.fitFrame);
    this.fitFrame = requestAnimationFrame(() => this.fitContent());
  },

  fitContent() {
    if (this.gestureActive) return;
    this.fitting = true;
    this.silent = true;
    // Start from the saved geometry on every pass so collapsed details can shrink again.
    if (this.columns === 2) this.applyMobileOrder();
    else if (this.columns === 6) this.applyCompactOrder();
    else {
      this.grid.batchUpdate();
      for (const { item, el } of this.orderedVisible()) {
        this.grid.update(el, { ...item, h: this.manualHeights.get(item.id) ?? item.h });
      }
      this.grid.batchUpdate(false);
      if (!this.editing && this.defaultLayout) this.applyDefaultView();
    }
    const baseY = new Map(this.grid.engine.nodes.map((node) => [node.id, node.y]));
    const cell = 72;
    this.grid.batchUpdate();
    for (const { item, el } of this.orderedVisible()) {
      const content = el.querySelector(":scope > .grid-stack-item-content");
      const card = content?.querySelector(".dashboard-widget-card");
      if (!card) continue;
      if (item.id === "latest_orders") continue;
      const oldContentHeight = content.style.height;
      const oldCardHeight = card.style.height;
      content.style.height = "max-content";
      card.style.height = "max-content";
      const contentTop = content.getBoundingClientRect().top;
      const expandedBottom = [...card.querySelectorAll("details[open]")]
        .reduce((bottom, details) => Math.max(bottom, details.getBoundingClientRect().bottom), 0);
      const intrinsic = Math.max(content.scrollHeight, expandedBottom - contentTop + 24);
      const needed = Math.ceil((intrinsic + 12) / cell);
      content.style.height = oldContentHeight;
      card.style.height = oldCardHeight;
      const node = this.grid.engine.nodes.find((entry) => entry.el === el);
      if (node && needed > node.h) this.grid.update(el, { h: needed, maxH: Math.max(needed, 100) });
    }
    this.grid.batchUpdate(false);
    this.autoShift = new Map(this.grid.engine.nodes.map((node) =>
      [node.id, node.y - (baseY.get(node.id) ?? node.y)]));
    this.silent = false;
    this.fitting = false;
    this.showGrid();
  },

  showGrid() {
    this.container.classList.add("dashboard-grid-ready");
    clearTimeout(this.readyTimer);
  },
};
