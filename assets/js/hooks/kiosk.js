import { ring } from "./alarm";

export const kiosk = ({ start, greeting, sounds }) => ({
  mounted() {
    this.lock = null;
    this.el.querySelector(start)?.addEventListener("click", () => this.start());
    this.onVisible = () => {
      if (document.visibilityState === "visible" && this.started) this.keepAwake();
    };
    this.onFullscreen = () => this.el.toggleAttribute("data-fullscreen", !!document.fullscreenElement);
    document.addEventListener("visibilitychange", this.onVisible);
    document.addEventListener("fullscreenchange", this.onFullscreen);
    Object.entries(sounds).forEach(([event, tones]) => this.handleEvent(event, () => ring(tones)));
  },
  destroyed() {
    document.removeEventListener("visibilitychange", this.onVisible);
    document.removeEventListener("fullscreenchange", this.onFullscreen);
    this.lock?.release().catch(() => {});
  },
  async start() {
    this.started = true;
    ring(greeting);
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
});
