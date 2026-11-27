const alertTones = {
  overdueIds: [660, 880, 660, 880],
  kitchenLateIds: [523, 440, 523, 440],
  channelCancelledIds: [880, 660, 440, 880, 660, 440],
};

const alertIds = (el, kind) => new Set((el.dataset[kind] || "").split(",").filter(Boolean));

export const ring = (frequencies) => {
  if (localStorage.getItem("orders-sound") === "off") return;
  try {
    const audio = new AudioContext();
    const now = audio.currentTime;
    frequencies.forEach((frequency, index) => {
      const oscillator = audio.createOscillator();
      const gain = audio.createGain();
      const start = now + index * 0.22;
      oscillator.frequency.value = frequency;
      gain.gain.setValueAtTime(0.0001, start);
      gain.gain.exponentialRampToValueAtTime(0.3, start + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.2);
      oscillator.connect(gain).connect(audio.destination);
      oscillator.start(start);
      oscillator.stop(start + 0.21);
    });
  } catch (_error) {}
};

export const Alarm = {
  mounted() {
    this.branchId = this.el.dataset.branchId || "";
    this.alerts = Object.fromEntries(
      Object.keys(alertTones).map((kind) => [kind, alertIds(this.el, kind)]),
    );
  },
  updated() {
    const branchId = this.el.dataset.branchId || "";
    const branchChanged = branchId !== this.branchId;

    for (const [kind, frequencies] of Object.entries(alertTones)) {
      const current = alertIds(this.el, kind);
      if (!branchChanged && [...current].some((id) => !this.alerts[kind].has(id))) {
        ring(frequencies);
      }
      this.alerts[kind] = current;
    }

    this.branchId = branchId;
  },
};
