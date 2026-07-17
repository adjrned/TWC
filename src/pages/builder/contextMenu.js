import { state } from '../../state.js';
import { getSlotArr, clearSlot, clearSlotItem } from './slots.js';
import { openPicker } from './picker.js';
import { deleteRow } from './rows.js';

export function closeAllPopovers() {
  if (!state.activePopoverDrop) return;
  const pop = state.activePopoverDrop.querySelector('.slot-popover');
  if (pop) pop.remove();
  state.activePopoverDrop.classList.remove('pop-open');
  state.activePopoverDrop = null;
}

export function openCtx(e, rowId, col) {
  e.preventDefault();
  state.ctxRowId = rowId;
  state.ctxCol = col;
  closeAllPopovers();
  const arr = getSlotArr(rowId, col);
  const hasPrimary = !!arr[0], hasAlt = !!arr[1];
  document.getElementById('ctxAddAltBtn').style.display = (hasPrimary && !hasAlt) ? '' : 'none';
  document.getElementById('ctxChangeAltBtn').style.display = hasAlt ? '' : 'none';
  document.getElementById('ctxClearAltBtn').style.display = hasAlt ? '' : 'none';
  const m = document.getElementById('ctxMenu');
  m.style.display = 'block';
  m.style.left = Math.min(e.clientX, window.innerWidth - 185) + 'px';
  m.style.top = Math.min(e.clientY, window.innerHeight - 200) + 'px';
}

export function closeCtx() {
  document.getElementById('ctxMenu').style.display = 'none';
}

export function ctxOpenPicker(idx) {
  closeCtx();
  openPicker(state.ctxRowId, state.ctxCol, idx);
}

export function ctxClear() {
  clearSlot(state.ctxRowId, state.ctxCol);
  closeCtx();
}

export function ctxClearAlt() {
  clearSlotItem(state.ctxRowId, state.ctxCol, 1);
  closeCtx();
}

export function ctxDelete() {
  deleteRow(state.ctxRowId);
  closeCtx();
}
