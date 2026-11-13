export const FoundationDirty = {
  mounted() {
    this.currentUrl = window.location.pathname + window.location.search + window.location.hash;
    this.beforeUnload = (event) => {
      if (this.el.dataset.dirty !== 'true') return;
      event.preventDefault();
      event.returnValue = '';
    };
    this.onClick = (event) => {
      if (this.el.dataset.dirty !== 'true' || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const link = event.target.closest('a[href]');
      if (!link || link.hasAttribute('download') || link.target === '_blank') return;
      const url = new URL(link.href, window.location.href);
      if (url.origin !== window.location.origin || !url.pathname.startsWith('/staff')) return;
      const to = url.pathname + url.search + url.hash;
      if (to === this.currentUrl) return;
      event.preventDefault();
      event.stopPropagation();
      this.pushEvent('request_leave', {to, kind: link.dataset.phxLink || 'ordinary'});
    };
    this.onPopState = (event) => {
      if (this.el.dataset.dirty !== 'true') return;
      const to = window.location.pathname + window.location.search + window.location.hash;
      if (to === this.currentUrl) return;
      event.stopImmediatePropagation();
      history.pushState(null, '', this.currentUrl);
      this.pushEvent('request_leave', {to, kind: 'history'});
    };
    window.addEventListener('beforeunload', this.beforeUnload);
    window.addEventListener('popstate', this.onPopState, true);
    document.addEventListener('click', this.onClick, true);
  },
  updated() { this.currentUrl = window.location.pathname + window.location.search + window.location.hash; },
  destroyed() {
    window.removeEventListener('beforeunload', this.beforeUnload);
    window.removeEventListener('popstate', this.onPopState, true);
    document.removeEventListener('click', this.onClick, true);
  },
};
