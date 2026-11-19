export const WorkspaceFullscreen = {
  mounted() {
    this.onFullscreenChange = () => {
      const active = document.fullscreenElement === this.el;
      const button = this.el.querySelector("[data-fullscreen-toggle]");
      button.setAttribute("aria-pressed", String(active));
      button.setAttribute(
        "aria-label",
        active ? button.dataset.exitLabel : button.dataset.enterLabel,
      );
    };
    this.onToggle = async (event) => {
      if (!event.target.closest("[data-fullscreen-toggle]")) return;

      try {
        if (document.fullscreenElement === this.el) {
          await document.exitFullscreen?.();
        } else {
          await this.el.requestFullscreen?.();
        }
      } catch (_error) {}
    };

    this.el.addEventListener("click", this.onToggle);
    document.addEventListener("fullscreenchange", this.onFullscreenChange);
    this.onFullscreenChange();
  },

  updated() {
    this.onFullscreenChange();
  },

  destroyed() {
    this.el.removeEventListener("click", this.onToggle);
    document.removeEventListener("fullscreenchange", this.onFullscreenChange);
  },
};
