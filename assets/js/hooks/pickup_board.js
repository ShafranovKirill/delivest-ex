import { kiosk } from "./kiosk";

const PAGE_MS = 8000;
const HOLD_MS = 15000;

const kioskHook = kiosk({
  start: "[data-board-start]",
  greeting: [784],
  sounds: { "board:ready": [784, 988, 1319] },
});

export const PickupBoard = {
  ...kioskHook,

  mounted() {
    kioskHook.mounted.call(this);

    this.alive = true;
    this.tickTimer = null;
    this.holdTimer = null;
    this.holdUntil = 0;
    this.measureFrame = null;

    this.columns = ["preparing", "ready"].map((key) => {
      const section = this.el.querySelector(`#board-${key}`);
      const grid = section?.querySelector("[data-board-grid]") || null;

      return {
        key,
        section,
        grid,
        items: [],
        page: 0,
        capacity: 1,
        pages: 1,
        compact: false,
        lastPage: 0,
        lastCapacity: 0,
      };
    });

    this.onBoardResize = () => this.scheduleMeasure();
    this.onBoardFullscreen = () => this.scheduleMeasure();
    this.onBoardVisibility = () => {
      if (document.visibilityState === "visible") this.scheduleMeasure();
    };

    if (typeof ResizeObserver !== "undefined") {
      this.resizeObserver = new ResizeObserver(() => this.scheduleMeasure());
      this.columns.forEach((column) => {
        if (column.grid) this.resizeObserver.observe(column.grid);
      });
    }

    window.addEventListener("resize", this.onBoardResize);
    document.addEventListener("fullscreenchange", this.onBoardFullscreen);
    document.addEventListener("visibilitychange", this.onBoardVisibility);
    document.fonts?.addEventListener?.("loadingdone", this.onBoardResize);
    document.fonts?.ready?.then(() => {
      if (this.alive) this.scheduleMeasure();
    });

    this.handleEvent("board:ready", (payload) => this.prioritize(payload));

    this.measure();
    this.startTicking();
  },

  updated() {
    this.scheduleMeasure();
  },

  destroyed() {
    kioskHook.destroyed.call(this);

    this.alive = false;
    clearInterval(this.tickTimer);
    clearTimeout(this.holdTimer);
    if (this.measureFrame) cancelAnimationFrame(this.measureFrame);
    this.resizeObserver?.disconnect();
    window.removeEventListener("resize", this.onBoardResize);
    document.removeEventListener("fullscreenchange", this.onBoardFullscreen);
    document.removeEventListener("visibilitychange", this.onBoardVisibility);
    document.fonts?.removeEventListener?.("loadingdone", this.onBoardResize);
  },

  startTicking() {
    if (this.tickTimer) return;
    this.tickTimer = setInterval(() => this.tick(), PAGE_MS);
  },

  restartTicking() {
    clearInterval(this.tickTimer);
    this.tickTimer = null;
    this.startTicking();
  },

  tick() {
    if (document.hidden || Date.now() < this.holdUntil) return;
    this.advance();
  },

  advance() {
    let changed = false;

    this.columns.forEach((column) => {
      if (column.pages <= 1) return;

      column.page = (column.page + 1) % column.pages;
      changed = true;
    });

    if (changed) this.apply(true);
  },

  scheduleMeasure() {
    if (!this.alive || this.measureFrame) return;

    this.measureFrame = requestAnimationFrame(() => {
      this.measureFrame = null;
      if (this.alive) this.measure();
    });
  },

  measure() {
    if (!this.alive) return;

    this.columns.forEach((column) => {
      if (!column.grid) return;

      const items = Array.from(column.grid.querySelectorAll("[data-board-order]"));
      const firstVisible = items.find((item) => !item.hidden) || null;
      column.items = items;

      if (column.compact) {
        column.section?.classList.remove("board-compact");
        column.compact = false;
      }

      let capacity = this.capacity(column, items);

      if (items.length > 0 && capacity < 1) {
        column.section?.classList.add("board-compact");
        column.compact = true;
        capacity = this.capacity(column, items);
        if (capacity < 1) capacity = 1;
      }

      if (items.length === 0) capacity = 1;

      column.capacity = Math.max(1, capacity);
      column.pages = Math.max(1, Math.ceil(items.length / column.capacity));

      let page = column.page;

      if (firstVisible) {
        const index = items.indexOf(firstVisible);
        if (index >= 0) page = Math.floor(index / column.capacity);
      }

      column.page = Math.min(Math.max(page, 0), column.pages - 1);
    });

    this.apply();
  },

  capacity(column, items) {
    const grid = column.grid;

    if (!grid || items.length === 0) return 1;
    if (grid.clientHeight <= 0) return 0;

    const fits = (count) => {
      items.forEach((item, index) => {
        item.hidden = index >= count;
      });

      return grid.scrollHeight <= grid.clientHeight + 1;
    };

    if (!fits(1)) return 0;

    let low = 1;
    let high = items.length;
    let best = 1;

    while (low <= high) {
      const middle = Math.floor((low + high) / 2);

      if (fits(middle)) {
        best = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }

    return best;
  },

  apply(animate = false) {
    this.columns.forEach((column) => {
      const start = column.page * column.capacity;
      const end = start + column.capacity;

      column.items.forEach((item, index) => {
        item.hidden = index < start || index >= end;
      });

      if (animate && (column.page !== column.lastPage || column.capacity !== column.lastCapacity)) {
        this.fade(column.grid);
      }

      column.lastPage = column.page;
      column.lastCapacity = column.capacity;
    });
  },

  fade(grid) {
    if (!grid?.animate || window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) return;

    grid.animate([{ opacity: 0.55 }, { opacity: 1 }], {
      duration: 180,
      easing: "ease-out",
    });
  },

  prioritize(payload) {
    if (!this.alive) return;

    this.measure();

    const column = this.columns.find((candidate) => candidate.key === "ready");
    if (!column || column.pages <= 1) return;

    if (payload?.newest == null) return;

    const newest = String(payload.newest);

    const index = column.items.findIndex((item) => item.dataset.orderId === newest);
    if (index < 0) return;

    column.page = Math.floor(index / column.capacity);
    this.apply(true);

    const hold = Number(payload?.hold_ms) || HOLD_MS;
    this.holdUntil = Date.now() + hold;

    clearTimeout(this.holdTimer);
    this.holdTimer = setTimeout(() => {
      if (!this.alive) return;

      this.holdUntil = 0;
      this.advance();
      this.restartTicking();
    }, hold);
  },
};
