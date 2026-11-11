export const HeaderScroll = {
  mounted() {
    this.viewport = this.el.querySelector("[data-scroll-viewport]");
    this.onScroll = () => this.scheduleUpdate();
    this.onLeft = () => this.scroll(-1);
    this.onRight = () => this.scroll(1);
    this.el.querySelector("[data-scroll-left]").addEventListener("click", this.onLeft);
    this.el.querySelector("[data-scroll-right]").addEventListener("click", this.onRight);
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
    this.el.querySelector("[data-scroll-left]").removeEventListener("click", this.onLeft);
    this.el.querySelector("[data-scroll-right]").removeEventListener("click", this.onRight);
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

  scroll(direction) {
    const behavior = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth";
    this.viewport.scrollBy({ left: direction * this.viewport.clientWidth * 0.75, behavior });
  },
};
