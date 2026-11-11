export const HeaderScroll = {
  mounted() {
    this.viewport = this.el.querySelector("[data-scroll-viewport]");
    this.onScroll = () => this.scheduleUpdate();
    this.viewport.addEventListener("scroll", this.onScroll, { passive: true });

    this.resizeObserver = new ResizeObserver(() => this.scheduleUpdate());
    this.resizeObserver.observe(this.viewport);
    this.mutationObserver = new MutationObserver(() => this.scheduleUpdate());
    this.mutationObserver.observe(this.viewport, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["class", "hidden", "style"],
    });
    this.scheduleUpdate();
  },

  updated() { this.scheduleUpdate(); },

  destroyed() {
    cancelAnimationFrame(this.updateFrame);
    this.resizeObserver.disconnect();
    this.mutationObserver.disconnect();
    this.viewport.removeEventListener("scroll", this.onScroll);
  },

  scheduleUpdate() {
    if (this.updateFrame) cancelAnimationFrame(this.updateFrame);
    this.updateFrame = requestAnimationFrame(() => {
      this.updateFrame = null;
      const maxScroll = this.viewport.scrollWidth - this.viewport.clientWidth;
      this.el.toggleAttribute("data-scroll-has-left", this.viewport.scrollLeft > 1);
      this.el.toggleAttribute("data-scroll-has-right", maxScroll > 1 && this.viewport.scrollLeft < maxScroll - 1);
    });
  },
};
