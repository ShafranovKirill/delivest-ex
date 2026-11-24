import { GridStack } from "gridstack";

const parseLayout = (el) => {
  try { return JSON.parse(el.dataset.layout || "[]"); } catch { return []; }
};

const widthColumns = (width) => width < 640 ? 1 : width < 1100 ? 6 : 12;
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
    this.canonical = parseLayout(this.el);
    this.visible = this.el.dataset.visible;
    this.columns = widthColumns(this.container.clientWidth);
    this.extraNarrow = this.container.clientWidth < 340;
    this.silent = true;
    this.grid = GridStack.init({
      column: 12,
      cellHeight: 72,
      margin: 12,
      float: false,
      animate: !window.matchMedia("(prefers-reduced-motion: reduce)").matches,
      draggable: { handle: ".dashboard-drag-handle", scroll: true },
      resizable: { handles: "se" },
      disableDrag: !this.editing || this.columns !== 12,
      disableResize: !this.editing || this.columns !== 12,
    }, this.container);
    this.applyLayout();
    this.grid.on("change", () => {
      if (this.silent || !this.editing || this.columns !== 12) return;
      this.canonical = this.readDesktop();
      this.pushEvent("dashboard_layout_change", { widgets: this.canonical });
    });
    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(this.container);
    this.silent = false;
  },

  updated() {
    const next = parseLayout(this.el);
    const visible = this.el.dataset.visible;
    const editing = this.el.dataset.editing === "true";
    this.editing = editing;
    this.grid.enableMove(editing && this.columns === 12);
    this.grid.enableResize(editing && this.columns === 12);
    this.canonical = next;
    this.visible = visible;
    this.applyLayout();
    this.resize();
  },

  destroyed() {
    this.resizeObserver?.disconnect();
    this.grid?.destroy(false);
  },

  readDesktop() {
    return this.canonical.map((item) => {
      const node = this.grid.engine.nodes.find((entry) => entry.id === item.id);
      return node ? { id: item.id, x: node.x, y: node.y, w: node.w, h: node.h } : item;
    });
  },

  applyLayout() {
    this.silent = true;
    const present = [...this.container.querySelectorAll(":scope > .grid-stack-item")];
    const known = new Set(this.grid.engine.nodes.map((node) => node.id));
    for (const el of present) {
      if (!known.has(el.dataset.widgetId)) this.grid.makeWidget(el);
    }
    for (const node of [...this.grid.engine.nodes]) {
      if (!present.includes(node.el)) this.grid.removeWidget(node.el, false, false);
    }
    if (this.grid.opts.column === 12) {
      for (const item of this.canonical) {
        const el = present.find((entry) => entry.dataset.widgetId === item.id);
        if (el) this.grid.update(el, item);
      }
    }
    this.resize();
    if (this.columns === 1) this.applyMobileOrder();
    if (this.columns === 6) this.applyCompactHeights();
    this.silent = false;
  },

  applyCompactHeights() {
    for (const item of this.canonical) {
      if (item.id !== "attention" && item.id !== "quick_actions") continue;
      const el = [...this.container.children].find((entry) => entry.dataset.widgetId === item.id);
      if (!el) continue;
      const manyActions = item.id === "quick_actions" && el.querySelectorAll(".dashboard-action-link").length > 4;
      this.grid.update(el, { h: this.editing || manyActions ? Math.max(3, item.h) : item.h });
    }
  },

  applyMobileOrder() {
    let y = 0;
    this.grid.batchUpdate();
    for (const item of this.canonical) {
      const el = [...this.container.children].find((entry) => entry.dataset.widgetId === item.id);
      if (!el) continue;
      const h = mobileHeight(item, this.editing, el, this.extraNarrow);
      this.grid.update(el, { x: 0, y, w: 1, h });
      y += h;
    }
    this.grid.batchUpdate(false);
  },

  resize() {
    const width = this.container.clientWidth;
    const columns = widthColumns(width);
    const extraNarrow = width < 340;
    if (columns === this.columns && this.grid.opts.column === columns) {
      if (columns === 1 && extraNarrow !== this.extraNarrow) {
        this.extraNarrow = extraNarrow;
        this.silent = true;
        this.applyMobileOrder();
        this.silent = false;
      }
      return;
    }
    this.silent = true;
    this.columns = columns;
    this.extraNarrow = extraNarrow;
    this.container.classList.toggle("dashboard-grid-compact", columns < 12);
    this.container.classList.toggle("dashboard-grid-mobile", columns === 1);
    this.grid.column(columns, "compact");
    this.grid.enableMove(this.editing && columns === 12);
    this.grid.enableResize(this.editing && columns === 12);
    if (columns === 12) {
      for (const item of this.canonical) {
        const el = this.container.querySelector(`[data-widget-id="${item.id}"]`);
        if (el) this.grid.update(el, item);
      }
    } else if (columns === 1) {
      this.applyMobileOrder();
    } else if (columns === 6) {
      this.applyCompactHeights();
    }
    this.silent = false;
  },
};
