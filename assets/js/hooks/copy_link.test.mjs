import assert from "node:assert/strict";
import test from "node:test";
import { CopyLink } from "./copy_link.js";

function mounted(writeText) {
  const status = { textContent: "" };
  const listeners = new Map();
  const el = {
    id: "advertising-copy-example",
    dataset: {
      url: "https://example.test/r/token",
      statusId: "copy-status-example",
      copySuccess: "Ссылка скопирована",
      copyFailure: "Скопируйте адрес вручную",
    },
    addEventListener: (event, listener) => listeners.set(event, listener),
    removeEventListener: (event) => listeners.delete(event),
  };

  Object.defineProperty(globalThis, "document", {
    configurable: true,
    value: { getElementById: () => status },
  });
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: { clipboard: writeText ? { writeText } : undefined },
  });

  const hook = { el };
  CopyLink.mounted.call(hook);
  return { hook, listeners, status };
}

test("reports clipboard success only after the write resolves", async () => {
  let resolve;
  const { hook, listeners, status } = mounted(() => new Promise((done) => (resolve = done)));
  const click = listeners.get("click")();
  assert.equal(status.textContent, "");
  resolve();
  await click;
  assert.equal(status.textContent, "Ссылка скопирована");
  CopyLink.destroyed.call(hook);
  assert.equal(listeners.size, 0);
});

test("reports rejected or unavailable clipboard without an unhandled rejection", async () => {
  const denied = mounted(() => Promise.reject(new Error("denied")));
  await denied.listeners.get("click")();
  assert.equal(denied.status.textContent, "Скопируйте адрес вручную");

  const missing = mounted(null);
  await missing.listeners.get("click")();
  assert.equal(missing.status.textContent, "Скопируйте адрес вручную");
});
