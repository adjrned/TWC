import { state } from '../../state.js';
import { LABELS, COLS, ROSTER } from '../../constants.js';
import { iconLibrary } from '../../data/icons.js';
import { showToast } from '../../ui/toast.js';
import { esc } from '../../ui/escape.js';
import { setSlotItem } from './slots.js';
import { t } from '../../i18n.js';

const BATCH_SIZE = 48;
let filtered = [];
let rendered = 0;
let observer = null;
let activeCategory = 'all';
let itemIcons = [];
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
  return CLASS_PATTERNS.some(p =>
    name.startsWith(p) && (name.length === p.length || name[p.length] === '_' || /^[A-Z]/.test(name.slice(p.length)))
  );
}

async function initItemIcons() {
  if (initialized) return;
  itemIcons = iconLibrary.filter(icon => !isClassIcon(icon.name));

  // Load item data for slot categorization
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

  document.getElementById('pickerTitle').textContent = `Choose Icon — ${LABELS[col]}`;
  document.getElementById('pickerSearch').value = '';

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
    { key: 'all', label: 'All Items', icon: '📦' },
    { key: 'weapon', label: 'Weapon', icon: '⚔️' },
    { key: 'helm', label: 'Helm', icon: '⛑️' },
    { key: 'body', label: 'Body', icon: '🥋' },
    { key: 'wings', label: 'Wings', icon: '🪽' },
    { key: 'accessory', label: 'Accessory', icon: '💍' },
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
  let pool = itemIcons;

  // Only filter by category when there's no search query
  if (respectCategory && activeCategory !== 'all' && itemsBySlot[activeCategory]?.length) {
    const slotNames = new Set(itemsBySlot[activeCategory].map(n => n.toLowerCase()));
    pool = pool.filter(icon => slotNames.has(icon.name.toLowerCase()));
  }

  if (query) {
    pool = pool.filter(icon => icon.name.toLowerCase().includes(query));
  }

  return pool;
}

function applyFilter() {
  const q = document.getElementById('pickerSearch').value.toLowerCase();

  // When searching, always search ALL items regardless of active tab
  if (q) {
    filtered = getFilteredIcons(q, false);
  } else if (activeCategory === 'all') {
    showSearchPrompt();
    return;
  } else if (itemsBySlot[activeCategory]?.length) {
    filtered = getFilteredIcons('', true);
  } else {
    // No item data for this category — show prompt
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

  renderBatch(grid);
  setupInfiniteScroll(grid);
  document.getElementById('pickerCount').textContent = filtered.length <= BATCH_SIZE
    ? `${filtered.length} ${t('picker.items')}`
    : `${rendered} / ${filtered.length}`;
}

export function buildPickerGrid() {
  applyFilter();
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
    img.decoding = 'async';
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
  searchTimeout = setTimeout(() => applyFilter(), 150);
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
