import { ring } from "./alarm";

export const KitchenScreen = {
  mounted() {
    this.lock = null;
    this.button = this.el.querySelector("[data-kitchen-start]");
    this.button?.addEventListener("click", () => this.start());
    this.onVisible = () => {
      if (document.visibilityState === "visible" && this.started) this.keepAwake();
    };
    this.onFullscreen = () => this.el.toggleAttribute("data-fullscreen", !!document.fullscreenElement);
    document.addEventListener("visibilitychange", this.onVisible);
    document.addEventListener("fullscreenchange", this.onFullscreen);
    this.handleEvent("kitchen:new", () => ring([880, 1175, 880, 1175]));
  },
  destroyed() {
    document.removeEventListener("visibilitychange", this.onVisible);
    document.removeEventListener("fullscreenchange", this.onFullscreen);
    this.lock?.release().catch(() => {});
  },
  async start() {
    this.started = true;
    ring([440]);
    try {
      await document.documentElement.requestFullscreen?.();
    } catch (_error) {}
    this.keepAwake();
  },
  async keepAwake() {
    try {
      this.lock = await navigator.wakeLock?.request("screen");
    } catch (_error) {}
  },
};
