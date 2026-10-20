import { state } from '../../state.js';
import { save } from '../../data/storage.js';
import { render } from './render.js';
import { getSlotsFor } from './slots.js';
import { COLS } from '../../constants.js';
import { showToast } from '../../ui/toast.js';
import { t, getRowName } from '../../i18n.js';
import { trackItemsForClass } from '../tracker/storage.js';

export function addRow() {
  state.rows.push({ id: state.uid++, name: 'New Row' });
  save(); render();
  setTimeout(() => {
    const inputs = document.querySelectorAll('.row-name-input');
    if (inputs.length) inputs[inputs.length-1].focus();
  }, 50);
}

// Applies a destructive change and offers Undo, which restores the rows and items as they were.
export function withUndo(message, change) {
  const snap = { rows: structuredClone(state.rows), builds: structuredClone(state.builds) };
  change();
  save(); render();
  showToast(message, {
    action: {
      label: t('builder.undo'),
      onClick: () => { state.rows = snap.rows; state.builds = snap.builds; save(); render(); },
    },
  });
}

export function deleteRow(id) {
  const row = state.rows.find(r => r.id === id);
  withUndo(t('builder.rowDeleted', { name: getRowName(row?.name || '') }), () => {
    state.rows = state.rows.filter(r => r.id !== id);
    for (const cls of Object.keys(state.builds)) delete state.builds[cls][id];
  });
}

// Up/down buttons (phones, where rows can't be dragged).
export function moveRow(id, dir) {
  const i = state.rows.findIndex(r => r.id === id);
  const j = i + dir;
  if (i < 0 || j < 0 || j >= state.rows.length) return;
  [state.rows[i], state.rows[j]] = [state.rows[j], state.rows[i]];
  save(); render();
  document.querySelector(`tr[data-id="${id}"] .move-btn[data-dir="${dir}"]`)?.focus();
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

// Sends a phase's main items (not alternates) to the Item Tracker.
export function trackPhase(id) {
  const slots = getSlotsFor(id);
  const names = COLS.map(col => slots[col]?.[0]?.name).filter(Boolean);
  if (!names.length) return showToast(t('builder.trackEmpty'));
  const res = trackItemsForClass(state.selectedClass, names);
  if (!res) return showToast(t('trk.needProfile'));
  showToast(res.added
    ? t('builder.trackedPhase', { n: res.added, name: res.profile.name })
    : t('builder.trackedAlready', { name: res.profile.name }));
}
