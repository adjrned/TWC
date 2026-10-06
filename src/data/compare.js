// Pinned items for the compare view, persisted in localStorage.
const KEY = 'compareItems';
export const COMPARE_MAX = 5;

let pins = [];
try { pins = JSON.parse(localStorage.getItem(KEY) || '[]').filter(n => typeof n === 'string'); } catch (e) { pins = []; }

const listeners = new Set();

function emit() {
  localStorage.setItem(KEY, JSON.stringify(pins));
  listeners.forEach(fn => fn(pins));
}

export function getPins() {
  return [...pins];
}

export function isPinned(name) {
  return pins.includes(name);
}

// Returns false when the list is already full.
export function togglePin(name) {
  if (pins.includes(name)) pins = pins.filter(n => n !== name);
  else if (pins.length >= COMPARE_MAX) return false;
  else pins = [...pins, name];
  emit();
  return true;
}

export function setPins(names) {
  pins = [...new Set(names)].slice(0, COMPARE_MAX);
  emit();
}

export function onPinsChange(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
