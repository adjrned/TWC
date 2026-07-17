import { state } from '../../state.js';
import { ICONS_PATH } from '../../constants.js';
import { showToast } from '../../ui/toast.js';
import { save } from '../../data/storage.js';
import { render } from './render.js';

export function getSlotsFor(rowId) {
  return state.selectedClass ? (state.builds[state.selectedClass]?.[rowId] || {}) : {};
}

export function getSlotArr(rowId, col) {
  return getSlotsFor(rowId)[col] || [];
}

export function iconSrc(item) {
  return !item ? null : item.type === 'upload' ? item.src : (item.src || ICONS_PATH + encodeURIComponent(item.name) + '.jpg');
}

export function setSlotItem(rowId, col, idx, item) {
  if (!state.selectedClass) { showToast('Select a hero class first!'); return; }
  if (!state.builds[state.selectedClass]) state.builds[state.selectedClass] = {};
  if (!state.builds[state.selectedClass][rowId]) state.builds[state.selectedClass][rowId] = {};
  const arr = [...(state.builds[state.selectedClass][rowId][col] || [])];
  while (arr.length <= idx) arr.push(null);
  arr[idx] = item;
  while (arr.length && !arr[arr.length-1]) arr.pop();
  if (arr.length) state.builds[state.selectedClass][rowId][col] = arr;
  else delete state.builds[state.selectedClass][rowId][col];
  save(); render();
}

export function clearSlotItem(rowId, col, idx) {
  if (!state.selectedClass || !state.builds[state.selectedClass]?.[rowId]) return;
  const arr = [...getSlotArr(rowId, col)];
  arr[idx] = null;
  while (arr.length && !arr[arr.length-1]) arr.pop();
  if (arr.length) state.builds[state.selectedClass][rowId][col] = arr;
  else delete state.builds[state.selectedClass][rowId][col];
  save(); render();
}

export function clearSlot(rowId, col) {
  if (!state.selectedClass || !state.builds[state.selectedClass]?.[rowId]) return;
  delete state.builds[state.selectedClass][rowId][col];
  save(); render();
}
