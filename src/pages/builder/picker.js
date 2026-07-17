import { state } from '../../state.js';
import { LABELS } from '../../constants.js';
import { iconLibrary } from '../../data/icons.js';
import { showToast } from '../../ui/toast.js';
import { esc } from '../../ui/escape.js';
import { setSlotItem } from './slots.js';

const BATCH_SIZE = 60;
let filtered = [];
let rendered = 0;
let observer = null;

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
  filtered = iconLibrary.slice();
  rendered = 0;
  buildPickerGrid();
  document.getElementById('pickerOverlay').classList.add('show');
  setTimeout(() => document.getElementById('pickerSearch').focus(), 50);
}

export function buildPickerGrid() {
  const grid = document.getElementById('pickerGrid');
  grid.innerHTML = '';
  rendered = 0;

  if (!iconLibrary.length) {
    grid.innerHTML = `<div class="picker-empty">No icons found in <code>twicons/</code>.<br><br>Add a <code>twicons/manifest.json</code> or ensure the folder is accessible.</div>`;
    document.getElementById('pickerCount').textContent = '0';
    return;
  }

  renderBatch(grid);
  setupInfiniteScroll(grid);
  document.getElementById('pickerCount').textContent = filtered.length;
}

function renderBatch(grid) {
  const end = Math.min(rendered + BATCH_SIZE, filtered.length);
  for (let i = rendered; i < end; i++) {
    const icon = filtered[i];
    const div = document.createElement('div');
    div.className = 'picker-item';
    div.dataset.name = icon.name.toLowerCase();
    const img = document.createElement('img');
    img.src = icon.src;
    img.alt = icon.name;
    img.loading = 'lazy';
    img.onerror = () => { div.style.display = 'none'; };
    const label = document.createElement('span');
    label.className = 'pi-name';
    label.textContent = icon.name;
    div.appendChild(img);
    div.appendChild(label);
    div.addEventListener('click', () => pickIcon(icon));
    grid.appendChild(div);
  }
  rendered = end;
}

function setupInfiniteScroll(grid) {
  if (observer) observer.disconnect();

  const sentinel = document.createElement('div');
  sentinel.className = 'picker-sentinel';
  grid.appendChild(sentinel);

  observer = new IntersectionObserver((entries) => {
    if (entries[0].isIntersecting && rendered < filtered.length) {
      sentinel.remove();
      renderBatch(grid);
      grid.appendChild(sentinel);
      document.getElementById('pickerCount').textContent = `${rendered} / ${filtered.length}`;
    }
  }, { root: grid, rootMargin: '200px' });

  observer.observe(sentinel);
}

export function filterPicker() {
  const q = document.getElementById('pickerSearch').value.toLowerCase();
  filtered = q ? iconLibrary.filter(icon => icon.name.toLowerCase().includes(q)) : iconLibrary.slice();
  rendered = 0;
  const grid = document.getElementById('pickerGrid');
  grid.innerHTML = '';
  if (filtered.length === 0) {
    grid.innerHTML = `<div class="picker-empty">No icons match your search.</div>`;
    document.getElementById('pickerCount').textContent = '0';
    return;
  }
  renderBatch(grid);
  setupInfiniteScroll(grid);
  document.getElementById('pickerCount').textContent = `${rendered} / ${filtered.length}`;
}

export function pickIcon(icon) {
  setSlotItem(state.pickerTargetRow, state.pickerTargetCol, state.pickerTargetIdx, { type: 'library', name: icon.name, src: icon.src });
  closePicker();
}

export function closePicker() {
  document.getElementById('pickerOverlay').classList.remove('show');
  if (observer) { observer.disconnect(); observer = null; }
  state.pickerTargetRow = null;
  state.pickerTargetCol = null;
  state.pickerTargetIdx = 0;
}

export function closePickerOnBg(e) {
  if (e.target === document.getElementById('pickerOverlay')) closePicker();
}
