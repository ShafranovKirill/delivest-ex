import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/delivest";
import topbar from "../vendor/topbar";
import Sortable from "sortablejs";
import { LocationMap } from "./hooks/location_map";
import { ZoneMap } from "./hooks/zone_map";
import { Alarm, ring } from "./hooks/alarm";
import { KitchenScreen } from "./hooks/kitchen_screen";
import { PickupBoard } from "./hooks/pickup_board";
import { CourierMap } from "./hooks/courier_map";
import { CourierLocation } from "./hooks/courier_location";
import { CouriersMap } from "./hooks/couriers_map";
import { CopyLink } from "./hooks/copy_link";
import { HeaderScroll } from "./hooks/header_scroll";
import { FoundationDialog } from "./hooks/foundation_dialog";
import { FoundationColumns } from "./hooks/foundation_columns";
import { FoundationDirty } from "./hooks/foundation_dirty";
import { StaffDirtyGuard } from "./hooks/staff_dirty_guard";
import { ActiveSectionNav } from "./hooks/active_section_nav";

let Uploaders = {};

Uploaders.S3 = function (entries, onViewError) {
  entries.forEach((entry) => {
    let { url } = entry.meta;
    let xhr = new XMLHttpRequest();

    onViewError(() => xhr.abort());

    xhr.open("PUT", url, true);

    xhr.onload = () => {
      if (xhr.status === 200) {
        entry.progress(100);
      } else {
        entry.error();
      }
    };

    xhr.onerror = () => {
      entry.error();
    };

    xhr.upload.addEventListener("progress", (event) => {
      if (event.lengthComputable) {
        let percent = Math.round((event.loaded / event.total) * 100);
        if (percent < 100) {
          entry.progress(percent);
        }
      }
    });

    xhr.send(entry.file);
  });
};

const ThemeToggle = {
  mounted() {
    this.el.checked = document.documentElement.getAttribute("data-theme") === "dark";

    this.el.addEventListener("change", (e) => {
      const theme = e.target.checked ? "dark" : "light";
      document.documentElement.setAttribute("data-theme", theme);
      document.documentElement.setAttribute("data-theme-source", "user");
      localStorage.setItem("phx:theme", theme);
    });
  },

  updated() {
    this.el.checked = document.documentElement.getAttribute("data-theme") === "dark";
  },
};

export const SortableCategories = {
  mounted() {
    let hook = this;
    let listEl = this.el;

    new Sortable(listEl, {
      animation: 150,
      handle: ".drag-handle",
      ghostClass: "bg-base-200",
      onEnd(evt) {
        let draggedId = evt.item.dataset.id;

        let prevNode = evt.item.previousElementSibling;
        let nextNode = evt.item.nextElementSibling;

        let aboveOrder = prevNode ? parseFloat(prevNode.dataset.order) : null;
        let belowOrder = nextNode ? parseFloat(nextNode.dataset.order) : null;

        hook.pushEvent("reorder_category", {
          id: draggedId,
          above_order: aboveOrder,
          below_order: belowOrder,
        });
      },
    });
  },
};

export const SortableStocks = {
  mounted() {
    let hook = this;
    let listEl = this.el;

    new Sortable(listEl, {
      animation: 150,
      handle: ".drag-handle",
      ghostClass: "bg-base-200",
      onEnd(evt) {
        let draggedId = evt.item.dataset.id;

        let prevNode = evt.item.previousElementSibling;
        let nextNode = evt.item.nextElementSibling;

        let aboveOrder = prevNode ? parseFloat(prevNode.dataset.order) : null;
        let belowOrder = nextNode ? parseFloat(nextNode.dataset.order) : null;

        hook.pushEvent("reorder_stock", {
          id: draggedId,
          above_order: aboveOrder,
          below_order: belowOrder,
        });
      },
    });
  },
};

export const SortableProducts = {
  mounted() {
    let hook = this;
    let listEl = this.el;

    new Sortable(listEl, {
      animation: 150,
      handle: ".drag-handle",
      ghostClass: "bg-base-200",
      onEnd(evt) {
        let draggedId = evt.item.dataset.id;

        let prevNode = evt.item.previousElementSibling;
        let nextNode = evt.item.nextElementSibling;

        let aboveOrder = prevNode ? parseFloat(prevNode.dataset.order) : null;
        let belowOrder = nextNode ? parseFloat(nextNode.dataset.order) : null;

        hook.pushEvent("reorder_product", {
          id: draggedId,
          above_order: aboveOrder,
          below_order: belowOrder,
        });
      },
    });
  },
};

export const SortableZones = {
  mounted() {
    const hook = this;
    new Sortable(this.el, {
      animation: 150,
      handle: ".drag-handle",
      ghostClass: "bg-base-200",
      onEnd() {
        hook.pushEvent("reorder_zones", {
          ids: [...hook.el.querySelectorAll("[data-id]")].map((item) => item.dataset.id),
        });
      },
    });
  },
};

const BulkPaste = {
  mounted() {
    this.el.addEventListener("paste", (event) => {
      const cell = event.target.closest("[data-row][data-column]");
      const text = event.clipboardData?.getData("text/plain") || "";
      if (!cell || !/[\t\n]/.test(text.trim())) return;

      event.preventDefault();
      this.pushEvent("paste", {
        row: cell.dataset.row,
        column: cell.dataset.column,
        text,
      });
    });
  },
};

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  uploaders: Uploaders,
  hooks: {
    ...colocatedHooks,
    ThemeToggle,
    SortableCategories,
    SortableStocks,
    SortableProducts,
    SortableZones,
    BulkPaste,
    LocationMap,
    ZoneMap,
    Alarm,
    KitchenScreen,
    PickupBoard,
    CourierMap,
    CourierLocation,
    CouriersMap,
    CopyLink,
    HeaderScroll,
    ActiveSectionNav,
    FoundationDialog,
    FoundationColumns,
    FoundationDirty,
    StaffDirtyGuard,
  },
});

const root = document.documentElement;

if ("serviceWorker" in navigator && location.pathname.startsWith("/staff")) {
  navigator.serviceWorker.register("/staff/sw.js", { scope: "/staff/" }).catch(() => {});
}

const staffDesktop = () => window.matchMedia("(min-width: 1024px)").matches;

function syncSidebarToggle() {
  const expanded = staffDesktop()
    ? !root.hasAttribute("data-sidebar-collapsed")
    : root.hasAttribute("data-sidebar-open");
  document.querySelectorAll("[data-sidebar-toggle]").forEach((button) => {
    const label = expanded ? button.dataset.collapseLabel : button.dataset.expandLabel;
    button.setAttribute("aria-expanded", String(expanded));
    button.setAttribute("aria-label", label);
    button.title = label;
  });
}

function focusVisibleSidebarToggle(active) {
  if (!active?.closest("#main-sidebar, #staff-header-sidebar-controls")) return;
  if (active.getClientRects().length) return;
  const button = [...document.querySelectorAll("[data-sidebar-toggle]")]
    .find((toggle) => toggle.getClientRects().length);
  button?.focus({ preventScroll: true });
}

const sidebarFocusKey = "staff:sidebar-return-focus";
let pendingSidebarFocus = sessionStorage.getItem(sidebarFocusKey) === "1";
function restoreSidebarFocus() {
  if (!pendingSidebarFocus) return;
  requestAnimationFrame(() => {
    const button = document.getElementById("header-sidebar-toggle");
    if (button?.getClientRects().length) button.focus({ preventScroll: true });
    pendingSidebarFocus = false;
    sessionStorage.removeItem(sidebarFocusKey);
  });
}

window.addEventListener("sidebar:toggle", () => {
  const focused = document.activeElement;
  if (staffDesktop()) {
    const collapsed = root.toggleAttribute("data-sidebar-collapsed");
    localStorage.setItem("sidebar_collapsed", collapsed);
  } else {
    root.toggleAttribute("data-sidebar-open");
  }
  syncSidebarToggle();
  focusVisibleSidebarToggle(focused);
});

window.addEventListener("sidebar:toggle-collapse", () => {
  const focused = document.activeElement;
  const collapsed = root.toggleAttribute("data-sidebar-collapsed");
  localStorage.setItem("sidebar_collapsed", collapsed);
  syncSidebarToggle();
  focusVisibleSidebarToggle(focused);
});

window.addEventListener("sidebar:toggle-open", () => {
  const focused = document.activeElement;
  root.toggleAttribute("data-sidebar-open");
  syncSidebarToggle();
  focusVisibleSidebarToggle(focused);
  if (!root.hasAttribute("data-sidebar-open"))
    document.getElementById("header-sidebar-toggle")?.focus({ preventScroll: true });
});

function setProfileOpen(open) {
  const button = document.querySelector("[data-profile-trigger]");
  const menu = document.querySelector("[data-profile-menu]");
  if (!button || !menu) return;
  button.setAttribute("aria-expanded", String(open));
  menu.hidden = !open;
  if (open) requestAnimationFrame(() => menu.querySelector("a, button")?.focus());
}

document.addEventListener("click", (event) => {
  if (event.target.closest("[data-profile-trigger]")) {
    const button = document.querySelector("[data-profile-trigger]");
    setProfileOpen(button?.getAttribute("aria-expanded") !== "true");
  } else if (!event.target.closest("#staff-profile")) {
    setProfileOpen(false);
  }
  if (!staffDesktop() && root.hasAttribute("data-sidebar-open") &&
      event.target.closest("#main-sidebar a")) {
    pendingSidebarFocus = true;
    sessionStorage.setItem(sidebarFocusKey, "1");
    const focused = document.activeElement;
    root.removeAttribute("data-sidebar-open");
    syncSidebarToggle();
    focusVisibleSidebarToggle(focused);
    document.getElementById("header-sidebar-toggle")?.focus({ preventScroll: true });
  }
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    const button = document.querySelector("[data-profile-trigger]");
    if (button?.getAttribute("aria-expanded") === "true") {
      setProfileOpen(false);
      button.focus();
      return;
    }
    if (event.target.closest("#command-palette") ||
        document.querySelector("#command-palette")?.getClientRects().length) return;
    if (root.hasAttribute("data-sidebar-open")) {
      const focused = document.activeElement;
      root.removeAttribute("data-sidebar-open");
      syncSidebarToggle();
      focusVisibleSidebarToggle(focused);
      document.getElementById("header-sidebar-toggle")?.focus({ preventScroll: true });
    }
  }
});

document.addEventListener("focusin", (event) => {
  if (!event.target.closest("#staff-profile")) setProfileOpen(false);
});

window.addEventListener("resize", syncSidebarToggle);
window.addEventListener("phx:page-loading-start", (event) => {
  if (["redirect", "patch"].includes(event.detail?.kind)) {
    root.removeAttribute("data-sidebar-open");
    setProfileOpen(false);
    syncSidebarToggle();
  }
});
window.addEventListener("phx:page-loading-stop", () => {
  syncSidebarToggle();
  restoreSidebarFocus();
});
if (document.readyState === "loading")
  document.addEventListener("DOMContentLoaded", () => {
    syncSidebarToggle();
    restoreSidebarFocus();
  });
else {
  syncSidebarToggle();
  restoreSidebarFocus();
}

topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());
window.addEventListener("phx:kitchen:ready", () => ring([660, 880, 1320]));
window.addEventListener("phx:force_staff_logout", (e) => {
  let csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");
  fetch("/staff/auth/log_out", {
    method: "DELETE",
    headers: {
      "X-CSRF-Token": csrfToken,
      "Content-Type": "application/json",
    },
  }).then(() => {
    window.location.href = "/staff/auth/login";
  });
});
liveSocket.connect();

window.liveSocket = liveSocket;

if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      reloader.enableServerLogs();

      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (_e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}
