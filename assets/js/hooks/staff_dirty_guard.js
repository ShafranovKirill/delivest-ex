const urlHere = () => window.location.pathname + window.location.search + window.location.hash;
const staffUrl = (href) => {
  const url = new URL(href, window.location.href);
  return url.origin === window.location.origin && url.pathname.startsWith('/staff')
    ? url.pathname + url.search + url.hash : null;
};
const values = (form) => JSON.stringify([...new FormData(form)].map(([key, value]) =>
  [key, value instanceof File ? [value.name, value.size] : value]));

export const StaffDirtyGuard = {
  mounted() {
    this.dialog = this.el.querySelector('#staff-unsaved-dialog');
    this.baselines = new WeakMap();
    this.pending = null;
    this.saving = null;
    this.bypass = false;
    this.currentUrl = urlHere();
    this.forms = () => [...document.querySelectorAll('form[data-staff-dirty]')];
    this.capture = () => this.forms().forEach((form) => {
      if (!this.baselines.has(form)) this.baselines.set(form, values(form));
    });
    this.dirty = () => this.forms().some((form) => {
      if (!this.baselines.has(form)) return false;
      return values(form) !== this.baselines.get(form);
    });
    this.capture();
    this.observer = new MutationObserver(() => this.capture());
    this.observer.observe(document.body, {childList: true, subtree: true});
    this.onInput = (event) => {
      const form = event.target.closest?.('form[data-staff-dirty]');
      if (form && !this.baselines.has(form)) this.baselines.set(form, values(form));
    };
    this.onSubmit = (event) => {
      if (this.forms().includes(event.target)) this.saving = event.target;
    };
    this.onSaved = (event) => {
      const id = event.detail?.id;
      const form = id ? this.forms().find((candidate) => candidate.id === id) : this.saving;
      this.saving = null;
      if (form) this.baselines.set(form, values(form));
    };
    this.onPageLoaded = () => { this.currentUrl = urlHere(); this.capture(); };
    this.onClick = (event) => {
      if (this.bypass || !this.dirty() || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const link = event.target.closest?.('a[href]');
      if (!link || link.hasAttribute('download') || link.target === '_blank') return;
      const to = staffUrl(link.href);
      if (!to || to === this.currentUrl) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      this.pending = to;
      this.dialog.showModal();
    };
    this.onPopState = (event) => {
      if (this.bypass || !this.dirty()) return;
      const to = urlHere();
      if (to === this.currentUrl) return;
      event.stopImmediatePropagation();
      history.pushState(null, '', this.currentUrl);
      this.pending = to;
      this.dialog.showModal();
    };
    this.onUnload = (event) => {
      if (!this.dirty() || this.bypass) return;
      event.preventDefault();
      event.returnValue = '';
    };
    this.onStay = () => { this.pending = null; this.dialog.close(); };
    this.onLeave = () => {
      const to = this.pending;
      this.pending = null;
      this.bypass = true;
      this.dialog.close();
      if (to) window.location.assign(to);
    };
    document.addEventListener('input', this.onInput, true);
    document.addEventListener('change', this.onInput, true);
    document.addEventListener('submit', this.onSubmit, true);
    document.addEventListener('click', this.onClick, true);
    window.addEventListener('popstate', this.onPopState, true);
    window.addEventListener('beforeunload', this.onUnload);
    window.addEventListener('phx:page-loading-stop', this.onPageLoaded);
    window.addEventListener('phx:staff:form-saved', this.onSaved);
    this.el.querySelector('#staff-unsaved-stay').addEventListener('click', this.onStay);
    this.el.querySelector('#staff-unsaved-leave').addEventListener('click', this.onLeave);
  },
  updated() { this.currentUrl = urlHere(); this.capture(); },
  destroyed() {
    this.observer.disconnect();
    document.removeEventListener('input', this.onInput, true);
    document.removeEventListener('change', this.onInput, true);
    document.removeEventListener('submit', this.onSubmit, true);
    document.removeEventListener('click', this.onClick, true);
    window.removeEventListener('popstate', this.onPopState, true);
    window.removeEventListener('beforeunload', this.onUnload);
    window.removeEventListener('phx:page-loading-stop', this.onPageLoaded);
    window.removeEventListener('phx:staff:form-saved', this.onSaved);
    this.el.querySelector('#staff-unsaved-stay').removeEventListener('click', this.onStay);
    this.el.querySelector('#staff-unsaved-leave').removeEventListener('click', this.onLeave);
  },
};
