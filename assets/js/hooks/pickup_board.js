import { kiosk } from "./kiosk";

export const PickupBoard = kiosk({
  start: "[data-board-start]",
  greeting: [784],
  sounds: { "board:ready": [784, 988, 1319] },
});
