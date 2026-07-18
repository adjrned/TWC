import { state } from '../../state.js';
import { LABELS, COLS, ROSTER } from '../../constants.js';
import { iconLibrary } from '../../data/icons.js';
import { showToast } from '../../ui/toast.js';
import { setSlotItem } from './slots.js';
import { t, loadItemTranslations, getLocale } from '../../i18n.js';
import { translateItemName, buildLocalizedSearchIndex, loadTranslationData, precomputeTranslations } from '../../data/translate.js';

const BATCH_SIZE = 48;
let filtered = [];
let rendered = 0;
let observer = null;
let activeCategory = 'all';
let itemIcons = [];
let searchIndex = [];
let localizedSearchIndex = [];
let cachedLocale = null;
let itemDb = [];
let itemsByType = {};
let initialized = false;

// Tier ordering: highest first
const GRADE_TO_TIER = { 5: 'arcana', 4: 'alteia', 3: 'gnosis', 2: 'neptinos', 1: 'deltirama' };
const RANK_TO_TIER = { '[Rare]': 'rare', '[Magic]': 'magic', '[Normal]': 'normal', 'none': 'none' };

function getItemTier(item) {
  if (item.rank === '[Epic]' && item.grade >= 1) return GRADE_TO_TIER[item.grade] || 'deltirama';
  return RANK_TO_TIER[item.rank] || 'none';
}

const TIER_ORDER = ['arcana', 'alteia', 'gnosis', 'neptinos', 'deltirama', 'rare', 'magic', 'normal', 'none'];

function tierSortValue(item) {
  return TIER_ORDER.indexOf(getItemTier(item));
}

// Map item types to builder columns
function typeToCategory(type) {
  if (!type) return 'other';
  const l = type.toLowerCase();
  if (l.startsWith('weapon') || l === 'pickaxe') return 'weapon';
  if (l === 'armor') return 'armor';
  if (l === 'headwear') return 'headwear';
  if (l === 'wings') return 'wings';
  if (l === 'accessory') return 'accessory';
  return 'other';
}

// Map builder columns to item type categories
const COL_TO_CATEGORY = {
  weapon: 'weapon',
  helm: 'headwear',
  body: 'armor',
  wings: 'wings',
  accessory: 'accessory',
};

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
  searchIndex = itemIcons.map(icon => icon.name.toLowerCase());

  try {
    const r = await fetch('data/items.json');
    if (r.ok) {
      itemDb = await r.json();
      // Group items by type category
      itemsByType = { weapon: [], headwear: [], armor: [], wings: [], accessory: [], other: [] };
      itemDb.forEach(item => {
        const cat = typeToCategory(item.type);
        if (itemsByType[cat]) itemsByType[cat].push(item);
      });
      // Sort each category by tier (highest first)
      for (const cat of Object.keys(itemsByType)) {
        itemsByType[cat].sort((a, b) => tierSortValue(a) - tierSortValue(b));
      }
      loadItemTranslations(itemDb);
    }
  } catch(e) {}

  await loadTranslationData();
  precomputeTranslations(itemIcons, getLocale());
  rebuildLocalizedIndex();
  initialized = true;
}

function rebuildLocalizedIndex() {
  const locale = getLocale();
  if (cachedLocale === locale && localizedSearchIndex.length) return;
  cachedLocale = locale;
  localizedSearchIndex = buildLocalizedSearchIndex(itemIcons, locale);
}

export async function openPicker(rowId, col, idx) {
  if (!state.selectedClass) { showToast('Select a hero class first!'); return; }
  state.pickerTargetRow = rowId;
  state.pickerTargetCol = col;
  state.pickerTargetIdx = idx;

  await initItemIcons();
  rebuildLocalizedIndex();

  const pill = document.getElementById('pickerModePill');
  if (idx === 1) { pill.textContent = 'ALT'; pill.className = 'picker-mode-pill mode-alt'; }
  else { pill.textContent = 'PRIMARY'; pill.className = 'picker-mode-pill mode-primary'; }

  document.getElementById('pickerTitle').textContent = 'Select Item';
  document.getElementById('pickerSearch').value = '';
  document.getElementById('pickerSearch').placeholder = t('picker.search');

  // Auto-select the category matching the column
  activeCategory = COL_TO_CATEGORY[col] || 'all';
  buildCategoryTabs();
  applyFilter();

  document.getElementById('pickerOverlay').classList.add('show');
  setTimeout(() => document.getElementById('pickerSearch').focus(), 50);
}

let tabsBuilt = false;

function buildCategoryTabs() {
  let tabs = document.getElementById('pickerTabs');
  if (!tabs) {
    tabs = document.createElement('div');
    tabs.id = 'pickerTabs';
    tabs.className = 'picker-tabs';
    const header = document.querySelector('.picker-header');
    header.parentNode.insertBefore(tabs, header.nextSibling);
  }

  if (!tabsBuilt || cachedLocale !== getLocale()) {
    const categories = [
      { key: 'all', label: t('picker.allItems'), icon: '📦' },
      { key: 'weapon', label: t('col.weapon'), icon: '⚔️' },
      { key: 'headwear', label: t('col.helm'), icon: '⛑️' },
      { key: 'armor', label: t('col.body'), icon: '🥋' },
      { key: 'wings', label: t('col.wings'), icon: '🪽' },
      { key: 'accessory', label: t('col.accessory'), icon: '💍' },
    ];

    tabs.innerHTML = categories.map(cat => `
      <button class="picker-tab ${cat.key === activeCategory ? 'active' : ''}" data-cat="${cat.key}">
        <span class="picker-tab-icon">${cat.icon}</span>
        ${cat.label}
      </button>
    `).join('');

    tabs.onclick = (e) => {
      const btn = e.target.closest('.picker-tab');
      if (!btn) return;
      activeCategory = btn.dataset.cat;
      tabs.querySelectorAll('.picker-tab').forEach(b => b.classList.toggle('active', b === btn));
      document.getElementById('pickerSearch').value = '';
      applyFilter();
    };
    tabsBuilt = true;
  } else {
    tabs.querySelectorAll('.picker-tab').forEach(b => b.classList.toggle('active', b.dataset.cat === activeCategory));
  }
}

const TIER_LABELS = {
  arcana: 'Arcana', alteia: 'Alteia', gnosis: 'Gnosis',
  neptinos: 'Neptinos', deltirama: 'Deltirama', rare: 'Rare', magic: 'Magic', normal: 'Normal', none: ''
};

const TIER_CSS = {
  arcana: 'rarity-arcana', alteia: 'rarity-alteia', gnosis: 'rarity-gnosis',
  neptinos: 'rarity-neptinos', deltirama: 'rarity-deltirama', rare: 'rarity-rare', magic: 'rarity-magic',
};

function getItemsForCategory(cat) {
  if (cat === 'all') {
    // All equippable items, sorted by tier
    const all = [...(itemsByType.weapon || []), ...(itemsByType.headwear || []),
      ...(itemsByType.armor || []), ...(itemsByType.wings || []), ...(itemsByType.accessory || [])];
    all.sort((a, b) => tierSortValue(a) - tierSortValue(b));
    return all;
  }
  return itemsByType[cat] || [];
}

function applyFilter() {
  const q = document.getElementById('pickerSearch').value.toLowerCase();

  if (q) {
    // Search overrides category — search all items
    const idx = localizedSearchIndex.length ? localizedSearchIndex : searchIndex;
    const results = [];
    for (let i = 0; i < idx.length; i++) {
      if (idx[i].includes(q)) {
        const dbItem = itemDb.find(d => d.name.toLowerCase() === searchIndex[i]);
        results.push({ icon: itemIcons[i], dbItem });
      }
    }
    // Sort search results by tier
    results.sort((a, b) => {
      const ta = a.dbItem ? tierSortValue(a.dbItem) : 99;
      const tb = b.dbItem ? tierSortValue(b.dbItem) : 99;
      return ta - tb;
    });
    filtered = results;
  } else {
    // Show category items from the database
    const catItems = getItemsForCategory(activeCategory);
    filtered = catItems.map(dbItem => {
      const icon = itemIcons.find(ic => ic.name.toLowerCase() === dbItem.name.toLowerCase());
      return { icon: icon || { name: dbItem.name, src: `twicons/${encodeURIComponent(dbItem.name)}.jpg` }, dbItem };
    });
  }

  rendered = 0;
  const grid = document.getElementById('pickerGrid');
  grid.innerHTML = '';
  grid.onclick = handleGridClick;

  if (filtered.length === 0) {
    grid.innerHTML = `<div class="picker-empty">${q ? t('picker.noMatch') : 'No items in this category.'}</div>`;
    document.getElementById('pickerCount').textContent = '0';
    return;
  }

  renderBatch(grid);
  setupInfiniteScroll(grid);
  initPickerHover();
  document.getElementById('pickerCount').textContent = filtered.length <= BATCH_SIZE
    ? `${filtered.length} ${t('picker.items')}`
    : `${rendered} / ${filtered.length}`;
}

function handleGridClick(e) {
  const item = e.target.closest('.picker-item');
  if (!item) return;
  const idx = parseInt(item.dataset.idx, 10);
  if (isNaN(idx) || !filtered[idx]) return;
  pickIcon(filtered[idx].icon);
}

export function buildPickerGrid() {
  applyFilter();
}

function renderBatch(grid) {
  const end = Math.min(rendered + BATCH_SIZE, filtered.length);
  const frag = document.createDocumentFragment();
  const locale = getLocale();
  for (let i = rendered; i < end; i++) {
    const { icon, dbItem } = filtered[i];
    const tier = dbItem ? getItemTier(dbItem) : 'none';
    const tierCss = TIER_CSS[tier] || '';
    const tierLabel = TIER_LABELS[tier] || '';

    const div = document.createElement('div');
    div.className = 'picker-item' + (tierCss ? ' ' + tierCss : '');
    div.dataset.idx = i;
    const img = document.createElement('img');
    img.src = icon.src;
    img.alt = icon.name;
    img.loading = 'lazy';
    img.decoding = 'async';
    img.onerror = () => { div.style.display = 'none'; };

    const label = document.createElement('span');
    label.className = 'pi-name';
    label.textContent = translateItemName(icon.name, locale);

    div.appendChild(img);
    div.appendChild(label);

    if (tierLabel) {
      const badge = document.createElement('span');
      badge.className = 'pi-tier ' + tierCss;
      badge.textContent = tierLabel;
      div.appendChild(badge);
    }

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
  hidePickerTooltip();
  if (observer) { observer.disconnect(); observer = null; }
  state.pickerTargetRow = null;
  state.pickerTargetCol = null;
  state.pickerTargetIdx = 0;
}

// ── Picker hover tooltip ──
const STAT_LABELS = {
  damage: 'Damage', armor: 'Armor', hp: 'HP', mp: 'MP',
  str: 'STR', agi: 'AGI', int: 'INT', allstat: 'All Stats',
  mainstat: 'Main Stat', hpregen: 'HP Regen', mpregen: 'MP Regen',
  movespeed: 'Move Speed', critchancepercent: 'Crit Chance',
  critmultiplier: 'Crit Multi', attackspeedpercent: 'Attack Speed',
  skilldamagepercent: 'Skill Dmg', periodicdamagepercent: 'Periodic Dmg',
  procdamagepercent: 'Proc Dmg', damagedealtpercent: 'Dmg Dealt',
  healingpercent: 'Healing', dodgechancepercent: 'Dodge',
  drpercent: 'Dmg Resist', mdpercent: 'Magic Resist',
};

function formatStatVal(key, val) {
  if (key.endsWith('percent')) return `+${Math.round(val * 100)}%`;
  if (key === 'critmultiplier') return `x${val}`;
  return `+${val}`;
}

function ensurePickerTooltip() {
  let tt = document.getElementById('pickerTooltip');
  if (!tt) {
    tt = document.createElement('div');
    tt.id = 'pickerTooltip';
    tt.className = 'picker-tooltip';
    document.body.appendChild(tt);
  }
  return tt;
}

function showPickerTooltip(e, dbItem) {
  const tt = ensurePickerTooltip();
  if (!dbItem) { tt.classList.remove('show'); return; }

  const tier = dbItem ? getItemTier(dbItem) : '';
  const tierLabel = TIER_LABELS[tier] || '';
  let html = `<div class="ptt-name">${dbItem.name}</div>`;
  if (tierLabel) html += `<div class="ptt-tier">${tierLabel}</div>`;
  if (dbItem.description) html += `<div class="ptt-desc">${dbItem.description}</div>`;

  if (dbItem.stats) {
    const lines = [];
    for (const [k, v] of Object.entries(dbItem.stats)) {
      if (k === 'passive' || k === 'active' || k === 'spec') continue;
      lines.push(`<div class="ptt-stat"><span class="ptt-stat-label">${STAT_LABELS[k] || k}</span><span class="ptt-stat-val">${formatStatVal(k, v)}</span></div>`);
    }
    if (lines.length) html += `<div class="ptt-stats">${lines.join('')}</div>`;
    if (dbItem.stats.passive?.length) {
      html += `<div class="ptt-passive">${dbItem.stats.passive.slice(0, 3).map(l => '• ' + l).join('<br>')}</div>`;
    }
  }

  tt.innerHTML = html;
  tt.classList.add('show');
  positionPickerTooltip(e, tt);
}

function positionPickerTooltip(e, tt) {
  const x = e.clientX + 16;
  const y = e.clientY - 10;
  tt.style.left = Math.min(x, window.innerWidth - 280) + 'px';
  tt.style.top = Math.min(y, window.innerHeight - tt.offsetHeight - 10) + 'px';
}

function hidePickerTooltip() {
  const tt = document.getElementById('pickerTooltip');
  if (tt) tt.classList.remove('show');
}

function initPickerHover() {
  const grid = document.getElementById('pickerGrid');
  grid.addEventListener('mousemove', (e) => {
    const item = e.target.closest('.picker-item');
    if (!item) { hidePickerTooltip(); return; }
    const idx = parseInt(item.dataset.idx, 10);
    if (isNaN(idx) || !filtered[idx]) { hidePickerTooltip(); return; }
    showPickerTooltip(e, filtered[idx].dbItem);
  });
  grid.addEventListener('mouseleave', hidePickerTooltip);
}

export function closePickerOnBg(e) {
  if (e.target === document.getElementById('pickerOverlay')) closePicker();
}
