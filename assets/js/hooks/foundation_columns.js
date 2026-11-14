export const FoundationColumns = {
  mounted() {
    this.key = `staff-columns:${this.el.dataset.staffId || document.querySelector('[data-staff-id]')?.dataset.staffId || 'anonymous'}:${this.el.dataset.listId}`;
    this.readInputs();
    let stored;
    try { stored = JSON.parse(localStorage.getItem(this.key) || 'null'); } catch (_) { stored = null; }
    if (Array.isArray(stored)) {
      const visible = new Set(stored);
      this.checkboxes.forEach((input) => { if (!input.disabled) input.checked = visible.has(input.dataset.column); });
    }
    this.onChange = () => {
      this.readInputs();
      try { localStorage.setItem(this.key, JSON.stringify(this.checkboxes.filter((input) => input.checked).map((input) => input.dataset.column))); } catch (_) { /* Browsers can disable storage. */ }
      this.apply();
    };
    this.el.addEventListener('change', this.onChange);
    this.observer = new MutationObserver(() => this.apply());
    this.observer.observe(document.body, { childList: true, subtree: true });
    this.apply();
  },
  updated() { this.readInputs(); this.apply(); },
  destroyed() { this.el.removeEventListener('change', this.onChange); this.observer?.disconnect(); },
  readInputs() { this.checkboxes = [...this.el.querySelectorAll('input[data-column]')]; },
  apply() {
    this.readInputs();
    const table = document.getElementById(this.el.dataset.tableId);
    if (!table) return;
    for (const input of this.checkboxes) {
      for (const cell of table.querySelectorAll(`[data-column="${CSS.escape(input.dataset.column)}"]`)) {
        cell.classList.toggle('foundation-column-hidden', !input.checked);
        cell.classList.toggle('foundation-column-visible', input.checked);
      }
    }
  },
};
