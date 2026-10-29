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
    BulkPaste,
    LocationMap,
    ZoneMap,
    Alarm,
    KitchenScreen,
    PickupBoard,
    CourierMap,
    CourierLocation,
    CouriersMap,
  },
});

const root = document.documentElement;

if ("serviceWorker" in navigator && location.pathname.startsWith("/staff")) {
  navigator.serviceWorker.register("/staff/sw.js", { scope: "/staff/" }).catch(() => {});
}

window.addEventListener("sidebar:toggle-collapse", () => {
  const collapsed = root.toggleAttribute("data-sidebar-collapsed");
  localStorage.setItem("sidebar_collapsed", collapsed);
});

window.addEventListener("sidebar:toggle-open", () =>
  root.toggleAttribute("data-sidebar-open"),
);

window.addEventListener("phx:page-loading-start", (event) => {
  if (["redirect", "patch"].includes(event.detail?.kind))
    root.removeAttribute("data-sidebar-open");
});

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
