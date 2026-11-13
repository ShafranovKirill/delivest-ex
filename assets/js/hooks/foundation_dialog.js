export const FoundationDialog = {
  mounted() {
    this.opener = document.activeElement;
    this.keydown = (event) => {
      const dialogs = document.querySelectorAll('[phx-hook="FoundationDialog"]');
      if (dialogs[dialogs.length - 1] !== this.el) return;
      if (event.key === "Escape") {
        event.preventDefault();
        if (this.el.dataset.pending === "true") return;
        const action = this.el.dataset.dirty === "true" ? "request_close" : this.el.dataset.closeEvent;
        if (action) {
          if (this.el.dataset.target === "component") this.pushEventTo(this.el, action);
          else this.pushEvent(action);
        }
      }
      if (event.key !== "Tab") return;
      const focusable = [...this.el.querySelectorAll('button:not([disabled]), a[href], input:not([disabled]), select:not([disabled]), textarea:not([disabled])')];
      if (!focusable.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    };
    document.addEventListener("keydown", this.keydown);
    this.el.querySelector('button:not([disabled]), input:not([disabled])')?.focus();
  },
  destroyed() {
    document.removeEventListener("keydown", this.keydown);
    if (this.opener?.isConnected) this.opener.focus();
  },
};
