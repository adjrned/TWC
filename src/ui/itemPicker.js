import { esc } from './escape.js';
import { t, getLocale, getTypeName } from '../i18n.js';
import { translateItemName } from '../data/translate.js';
import {
  loadItems, rankInfo, tierIndex, typeGroup, weaponSubtype, numericStats, formatStat,
  STAT_SHORT, AFFINITY_ELEMENT, localizedItemName, TIERS,
} from '../data/items.js';
import { iconHtml, bindItemHover } from './itemUi.js';
import { hideItemTooltip } from './tooltip.js';
import { slotIcon } from './slotIcons.js';

// Searchable item list modal shared by the build planner and the item tracker.
// Tabs map an item type group to the slot icon/label shown for it.
export const EQUIP_TABS = [
  { key: 'weapon', icon: 'weapon', label: () => t('col.weapon') },
  { key: 'headwear', icon: 'helm', label: () => t('col.helm') },
  { key: 'armor', icon: 'body', label: () => t('col.body') },
  { key: 'wings', icon: 'wings', label: () => t('col.wings') },
  { key: 'accessory', icon: 'accessory', label: () => t('col.accessory') },
];
export const MATERIAL_TAB = { key: 'material', icon: 'material', label: () => getTypeName('Material') };
export const ALL_TAB = { key: 'all', icon: 'all', label: () => t('picker.allItems') };

const SUBTYPES = ['melee', 'bow', 'gun', 'staff', 'bag', 'shared'];
const SUBTYPE_LABEL = { melee: 'Melee', bow: 'Bow', gun: 'Gun', staff: 'Staff', bag: 'Bag', shared: 'Shared' };
const TIER_FILTERS = ['arcana', 'alteia', 'gnosis', 'neptinos', 'deltirama', 'rare', 'magic'];
const EQUIP_GROUPS = new Set(['weapon', 'headwear', 'armor', 'wings', 'accessory']);

let items = [];
let built = false;
let filtered = [];
let cursor = 0;
let opts = null;
const f = { tab: 'weapon', tier: '', sub: '', q: '' };
const hayCache = new Map();

function hay(item) {
  const loc = getLocale();
  let h = hayCache.get(item);
  if (!h || h.loc !== loc) {
    const parts = [item.name, item.koreanname || ''];
    if (loc === 'zh') parts.push(translateItemName(item.name, 'zh'));
    h = { loc, s: parts.join(' ').toLowerCase() };
    hayCache.set(item, h);
  }
  return h.s;
}

function el(id) { return document.getElementById(id); }

function buildModal() {
  el('pickerModal').innerHTML = `
    <div class="pk-head">
      <div class="pk-title">
        <span class="pk-title-icon" id="pkTitleIcon"></span>
        <h2 id="pickerTitle"></h2>
        <span class="pk-mode" id="pickerModePill"></span>
      </div>
      <button type="button" class="pk-close" data-close aria-label="Close">×</button>
    </div>
    <div class="pk-search">
      <label class="idb-search">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/></svg>
        <input type="search" id="pickerSearch" autocomplete="off" spellcheck="false">
      </label>
    </div>
    <div class="pk-tabs" id="pkTabs" role="tablist"></div>
    <div class="pk-filters" id="pkFilters"></div>
    <div class="pk-list" id="pickerGrid" role="listbox"></div>
    <div class="pk-foot">
      <span id="pickerCount"></span>
      <span class="pk-keys"><kbd>↑</kbd><kbd>↓</kbd> ${t('picker.navigate')} · <kbd>Enter</kbd> ${t('picker.select')} · <kbd>Esc</kbd> ${t('picker.close')}</span>
    </div>`;

  el('pickerOverlay').addEventListener('click', e => { if (e.target === el('pickerOverlay')) closePicker(); });
  const modal = el('pickerModal');
  modal.addEventListener('click', e => {
    if (e.target.closest('[data-close]')) return closePicker();
    const tab = e.target.closest('[data-tab]');
    if (tab) { f.tab = tab.dataset.tab; f.sub = ''; el('pickerSearch').value = f.q = ''; return refresh(); }
    const chip = e.target.closest('[data-tier], [data-sub]');
    if (chip && !chip.disabled) {
      if ('tier' in chip.dataset) f.tier = f.tier === chip.dataset.tier ? '' : chip.dataset.tier;
      else f.sub = f.sub === chip.dataset.sub ? '' : chip.dataset.sub;
      return refresh();
    }
    const row = e.target.closest('.pk-row');
    if (row) pick(+row.dataset.idx);
  });
  el('pickerSearch').addEventListener('input', e => { f.q = e.target.value; refresh(); });
  el('pickerSearch').addEventListener('keydown', onKey);
  el('pickerGrid').addEventListener('mousemove', e => {
    const row = e.target.closest('.pk-row');
    if (row && +row.dataset.idx !== cursor) setCursor(+row.dataset.idx, false);
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape' && isPickerOpen() && e.target !== el('pickerSearch')) closePicker();
  });
  bindItemHover(el('pickerGrid'));
  built = true;
}

function onKey(e) {
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault();
    setCursor(Math.max(0, Math.min(filtered.length - 1, cursor + (e.key === 'ArrowDown' ? 1 : -1))), true);
  } else if (e.key === 'Enter') {
    e.preventDefault();
    if (filtered.length) pick(cursor);
  } else if (e.key === 'Escape') {
    e.preventDefault();
    if (f.q) { e.target.value = f.q = ''; refresh(); } else closePicker();
  }
}

function setCursor(i, scroll) {
  const list = el('pickerGrid');
  list.querySelector('.pk-row.cursor')?.classList.remove('cursor');
  cursor = i;
  const row = list.querySelector(`.pk-row[data-idx="${i}"]`);
  row?.classList.add('cursor');
  if (scroll) row?.scrollIntoView({ block: 'nearest' });
}

// Base filter (tab / search), before tier & subtype — used for chip counts.
function baseList() {
  const terms = f.q.toLowerCase().trim().split(/\s+/).filter(Boolean);
  const pool = opts.allItems ? items : items.filter(i => EQUIP_GROUPS.has(typeGroup(i.type)));
  if (terms.length) return items.filter(i => terms.every(x => hay(i).includes(x)));
  if (f.tab === 'all') return pool;
  return items.filter(i => typeGroup(i.type) === f.tab);
}

function refresh(keepCursor = false) {
  const base = baseList();
  const showSub = !f.q && f.tab === 'weapon';
  filtered = base.filter(i =>
    (!f.tier || rankInfo(i).key === f.tier) &&
    (!showSub || !f.sub || weaponSubtype(i.type) === f.sub));
  // Equippable first when searching, then tier, level, name.
  filtered.sort((a, b) =>
    (EQUIP_GROUPS.has(typeGroup(b.type)) - EQUIP_GROUPS.has(typeGroup(a.type))) ||
    tierIndex(a) - tierIndex(b) || (b.level || 0) - (a.level || 0) || a.name.localeCompare(b.name));

  el('pkTabs').innerHTML = opts.tabs.map(tb => {
    const active = !f.q && f.tab === tb.key;
    return `<button type="button" role="tab" class="pk-tab" data-tab="${tb.key}" aria-selected="${active}">${slotIcon(tb.icon, 15)}<span>${esc(tb.label())}</span></button>`;
  }).join('');

  // Chips: weapon subtypes + tiers, with counts from the base list.
  const tierCount = k => base.filter(i => rankInfo(i).key === k && (!showSub || !f.sub || weaponSubtype(i.type) === f.sub)).length;
  const subCount = k => base.filter(i => weaponSubtype(i.type) === k && (!f.tier || rankInfo(i).key === f.tier)).length;
  el('pkFilters').innerHTML =
    (showSub ? `<div class="pk-chiprow">${SUBTYPES.map(k => {
      const n = subCount(k);
      return `<button type="button" class="idb-chip" data-sub="${k}" aria-pressed="${f.sub === k}" ${n ? '' : 'disabled'}>${esc(getTypeName(SUBTYPE_LABEL[k]))}<span>${n}</span></button>`;
    }).join('')}</div>` : '') +
    `<div class="pk-chiprow">${TIER_FILTERS.map(k => {
      const n = tierCount(k);
      return `<button type="button" class="idb-chip idb-tierchip ${TIERS[k].css}" data-tier="${k}" aria-pressed="${f.tier === k}" ${n ? '' : 'disabled'}><i></i>${TIERS[k].label}<span>${n}</span></button>`;
    }).join('')}</div>`;

  const current = opts.current?.() || new Set();
  el('pickerGrid').innerHTML = filtered.length
    ? filtered.map((it, i) => rowHtml(it, i, current.has(it.name))).join('')
    : `<div class="picker-empty">${f.q ? t('picker.noMatch') : t('items.empty')}</div>`;
  el('pickerCount').textContent = `${filtered.length} ${t('picker.items')}`;
  hideItemTooltip();
  if (keepCursor) return setCursor(Math.min(cursor, filtered.length - 1), false);
  // Start the cursor on the current item if it's visible.
  const eq = filtered.findIndex(it => current.has(it.name));
  setCursor(eq >= 0 ? eq : 0, eq >= 0);
}

function rowHtml(item, i, isCurrent) {
  const ri = rankInfo(item);
  const stats = numericStats(item).slice(0, 4).map(([k, v]) => {
    const aff = AFFINITY_ELEMENT[k] ? ` is-affinity affinity-${AFFINITY_ELEMENT[k]}` : '';
    return `<span class="idb-stat${aff}"><b>${formatStat(k, v)}</b> ${esc(STAT_SHORT[k] || k)}</span>`;
  }).join('');
  return `<div class="pk-row ${ri.css}${isCurrent ? ' equipped' : ''}" role="option" data-idx="${i}" data-name="${esc(item.name)}">
    ${iconHtml(item.name, 'idb-icon')}
    <span class="idb-main">
      <span class="idb-name">${esc(localizedItemName(item))}</span>
      <span class="idb-type">${esc(getTypeName(item.type || ''))}${item.level ? ` · ${t('items.lv')} ${item.level}` : ''}</span>
    </span>
    <span class="idb-stats">${stats}</span>
    <span class="pk-right">${isCurrent ? `<span class="pk-equipped">${esc(opts.currentLabel)}</span>` : `<span class="idb-tier">${esc(ri.label)}</span>`}</span>
  </div>`;
}

function pick(i) {
  const item = filtered[i];
  if (!item) return;
  // onPick returns true to keep the picker open (e.g. tracking several items).
  if (opts.onPick(item)) refresh(true);
  else closePicker();
}

/**
 * @param {object} o
 * @param {string} o.title
 * @param {string} [o.titleIcon]  slot icon key
 * @param {{text: string, cls: string}} [o.pill]
 * @param {Array} o.tabs          tab defs (EQUIP_TABS, MATERIAL_TAB, ALL_TAB)
 * @param {string} o.tab          initial tab key
 * @param {boolean} [o.allItems]  "All" tab includes non-equipment
 * @param {() => Set<string>} [o.current]  names to mark as current
 * @param {string} [o.currentLabel]
 * @param {(item) => boolean|void} o.onPick
 */
export async function openItemPicker(o) {
  opts = o;
  items = await loadItems();
  if (!built) buildModal();

  f.tab = o.tab;
  f.q = '';
  f.sub = '';
  el('pickerSearch').value = '';
  el('pickerSearch').placeholder = t('picker.search');
  el('pkTitleIcon').innerHTML = o.titleIcon ? slotIcon(o.titleIcon, 18) : '';
  el('pickerTitle').textContent = o.title;
  const pill = el('pickerModePill');
  pill.textContent = o.pill?.text || '';
  pill.className = 'pk-mode ' + (o.pill?.cls || '');
  pill.hidden = !o.pill;

  refresh();
  el('pickerOverlay').classList.add('show');
  // Don't pop the keyboard on touch devices.
  if (window.matchMedia('(hover: hover)').matches) setTimeout(() => el('pickerSearch').focus(), 30);
}

export function isPickerOpen() {
  return !!el('pickerOverlay')?.classList.contains('show');
}

export function closePicker() {
  el('pickerOverlay')?.classList.remove('show');
  hideItemTooltip();
  opts?.onClose?.();
}
