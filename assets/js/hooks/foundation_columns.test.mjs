import test from 'node:test';
import assert from 'node:assert/strict';
import { FoundationColumns } from './foundation_columns.js';

function setup(store, staff, list) {
  const cells = new Map(['name', 'status'].map((key) => [key, {hidden: false, visible: true, classList: {toggle(name, value) { cells.get(key)[name === 'foundation-column-hidden' ? 'hidden' : 'visible'] = value; }}}]));
  const inputs = ['name', 'status'].map((key) => ({dataset: {column: key}, checked: true, disabled: key === 'name'}));
  const listeners = new Map();
  const el = {dataset: {staffId: staff, listId: list, tableId: 'table'}, querySelectorAll: () => inputs, addEventListener: (name, fn) => listeners.set(name, fn), removeEventListener: (name) => listeners.delete(name)};
  const table = {querySelectorAll: (selector) => [cells.get(selector.match(/"(.*?)"/)[1])]};
  globalThis.CSS = {escape: (key) => key};
  globalThis.localStorage = {getItem: (key) => store.get(key) ?? null, setItem: (key, value) => store.set(key, value)};
  globalThis.document = {body: {}, getElementById: () => table};
  globalThis.MutationObserver = class {constructor(fn) { this.fn = fn; } observe() {} disconnect() {}};
  const hook = {el, ...FoundationColumns};
  hook.mounted();
  return {hook, cells, inputs, listeners};
}

test('visible columns persist by staff and list, and reapply after a server patch', () => {
  const store = new Map();
  let state = setup(store, 's1', 'products');
  state.inputs[1].checked = false;
  state.listeners.get('change')();
  assert.equal(state.cells.get('status').hidden, true);
  state.hook.updated();
  assert.equal(state.cells.get('status').hidden, true);
  state.hook.destroyed();
  state = setup(store, 's1', 'products');
  assert.equal(state.inputs[1].checked, false);
  state.hook.destroyed();
  state = setup(store, 's2', 'products');
  assert.equal(state.inputs[1].checked, true);
  state.hook.destroyed();
  state = setup(store, 's1', 'orders');
  assert.equal(state.inputs[1].checked, true);
  state.hook.destroyed();
});

test('blocked browser storage does not break column display', () => {
  const state = setup(new Map(), 's1', 'products');
  globalThis.localStorage = {setItem() { throw new Error('blocked'); }};
  state.inputs[1].checked = false;
  assert.doesNotThrow(() => state.listeners.get('change')());
  assert.equal(state.cells.get('status').hidden, true);
  state.hook.destroyed();
});
