import assert from "node:assert/strict";
import test from "node:test";
import { Alarm } from "./alarm.js";

function setup({ branchId = "center", overdueIds = "", kitchenLateIds = "", channelCancelledIds = "" } = {}) {
  const sounds = [];
  let muted = false;

  globalThis.localStorage = {
    getItem(key) {
      assert.equal(key, "orders-sound");
      return muted ? "off" : "on";
    },
  };

  globalThis.AudioContext = class {
    constructor() {
      sounds.push([]);
    }

    currentTime = 0;
    destination = {};

    createOscillator() {
      const frequency = {};
      return {
        frequency,
        connect() { return this; },
        start() { sounds.at(-1).push(frequency.value); },
        stop() {},
      };
    }

    createGain() {
      return {
        gain: { setValueAtTime() {}, exponentialRampToValueAtTime() {} },
        connect() { return this; },
      };
    }
  };

  const el = { dataset: { branchId, overdueIds, kitchenLateIds, channelCancelledIds } };
  const hook = { el, ...Alarm };
  hook.mounted();

  return { hook, el, sounds, mute: () => { muted = true; } };
}

test("existing alerts stay quiet on mount, update, and a fresh page mount", () => {
  const { hook, el, sounds } = setup({ kitchenLateIds: "late-15" });
  assert.deepEqual(sounds, []);

  hook.updated();
  assert.deepEqual(sounds, []);

  const nextPage = { el: { dataset: { ...el.dataset } }, ...Alarm };
  nextPage.mounted();
  nextPage.updated();
  assert.deepEqual(sounds, []);
});

test("new alert IDs ring, including the first and a replacement at the same count", () => {
  const { hook, el, sounds } = setup();

  el.dataset.kitchenLateIds = "late-1";
  hook.updated();
  assert.deepEqual(sounds, [[523, 440, 523, 440]]);

  el.dataset.kitchenLateIds = "late-2";
  hook.updated();
  assert.deepEqual(sounds.at(-1), [523, 440, 523, 440]);
  assert.equal(sounds.length, 2);

  el.dataset.overdueIds = "overdue-1";
  el.dataset.channelCancelledIds = "cancel-1";
  hook.updated();
  assert.deepEqual(sounds.slice(-2), [
    [660, 880, 660, 880],
    [880, 660, 440, 880, 660, 440],
  ]);
});

test("changing branch resets the baseline and the sound switch mutes later alerts", () => {
  const { hook, el, sounds, mute } = setup({ overdueIds: "old" });

  el.dataset.branchId = "north";
  el.dataset.overdueIds = "north-1";
  hook.updated();
  assert.deepEqual(sounds, []);

  mute();
  el.dataset.overdueIds = "north-1,north-2";
  hook.updated();
  assert.deepEqual(sounds, []);
});
