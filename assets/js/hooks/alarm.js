const tones = (el) =>
  (el.dataset.tones || "660,880,660,880").split(",").map(Number).filter(Boolean);

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
    this.count = Number(this.el.dataset.count);
    ring(tones(this.el));
  },
  updated() {
    const count = Number(this.el.dataset.count);
    if (count > this.count) ring(tones(this.el));
    this.count = count;
  },
};
