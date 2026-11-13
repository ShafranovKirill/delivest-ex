import test from 'node:test';
import assert from 'node:assert/strict';
import {StaffDirtyGuard} from './staff_dirty_guard.js';

function setup() {
  const handlers = new Map();
  const add = (prefix) => (name, fn) => handlers.set(`${prefix}:${name}`, fn);
  const remove = (prefix) => (name) => handlers.delete(`${prefix}:${name}`);
  const form = {fields: [['name', 'Original']], isConnected: true, closest: () => null, querySelector: () => null};
  globalThis.File = class File {};
  globalThis.FormData = class FormData { constructor(target) { this.fields = target.fields; } [Symbol.iterator]() { return this.fields[Symbol.iterator](); } };
  globalThis.MutationObserver = class MutationObserver { observe() {} disconnect() {} };
  const location = {href: 'http://localhost/staff/b/main/loyalty', origin: 'http://localhost', pathname: '/staff/b/main/loyalty', search: '', hash: '', assign(to) {this.assigned = to;}};
  globalThis.window = {location, addEventListener: add('window'), removeEventListener: remove('window')};
  globalThis.document = {body: {}, querySelectorAll: () => [form], addEventListener: add('document'), removeEventListener: remove('document')};
  globalThis.history = {pushState: (_state, _title, to) => {location.pathname = to;}};
  const dialog = {open: false, showModal() {this.open = true;}, close() {this.open = false;}};
  const stay = {addEventListener: add('stay'), removeEventListener: remove('stay')};
  const leave = {addEventListener: add('leave'), removeEventListener: remove('leave')};
  const hook = {el: {querySelector: (selector) => ({'#staff-unsaved-dialog': dialog, '#staff-unsaved-stay': stay, '#staff-unsaved-leave': leave})[selector]}, ...StaffDirtyGuard};
  hook.mounted();
  return {hook, handlers, form, dialog, location};
}

function linkEvent() {
  const link = {href: 'http://localhost/staff/settings', target: '', hasAttribute: () => false};
  return {button: 0, target: {closest: () => link}, prevented: false, preventDefault() {this.prevented = true;}, stopImmediatePropagation() {}};
}

test('dirty staff form blocks scope navigation until confirmed', () => {
  const {hook, handlers, form, dialog, location} = setup();
  form.fields = [['name', 'Changed']];
  const event = linkEvent();
  handlers.get('document:click')(event);
  assert.equal(event.prevented, true);
  assert.equal(dialog.open, true);
  handlers.get('stay:click')();
  assert.equal(dialog.open, false);
  assert.equal(location.assigned, undefined);
  handlers.get('document:click')(linkEvent());
  handlers.get('leave:click')();
  assert.equal(location.assigned, '/staff/settings');
  hook.destroyed();
});

test('successful save clears dirty state and back navigation is guarded before save', () => {
  const {hook, handlers, form, dialog, location} = setup();
  form.fields = [['name', 'Changed']];
  location.pathname = '/staff/b/main/orders';
  handlers.get('window:popstate')({stopImmediatePropagation() {}});
  assert.equal(dialog.open, true);
  handlers.get('stay:click')();
  handlers.get('document:submit')({target: form});
  handlers.get('window:phx:page-loading-stop')();
  const stillDirty = linkEvent();
  handlers.get('document:click')(stillDirty);
  assert.equal(stillDirty.prevented, true);
  handlers.get('stay:click')();
  handlers.get('window:phx:staff:form-saved')({detail: {}});
  const click = linkEvent();
  handlers.get('document:click')(click);
  assert.equal(click.prevented, false);
  form.fields = [['name', 'Changed again']];
  const rearmed = linkEvent();
  handlers.get('document:click')(rearmed);
  assert.equal(rearmed.prevented, true);
  hook.destroyed();
});
