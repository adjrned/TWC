import { state } from '../../state.js';
import { LABELS } from '../../constants.js';
import { iconLibrary } from '../../data/icons.js';
import { showToast } from '../../ui/toast.js';
import { esc } from '../../ui/escape.js';
import { setSlotItem } from './slots.js';

export function openPicker(rowId, col, idx) {
  if (!state.selectedClass) { showToast('Select a hero class first!'); return; }
  state.pickerTargetRow = rowId;
  state.pickerTargetCol = col;
  state.pickerTargetIdx = idx;
  const pill = document.getElementById('pickerModePill');
  if (idx === 1) { pill.textContent = 'ALT'; pill.className = 'picker-mode-pill mode-alt'; }
  else { pill.textContent = 'PRIMARY'; pill.className = 'picker-mode-pill mode-primary'; }
  document.getElementById('pickerTitle').textContent = `Choose Icon — ${LABELS[col]}`;
  document.getElementById('pickerSearch').value = '';
  buildPickerGrid();
  document.getElementById('pickerOverlay').classList.add('show');
  setTimeout(() => document.getElementById('pickerSearch').focus(), 50);
}

export function buildPickerGrid() {
  const grid = document.getElementById('pickerGrid');
  grid.innerHTML = '';
  if (!iconLibrary.length) {
    grid.innerHTML = `<div class="picker-empty">No icons found in <code>twicons/</code>.<br><br>Add a <code>twicons/manifest.json</code> or ensure the folder is accessible.</div>`;
    document.getElementById('pickerCount').textContent = '0';
    return;
  }
  iconLibrary.forEach(icon => {
    const div = document.createElement('div');
    div.className = 'picker-item';
    div.dataset.name = icon.name.toLowerCase();
    div.innerHTML = `<img src="${icon.src}" alt="${esc(icon.name)}" onerror="this.closest('.picker-item').style.display='none'">
                     <span class="pi-name">${esc(icon.name)}</span>`;
    div.addEventListener('click', () => pickIcon(icon));
    grid.appendChild(div);
  });
  document.getElementById('pickerCount').textContent = iconLibrary.length;
}

export function filterPicker() {
  const q = document.getElementById('pickerSearch').value.toLowerCase();
  let vis = 0;
  document.querySelectorAll('.picker-item').forEach(el => {
    const m = el.dataset.name.includes(q);
    el.classList.toggle('hidden', !m);
    if (m) vis++;
  });
  document.getElementById('pickerCount').textContent = vis;
}

export function pickIcon(icon) {
  setSlotItem(state.pickerTargetRow, state.pickerTargetCol, state.pickerTargetIdx, { type: 'library', name: icon.name, src: icon.src });
  closePicker();
}

export function closePicker() {
  document.getElementById('pickerOverlay').classList.remove('show');
  state.pickerTargetRow = null;
  state.pickerTargetCol = null;
  state.pickerTargetIdx = 0;
}

export function closePickerOnBg(e) {
  if (e.target === document.getElementById('pickerOverlay')) closePicker();
}
