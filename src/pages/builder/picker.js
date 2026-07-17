import { state } from '../../state.js';
import { LABELS, COLS, ROSTER } from '../../constants.js';
import { iconLibrary } from '../../data/icons.js';
import { showToast } from '../../ui/toast.js';
import { setSlotItem } from './slots.js';
import { t, getIconName, loadItemTranslations } from '../../i18n.js';

const BATCH_SIZE = 48;
let filtered = [];
let rendered = 0;
let observer = null;
let activeCategory = 'all';
let itemIcons = [];
let searchIndex = [];
let itemsBySlot = {};
let initialized = false;

const CLASS_PATTERNS = (() => {
  const all = [];
  for (const list of Object.values(ROSTER)) {
    list.forEach(name => all.push(name.replace(/\s+/g, '')));
  }
  return all;
})();

function isClassIcon(name) {
  for (let i = 0; i < CLASS_PATTERNS.length; i++) {
    const p = CLASS_PATTERNS[i];
    if (name.startsWith(p) && (name.length === p.length || name[p.length] === '_' || (name.charCodeAt(p.length) >= 65 && name.charCodeAt(p.length) <= 90))) {
      return true;
    }
  }
  return false;
}

async function initItemIcons() {
  if (initialized) return;
  itemIcons = iconLibrary.filter(icon => !isClassIcon(icon.name));

  // Pre-compute lowercase names for fast searching
  searchIndex = itemIcons.map(icon => icon.name.toLowerCase());

  try {
    const r = await fetch('data/items.json');
    if (r.ok) {
      const items = await r.json();
      itemsBySlot = {};
      COLS.forEach(c => { itemsBySlot[c] = []; });
      items.forEach(item => {
        if (item.slot && itemsBySlot[item.slot]) {
          itemsBySlot[item.slot].push(item.name);
        }
      });
      loadItemTranslations(items);
    }
  } catch(e) {}

  initialized = true;
}

export async function openPicker(rowId, col, idx) {
  if (!state.selectedClass) { showToast('Select a hero class first!'); return; }
  state.pickerTargetRow = rowId;
  state.pickerTargetCol = col;
  state.pickerTargetIdx = idx;

  await initItemIcons();

  const pill = document.getElementById('pickerModePill');
  if (idx === 1) { pill.textContent = 'ALT'; pill.className = 'picker-mode-pill mode-alt'; }
  else { pill.textContent = 'PRIMARY'; pill.className = 'picker-mode-pill mode-primary'; }

  document.getElementById('pickerTitle').textContent = `${t('picker.title')} — ${t('col.' + col)}`;
  document.getElementById('pickerSearch').value = '';
  document.getElementById('pickerSearch').placeholder = t('picker.search');

  activeCategory = col;
  buildCategoryTabs();
  applyFilter();

  document.getElementById('pickerOverlay').classList.add('show');
  setTimeout(() => document.getElementById('pickerSearch').focus(), 50);
}

function buildCategoryTabs() {
  let tabs = document.getElementById('pickerTabs');
  if (!tabs) {
    tabs = document.createElement('div');
    tabs.id = 'pickerTabs';
    tabs.className = 'picker-tabs';
    const header = document.querySelector('.picker-header');
    header.parentNode.insertBefore(tabs, header.nextSibling);
  }

  const categories = [
    { key: 'all', label: t('picker.allItems'), icon: '📦' },
    { key: 'weapon', label: t('col.weapon'), icon: '⚔️' },
    { key: 'helm', label: t('col.helm'), icon: '⛑️' },
    { key: 'body', label: t('col.body'), icon: '🥋' },
    { key: 'wings', label: t('col.wings'), icon: '🪽' },
    { key: 'accessory', label: t('col.accessory'), icon: '💍' },
  ];

  tabs.innerHTML = categories.map(cat => {
    const count = cat.key === 'all' ? '' : (itemsBySlot[cat.key]?.length || '');
    return `<button class="picker-tab ${cat.key === activeCategory ? 'active' : ''}" data-cat="${cat.key}">
      <span class="picker-tab-icon">${cat.icon}</span>
      ${cat.label}
      ${count ? `<span class="picker-tab-count">${count}</span>` : ''}
    </button>`;
  }).join('');

  tabs.querySelectorAll('.picker-tab').forEach(btn => {
    btn.addEventListener('click', () => {
      activeCategory = btn.dataset.cat;
      tabs.querySelectorAll('.picker-tab').forEach(b => b.classList.toggle('active', b === btn));
      document.getElementById('pickerSearch').value = '';
      applyFilter();
    });
  });
}

function showSearchPrompt() {
  const grid = document.getElementById('pickerGrid');
  grid.innerHTML = `<div class="picker-empty">
    <div style="font-size: 28px; margin-bottom: 12px;">🔍</div>
    <p>${t('picker.searchPrompt')}</p>
    <p style="font-size: 11px; margin-top: 8px; color: var(--muted);">${itemIcons.length} ${t('picker.available')}</p>
  </div>`;
  document.getElementById('pickerCount').textContent = `${itemIcons.length} ${t('picker.items')}`;
}

function getFilteredIcons(query, respectCategory) {
  let indices;

  if (respectCategory && activeCategory !== 'all' && itemsBySlot[activeCategory]?.length) {
    const slotNames = new Set(itemsBySlot[activeCategory].map(n => n.toLowerCase()));
    indices = [];
    for (let i = 0; i < itemIcons.length; i++) {
      if (slotNames.has(searchIndex[i])) indices.push(i);
    }
  } else {
    indices = null;
  }

  if (query) {
    const result = [];
    if (indices) {
      for (let i = 0; i < indices.length; i++) {
        if (searchIndex[indices[i]].includes(query)) result.push(itemIcons[indices[i]]);
      }
    } else {
      for (let i = 0; i < searchIndex.length; i++) {
        if (searchIndex[i].includes(query)) result.push(itemIcons[i]);
      }
    }
    return result;
  }

  if (indices) return indices.map(i => itemIcons[i]);
  return itemIcons;
}

function applyFilter() {
  const q = document.getElementById('pickerSearch').value.toLowerCase();

  if (q) {
    filtered = getFilteredIcons(q, false);
  } else if (activeCategory === 'all') {
    showSearchPrompt();
    return;
  } else if (itemsBySlot[activeCategory]?.length) {
    filtered = getFilteredIcons('', true);
  } else {
    const catIcon = activeCategory === 'weapon' ? '⚔️' : activeCategory === 'helm' ? '⛑️' : activeCategory === 'body' ? '🥋' : activeCategory === 'wings' ? '🪽' : '💍';
    const grid = document.getElementById('pickerGrid');
    grid.innerHTML = `<div class="picker-empty">
      <div style="font-size: 28px; margin-bottom: 12px;">${catIcon}</div>
      <p>${t('picker.noData', { slot: t('col.' + activeCategory) })}</p>
      <p style="font-size: 11px; margin-top: 8px; color: var(--muted);">${t('picker.useSearch')}</p>
    </div>`;
    document.getElementById('pickerCount').textContent = '—';
    return;
  }

  rendered = 0;
  const grid = document.getElementById('pickerGrid');
  grid.innerHTML = '';

  if (filtered.length === 0) {
    grid.innerHTML = `<div class="picker-empty">${t('picker.noMatch')}</div>`;
    document.getElementById('pickerCount').textContent = '0';
    return;
  }

  // Event delegation — single listener on grid
  grid.onclick = handleGridClick;

  renderBatch(grid);
  setupInfiniteScroll(grid);
  document.getElementById('pickerCount').textContent = filtered.length <= BATCH_SIZE
    ? `${filtered.length} ${t('picker.items')}`
    : `${rendered} / ${filtered.length}`;
}

function handleGridClick(e) {
  const item = e.target.closest('.picker-item');
  if (!item) return;
  const idx = parseInt(item.dataset.idx, 10);
  if (isNaN(idx) || !filtered[idx]) return;
  pickIcon(filtered[idx]);
}

export function buildPickerGrid() {
  applyFilter();
}

function renderBatch(grid) {
  const end = Math.min(rendered + BATCH_SIZE, filtered.length);
  const frag = document.createDocumentFragment();
  for (let i = rendered; i < end; i++) {
    const icon = filtered[i];
    const div = document.createElement('div');
    div.className = 'picker-item';
    div.dataset.idx = i;
    const img = document.createElement('img');
    img.src = icon.src;
    img.alt = icon.name;
    img.loading = 'lazy';
    img.decoding = 'async';
    img.onerror = () => { div.style.display = 'none'; };
    const label = document.createElement('span');
    label.className = 'pi-name';
    label.textContent = getIconName(icon.name);
    div.appendChild(img);
    div.appendChild(label);
    frag.appendChild(div);
  }
  grid.appendChild(frag);
  rendered = end;
}

function setupInfiniteScroll(grid) {
  if (observer) observer.disconnect();

  if (rendered >= filtered.length) return;

  const sentinel = document.createElement('div');
  sentinel.className = 'picker-sentinel';
  grid.appendChild(sentinel);

  observer = new IntersectionObserver((entries) => {
    if (entries[0].isIntersecting && rendered < filtered.length) {
      sentinel.remove();
      renderBatch(grid);
      if (rendered < filtered.length) {
        grid.appendChild(sentinel);
      }
      document.getElementById('pickerCount').textContent = `${rendered} / ${filtered.length}`;
    }
  }, { root: grid, rootMargin: '200px' });

  observer.observe(sentinel);
}

let searchTimeout = null;
export function filterPicker() {
  clearTimeout(searchTimeout);
  searchTimeout = setTimeout(() => applyFilter(), 50);
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
