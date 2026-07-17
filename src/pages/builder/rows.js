import { state } from '../../state.js';
import { save } from '../../data/storage.js';
import { render } from './render.js';

export function addRow() {
  state.rows.push({ id: state.uid++, name: 'New Row' });
  save(); render();
  setTimeout(() => {
    const inputs = document.querySelectorAll('.row-name-input');
    if (inputs.length) inputs[inputs.length-1].focus();
  }, 50);
}

export function deleteRow(id) {
  state.rows = state.rows.filter(r => r.id !== id);
  for (const cls of Object.keys(state.builds)) delete state.builds[cls][id];
  save(); render();
}

export function renameRow(id, val) {
  const r = state.rows.find(r => r.id === id);
  if (r && val.trim()) { r.name = val.trim(); save(); }
}

export function onDragStart(e, id) {
  state.dragSrcId = id;
  e.dataTransfer.effectAllowed = 'move';
  setTimeout(() => document.querySelector(`tr[data-id="${id}"]`)?.classList.add('dragging'), 0);
}

export function onDragOver(e, id) {
  e.preventDefault();
  document.querySelectorAll('tbody tr').forEach(tr => tr.classList.remove('drag-over'));
  if (id !== state.dragSrcId) document.querySelector(`tr[data-id="${id}"]`)?.classList.add('drag-over');
}

export function onDrop(e, id) {
  e.preventDefault();
  if (state.dragSrcId === null || state.dragSrcId === id) return;
  const fi = state.rows.findIndex(r => r.id === state.dragSrcId);
  const ti = state.rows.findIndex(r => r.id === id);
  if (fi < 0 || ti < 0) return;
  const [m] = state.rows.splice(fi, 1);
  state.rows.splice(ti, 0, m);
  state.dragSrcId = null;
  save(); render();
}

export function onDragEnd() {
  state.dragSrcId = null;
  document.querySelectorAll('tbody tr').forEach(tr => tr.classList.remove('dragging','drag-over'));
}
