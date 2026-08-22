import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/delivest";
import topbar from "../vendor/topbar";
import Sortable from "sortablejs";

const ThemeToggle = {
  mounted() {
    const currentTheme =
      document.documentElement.getAttribute("data-theme") ||
      localStorage.getItem("theme") ||
      (window.matchMedia("(prefers-color-scheme: dark)").matches
        ? "dark"
        : "light");

    this.el.checked = currentTheme === "dark";

    this.handleToggle = (e) => {
      const newTheme = e.target.checked ? "dark" : "light";

      document.documentElement.setAttribute("data-theme", newTheme);
      localStorage.setItem("theme", newTheme);
    };

    this.el.addEventListener("change", this.handleToggle);
  },

  updated() {
    const currentTheme =
      document.documentElement.getAttribute("data-theme") ||
      localStorage.getItem("theme");

    this.el.checked = currentTheme === "dark";
  },
};

const initTheme = () => {
  const savedTheme = localStorage.getItem("theme");
  if (savedTheme) {
    document.documentElement.setAttribute("data-theme", savedTheme);
  } else if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
    document.documentElement.setAttribute("data-theme", "dark");
  } else {
    document.documentElement.setAttribute("data-theme", "light");
  }
};
initTheme();

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

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: {
    ...colocatedHooks,
    ThemeToggle,
    SortableCategories,
  },
});

topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());
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
