import test from 'node:test';
import assert from 'node:assert/strict';
import { FoundationDialog } from './foundation_dialog.js';

function setup({dirty = false, pending = false, nested = false, target = false} = {}) {
  const events = [];
  const buttons = Array.from({length: 2}, () => ({isConnected: true, focus() { document.activeElement = this; }}));
  const dialog = {dataset: {dirty: String(dirty), pending: String(pending), closeEvent: 'close_panel', target: target ? 'component' : undefined}, querySelector: () => buttons[0], querySelectorAll: () => buttons};
  const parent = nested ? {dataset: {closeEvent: 'parent'}} : null;
  const listeners = new Map();
  globalThis.document = {
    activeElement: {isConnected: true, focus() { document.activeElement = this; }},
    addEventListener(name, cb) { listeners.set(name, cb); },
    removeEventListener(name) { listeners.delete(name); },
    querySelectorAll() { return parent ? [parent, dialog] : [dialog]; },
  };
  const opener = document.activeElement;
  const hook = {el: dialog, pushEvent(name) { events.push(name); }, pushEventTo(el, name) { events.push([el, name]); }, ...FoundationDialog};
  hook.mounted();
  return {hook, dialog, buttons, events, listeners, opener};
}

function key(listeners, name, shiftKey = false) {
  const event = {key: name, shiftKey, prevented: false, preventDefault() { this.prevented = true; }};
  listeners.get('keydown')(event);
  return event;
}

test('Escape closes only top dialog and returns focus to opener', () => {
  const {hook, events, listeners, opener} = setup({nested: true});
  assert.equal(key(listeners, 'Escape').prevented, true);
  assert.deepEqual(events, ['close_panel']);
  hook.destroyed();
  assert.equal(document.activeElement, opener);
});

test('dirty Escape asks guard and pending Escape does nothing', () => {
  let instance = setup({dirty: true});
  key(instance.listeners, 'Escape');
  assert.deepEqual(instance.events, ['request_close']);
  instance.hook.destroyed();
  instance = setup({pending: true});
  key(instance.listeners, 'Escape');
  assert.deepEqual(instance.events, []);
});

test('Tab wraps within dialog', () => {
  const {hook, buttons, listeners} = setup();
  buttons[1].focus();
  assert.equal(key(listeners, 'Tab').prevented, true);
  assert.equal(document.activeElement, buttons[0]);
  assert.equal(key(listeners, 'Tab', true).prevented, true);
  assert.equal(document.activeElement, buttons[1]);
  hook.destroyed();
});

test('Escape targets the owning LiveComponent when configured', () => {
  const {dialog, events, listeners} = setup({target: true});
  key(listeners, 'Escape');
  assert.deepEqual(events, [[dialog, 'close_panel']]);
});
