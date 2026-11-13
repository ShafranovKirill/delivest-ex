import test from 'node:test';
import assert from 'node:assert/strict';
import { FoundationDirty } from './foundation_dirty.js';

function setup() {
  const listeners = new Map();
  const location = {href: 'http://localhost:4107/staff/foundation-gallery?view=settings', origin: 'http://localhost:4107', pathname: '/staff/foundation-gallery', search: '?view=settings', hash: ''};
  globalThis.window = {location, addEventListener: (event, fn) => listeners.set(`window:${event}`, fn), removeEventListener: (event) => listeners.delete(`window:${event}`)};
  const pushed = [];
  globalThis.history = {pushState: (_state, _title, url) => pushed.push(url)};
  globalThis.document = {addEventListener: (event, fn) => listeners.set(`document:${event}`, fn), removeEventListener: (event) => listeners.delete(`document:${event}`)};
  const events = [];
  const hook = {el: {dataset: {dirty: 'true'}}, pushEvent: (name, payload) => events.push([name, payload]), ...FoundationDirty};
  hook.mounted();
  return {hook, listeners, events, location, pushed};
}

function click(link, options = {}) {
  return {button: 0, target: {closest: () => link}, prevented: false, preventDefault() {this.prevented = true;}, stopPropagation() {}, ...options};
}

test('dirty form guards internal leave and beforeunload', () => {
  const {hook, listeners, events} = setup();
  const link = {href: 'http://localhost:4107/staff/foundation-gallery?view=list', target: '', dataset: {phxLink: 'patch'}, hasAttribute: () => false};
  const event = click(link);
  listeners.get('document:click')(event);
  assert.equal(event.prevented, true);
  assert.deepEqual(events, [['request_leave', {to: '/staff/foundation-gallery?view=list', kind: 'patch'}]]);
  const unload = {prevented: false, preventDefault() {this.prevented = true;}};
  listeners.get('window:beforeunload')(unload);
  assert.equal(unload.prevented, true);
  hook.el.dataset.dirty = 'false';
  const clean = {prevented: false, preventDefault() {this.prevented = true;}};
  listeners.get('window:beforeunload')(clean);
  assert.equal(clean.prevented, false);
  hook.destroyed();
  assert.equal(listeners.size, 0);
});

test('modified clicks and unrelated links remain normal browser actions', () => {
  const {hook, listeners, events} = setup();
  const link = {href: 'http://localhost:4107/staff/settings', target: '', dataset: {}, hasAttribute: () => false};
  assert.equal(click(link, {ctrlKey: true}).prevented, false);
  const modified = click(link, {metaKey: true});
  listeners.get('document:click')(modified);
  assert.equal(modified.prevented, false);
  const unrelated = click({...link, href: 'http://localhost:4107/locale'});
  listeners.get('document:click')(unrelated);
  assert.equal(unrelated.prevented, false);
  assert.deepEqual(events, []);
  hook.destroyed();
});

test('Back is rolled back until explicit leave confirmation', () => {
  const {hook, listeners, events, location, pushed} = setup();
  location.search = '?view=list';
  const pop = {stopped: false, stopImmediatePropagation() {this.stopped = true;}};
  listeners.get('window:popstate')(pop);
  assert.equal(pop.stopped, true);
  assert.deepEqual(pushed, ['/staff/foundation-gallery?view=settings']);
  assert.deepEqual(events, [['request_leave', {to: '/staff/foundation-gallery?view=list', kind: 'history'}]]);
  hook.destroyed();
});
