export const ActiveSectionNav = {
  mounted() {
    this.resizeObserver = new ResizeObserver(() => this.revealActiveTab());
    this.resizeObserver.observe(this.el);
    this.revealActiveTab();
  },
  updated() { this.revealActiveTab(); },
  destroyed() { this.resizeObserver.disconnect(); },
  revealActiveTab() {
    const active = this.el.querySelector('[aria-current="page"]');
    if (!active) return;
    const left = active.getBoundingClientRect().left - this.el.getBoundingClientRect().left + this.el.scrollLeft;
    const right = left + active.offsetWidth;
    if (left < this.el.scrollLeft || right > this.el.scrollLeft + this.el.clientWidth) {
      this.el.scrollLeft = Math.max(0, left - (this.el.clientWidth - active.offsetWidth) / 2);
    }
  },
};
