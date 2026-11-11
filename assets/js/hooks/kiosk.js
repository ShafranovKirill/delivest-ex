import { ring } from "./alarm";

export const kiosk = ({ start, greeting, sounds, startOutside = false, fullscreenSelf = false }) => ({
  mounted() {
    this.lock = null;
    this.onStart = (event) => {
      if (event.target.closest(start)) this.start();
    };
    this.onStop = (event) => {
      if (event.target.closest("[data-kitchen-stop]")) document.exitFullscreen?.();
    };
    (startOutside ? document : this.el).addEventListener("click", this.onStart);
    this.el.addEventListener("click", this.onStop);
    this.onVisible = () => {
      if (document.visibilityState === "visible" && this.started) this.keepAwake();
    };
    this.onFullscreen = () => this.el.toggleAttribute(
      "data-fullscreen",
      document.fullscreenElement === (fullscreenSelf ? this.el : document.documentElement),
    );
    document.addEventListener("visibilitychange", this.onVisible);
    document.addEventListener("fullscreenchange", this.onFullscreen);
    Object.entries(sounds).forEach(([event, tones]) => this.handleEvent(event, () => ring(tones)));
  },
  destroyed() {
    (startOutside ? document : this.el).removeEventListener("click", this.onStart);
    this.el.removeEventListener("click", this.onStop);
    document.removeEventListener("visibilitychange", this.onVisible);
    document.removeEventListener("fullscreenchange", this.onFullscreen);
    this.lock?.release().catch(() => {});
  },
  async start() {
    this.started = true;
    ring(greeting);
    try {
      await (fullscreenSelf ? this.el : document.documentElement).requestFullscreen?.();
    } catch (_error) {}
    this.keepAwake();
  },
  async keepAwake() {
    try {
      this.lock = await navigator.wakeLock?.request("screen");
    } catch (_error) {}
  },
});
