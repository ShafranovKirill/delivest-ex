export const CopyLink = {
  mounted() {
    this.onClick = async () => {
      const status = document.getElementById(this.el.dataset.statusId);

      try {
        if (!navigator.clipboard?.writeText) throw new Error("Clipboard unavailable");
        await navigator.clipboard.writeText(this.el.dataset.url);
        if (status) status.textContent = this.el.dataset.copySuccess;
      } catch (_) {
        if (status) status.textContent = this.el.dataset.copyFailure;
      }
    };
    this.el.addEventListener("click", this.onClick);
  },
  destroyed() {
    this.el.removeEventListener("click", this.onClick);
  },
};
