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
    if (!active || !active.getClientRects().length) return;
    const left = active.getBoundingClientRect().left - this.el.getBoundingClientRect().left + this.el.scrollLeft;
    const right = left + active.offsetWidth;
    if (left < this.el.scrollLeft || right > this.el.scrollLeft + this.el.clientWidth) {
      this.el.scrollLeft = Math.max(0, left - (this.el.clientWidth - active.offsetWidth) / 2);
    }
    const context = this.el.closest('#staff-context-navigation');
    const container = this.el.closest('#main-sidebar')?.querySelector('nav') || context;
    if (container && (container !== context || getComputedStyle(container).position === 'fixed')) {
      const top = active.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop;
      const bottom = top + active.offsetHeight;
      if (top < container.scrollTop || bottom > container.scrollTop + container.clientHeight) {
        container.scrollTop = Math.max(0, top - (container.clientHeight - active.offsetHeight) / 2);
      }
    }
  },
};
