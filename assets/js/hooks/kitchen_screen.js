import { kiosk } from "./kiosk";

export const KitchenScreen = kiosk({
  start: "[data-kitchen-start]",
  startOutside: true,
  fullscreenSelf: true,
  greeting: [440],
  sounds: { "kitchen:new": [880, 1175, 880, 1175] },
});
