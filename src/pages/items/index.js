import { esc } from '../../ui/escape.js';
import { t, getLocale, getTypeName } from '../../i18n.js';
import { translateItemName } from '../../data/translate.js';
import { showToast } from '../../ui/toast.js';
import { hideItemTooltip } from '../../ui/tooltip.js';
import { iconHtml, bindItemHover } from '../../ui/itemUi.js';
import { appendPatchHistory } from '../../ui/patchHistory.js';
import { isPinned, togglePin, onPinsChange, COMPARE_MAX } from '../../data/compare.js';
import { getActiveProfile, isTrackedInActiveProfile, toggleTrackedInActiveProfile } from '../tracker/storage.js';
import {
  loadItems, getItem, getUsedIn, iconSrc, rankInfo, tierIndex, typeGroup, weaponSubtype,
  numericStats, formatStat, formatDropRate, dropRateFor, STAT_LABELS, STAT_SHORT, AFFINITY_ELEMENT,
  localizedItemName, localizedNameByName, TIERS,
} from '../../data/items.js';

// ── Filter definitions ───────────────────────────────────────────────────────
const TYPE_FILTERS = [
  { key: '',          label: () => t('items.all') },
  { key: 'weapon',    label: () => getTypeName('Weapon') },
  { key: 'headwear',  label: () => getTypeName('Headwear') },
  { key: 'armor',     label: () => getTypeName('Armor') },
  { key: 'wings',     label: () => getTypeName('Wings') },
  { key: 'accessory', label: () => getTypeName('Accessory') },
  { key: 'material',  label: () => getTypeName('Material') },
  { key: 'other',     label: () => t('items.other') },
];

const WEAPON_SUBTYPES = [
  { key: '',       label: () => t('items.all') },
  { key: 'melee',  label: () => getTypeName('Melee') },
  { key: 'bow',    label: () => getTypeName('Bow') },
  { key: 'gun',    label: () => getTypeName('Gun') },
  { key: 'staff',  label: () => getTypeName('Staff') },
  { key: 'bag',    label: () => getTypeName('Bag') },
  { key: 'shared', label: () => getTypeName('Shared') },
];

const TIER_FILTERS = ['arcana', 'alteia', 'gnosis', 'neptinos', 'deltirama', 'rare', 'magic'];

const SORTS = [
  { key: 'tier',  label: () => t('items.sortTier') },
  { key: 'level', label: () => t('items.sortLevel') },
  { key: 'name',  label: () => t('items.sortName') },
  { key: 'stat',  label: () => t('items.sortStat') },
];

const DEFAULTS = { q: '', type: '', sub: '', rank: '', stat: '', sort: 'tier', view: 'list' };
const VIEW_KEY = 'itemsView';
const SCROLL_KEY = 'itemsScroll';

// ── Helpers ──────────────────────────────────────────────────────────────────
function itemHref(name) {
  return `#/items/${encodeURIComponent(name)}`;
}

// Adds the item to the Item Tracker's active profile.
function trackBtn(name) {
  const on = isTrackedInActiveProfile(name);
  const profile = getActiveProfile();
  const title = profile ? t(on ? 'trk.untrackHintProfile' : 'trk.trackHintProfile', { name: profile.name }) : t('trk.trackHint');
  return `<button type="button" class="idb-pin idb-track" data-track="${esc(name)}" aria-pressed="${on}" title="${esc(title)}"><span>${t(on ? 'trk.tracking' : 'trk.track')}</span></button>`;
}

function pinBtn(name, withLabel = false) {
  const on = isPinned(name);
  return `<button type="button" class="idb-pin" data-pin="${esc(name)}" aria-pressed="${on}" title="${esc(t('compare.toggle'))}">${withLabel ? `<span>${t(on ? 'compare.pinned' : 'compare.pin')}</span>` : ''}</button>`;
}

// Toggle a pin from any [data-pin] button; returns true if the click was handled.
function handlePinClick(e) {
  const btn = e.target.closest('[data-pin]');
  if (!btn) return false;
  e.preventDefault();
  e.stopPropagation();
  if (!togglePin(btn.dataset.pin)) showToast(t('compare.full', { n: COMPARE_MAX }));
  return true;
}

// Reflect pin state on visible buttons without re-rendering the list.
function syncPinButtons(root) {
  root.querySelectorAll('[data-pin]').forEach(b => {
    const on = isPinned(b.dataset.pin);
    b.setAttribute('aria-pressed', on);
    const label = b.querySelector('span');
    if (label) label.textContent = t(on ? 'compare.pinned' : 'compare.pin');
  });
}

// Per-locale search haystacks, built once.
const hayCache = new Map();
function hay(item) {
  const loc = getLocale();
  let h = hayCache.get(item);
  if (!h || h.loc !== loc) {
    const names = [item.name, item.koreanname || ''];
    if (loc === 'zh') names.push(translateItemName(item.name, 'zh'));
    const fx = [item.description, ...(item.stats?.passive || []), ...(item.stats?.active || [])].filter(Boolean).join(' ');
    h = { loc, name: names.join(' ').toLowerCase(), fx: fx.toLowerCase() };
    hayCache.set(item, h);
  }
  return h;
}

// ── Filtering / sorting ──────────────────────────────────────────────────────
// `skip` lets facet counts ignore their own dimension (e.g. type tab counts).
function matches(item, s, terms, skip) {
  if (skip !== 'type' && s.type && typeGroup(item.type) !== s.type) return -1;
  if (skip !== 'type' && s.type === 'weapon' && s.sub && weaponSubtype(item.type) !== s.sub) return -1;
  if (skip !== 'rank' && s.rank && rankInfo(item).key !== s.rank) return -1;
  if (s.stat && typeof item.stats?.[s.stat] !== 'number') return -1;
  if (!terms.length) return 0;
  const h = hay(item);
  if (terms.every(x => h.name.includes(x))) return 0;
  // Effect-text matches (e.g. "lifesteal") rank after name matches.
  if (terms.join(' ').length >= 3 && terms.every(x => h.fx.includes(x))) return 1;
  return -1;
}

function filterItems(items, s) {
  const terms = s.q.toLowerCase().trim().split(/\s+/).filter(Boolean);
  const out = [];
  for (const it of items) {
    const hit = matches(it, s, terms);
    if (hit >= 0) out.push({ it, hit });
  }
  const byName = (a, b) => a.it.name.localeCompare(b.it.name);
  const byTier = (a, b) => tierIndex(a.it) - tierIndex(b.it);
  const byLevel = (a, b) => (b.it.level || 0) - (a.it.level || 0);
  const byStat = (a, b) => (b.it.stats?.[s.stat] || 0) - (a.it.stats?.[s.stat] || 0);
  const chain = {
    tier:  [byTier, byLevel, byName],
    level: [byLevel, byTier, byName],
    name:  [(a, b) => localizedItemName(a.it).localeCompare(localizedItemName(b.it))],
    stat:  s.stat ? [byStat, byTier, byName] : [byTier, byLevel, byName],
  }[s.sort] || [byTier, byLevel, byName];
  out.sort((a, b) => {
    if (a.hit !== b.hit) return a.hit - b.hit;
    for (const fn of chain) { const d = fn(a, b); if (d) return d; }
    return 0;
  });
  return out.map(x => x.it);
}

function facetCounts(items, s, dim, keyFn) {
  const terms = s.q.toLowerCase().trim().split(/\s+/).filter(Boolean);
  const counts = new Map();
  let total = 0;
  for (const it of items) {
    if (matches(it, s, terms, dim) < 0) continue;
    total++;
    const k = keyFn(it);
    counts.set(k, (counts.get(k) || 0) + 1);
  }
  counts.set('', total);
  return counts;
}

// ── List view ────────────────────────────────────────────────────────────────
function statsSummary(item, s, max) {
  let stats = numericStats(item);
  if (s.stat) stats = [...stats.filter(([k]) => k === s.stat), ...stats.filter(([k]) => k !== s.stat)];
  const shown = stats.slice(0, max);
  const more = stats.length - shown.length;
  return shown.map(([k, v]) => {
    const aff = AFFINITY_ELEMENT[k] ? ` is-affinity affinity-${AFFINITY_ELEMENT[k]}` : '';
    return `<span class="idb-stat${k === s.stat ? ' hl' : ''}${aff}"><b>${formatStat(k, v)}</b> ${esc(STAT_SHORT[k] || k)}</span>`;
  }).join('') + (more > 0 ? `<span class="idb-more">+${more}</span>` : '');
}

function rowHtml(item, s) {
  const ri = rankInfo(item);
  const hasFx = item.stats?.passive?.length || item.stats?.active?.length;
  return `<a class="idb-row ${ri.css}" href="${itemHref(item.name)}" data-name="${esc(item.name)}">
    ${iconHtml(item.name, 'idb-icon')}
    <span class="idb-main">
      <span class="idb-name">${esc(localizedItemName(item))}</span>
      <span class="idb-type">${esc(getTypeName(item.type || ''))}</span>
    </span>
    <span class="idb-stats">${statsSummary(item, s, 4)}${hasFx ? `<span class="idb-fx" title="${esc(t('items.passive'))} / ${esc(t('items.active'))}">${item.stats?.active?.length ? t('items.active') : t('items.passive')}</span>` : ''}</span>
    <span class="idb-lv">${item.level ? item.level : ''}</span>
    <span class="idb-tier">${esc(ri.label)}</span>
    ${pinBtn(item.name)}
  </a>`;
}

function tileHtml(item) {
  const ri = rankInfo(item);
  return `<a class="idb-tile ${ri.css}" href="${itemHref(item.name)}" data-name="${esc(item.name)}">
    ${iconHtml(item.name, 'idb-tile-icon')}
    <span class="idb-tile-name">${esc(localizedItemName(item))}</span>
  </a>`;
}

const ICON_LIST = '<svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor" aria-hidden="true"><rect x="1" y="2" width="14" height="2.5" rx=".5"/><rect x="1" y="6.75" width="14" height="2.5" rx=".5"/><rect x="1" y="11.5" width="14" height="2.5" rx=".5"/></svg>';
const ICON_GRID = '<svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor" aria-hidden="true"><rect x="1" y="1" width="6" height="6" rx=".5"/><rect x="9" y="1" width="6" height="6" rx=".5"/><rect x="1" y="9" width="6" height="6" rx=".5"/><rect x="9" y="9" width="6" height="6" rx=".5"/></svg>';

function renderShell(s, statKeys) {
  return `
    <div class="page-header">
      <h1>${t('items.title')}</h1>
      <p class="page-subtitle">${t('items.subtitle')}</p>
    </div>
    <div class="idb-toolbar">
      <label class="idb-search">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/></svg>
        <input type="search" id="idbSearch" placeholder="${esc(t('items.search'))}" value="${esc(s.q)}" autocomplete="off" spellcheck="false">
        <kbd>/</kbd>
      </label>
      <label class="idb-select">
        <span>${t('items.stat')}</span>
        <select data-k="stat">
          <option value="">${t('items.anyStat')}</option>
          ${statKeys.map(k => `<option value="${k}" ${s.stat === k ? 'selected' : ''}>${esc(STAT_LABELS[k] || k)}</option>`).join('')}
        </select>
      </label>
      <label class="idb-select">
        <span>${t('items.sort')}</span>
        <select data-k="sort">
          ${SORTS.map(o => `<option value="${o.key}" ${s.sort === o.key ? 'selected' : ''} ${o.key === 'stat' && !s.stat ? 'hidden' : ''}>${o.label()}</option>`).join('')}
        </select>
      </label>
      <div class="idb-seg" role="group" aria-label="View">
        <button type="button" data-k="view" data-v="list" aria-pressed="${s.view === 'list'}" title="${t('items.viewList')}">${ICON_LIST}</button>
        <button type="button" data-k="view" data-v="grid" aria-pressed="${s.view === 'grid'}" title="${t('items.viewGrid')}">${ICON_GRID}</button>
      </div>
    </div>
    <div class="idb-facets" id="idbFacets"></div>
    <div class="idb-meta" id="idbMeta"></div>
    <div id="idbList"></div>
  `;
}

function renderFacets(items, s) {
  const typeCounts = facetCounts(items, { ...s, sub: '' }, 'type', it => typeGroup(it.type));
  const tierCounts = facetCounts(items, s, 'rank', it => rankInfo(it).key);
  const tabs = TYPE_FILTERS.map(f => {
    const n = typeCounts.get(f.key) || 0;
    return `<button type="button" class="idb-tab" data-k="type" data-v="${f.key}" aria-pressed="${s.type === f.key}" ${n ? '' : 'disabled'}>${esc(f.label())}<span>${n}</span></button>`;
  }).join('');
  let subRow = '';
  if (s.type === 'weapon') {
    const subCounts = facetCounts(items, { ...s, type: 'weapon', sub: '' }, null, it => weaponSubtype(it.type));
    subRow = `<div class="idb-subtabs">${WEAPON_SUBTYPES.map(f => {
      const n = subCounts.get(f.key) || 0;
      return `<button type="button" class="idb-chip" data-k="sub" data-v="${f.key}" aria-pressed="${s.sub === f.key}" ${n ? '' : 'disabled'}>${esc(f.label())}<span>${n}</span></button>`;
    }).join('')}</div>`;
  }
  const tiers = TIER_FILTERS.map(k => {
    const n = tierCounts.get(k) || 0;
    const ti = TIERS[k];
    return `<button type="button" class="idb-chip idb-tierchip ${ti.css}" data-k="rank" data-v="${k}" aria-pressed="${s.rank === k}" ${n ? '' : 'disabled'}><i></i>${ti.label}<span>${n}</span></button>`;
  }).join('');
  return `<div class="idb-tabs">${tabs}</div>${subRow}<div class="idb-tiers">${tiers}</div>`;
}

// Rendering all 809 rows in one go costs ~0.5s of layout; the first screenful is
// rendered synchronously and the rest is appended over the next few frames.
const FIRST_CHUNK = 60;
const NEXT_CHUNK = 200;
let renderToken = 0;

function renderList(el, list, s, onDone) {
  const token = ++renderToken;
  if (!list.length) {
    el.innerHTML = `<div class="idb-empty">${t('items.empty')} <button type="button" class="idb-link" data-k="clear">${t('items.clear')}</button></div>`;
    onDone?.();
    return;
  }
  const grid = s.view === 'grid';
  const html = grid ? tileHtml : it => rowHtml(it, s);
  el.innerHTML = `<div class="${grid ? 'idb-grid' : 'idb-list'}">${list.slice(0, FIRST_CHUNK).map(html).join('')}</div>`;
  const box = el.firstElementChild;
  let i = FIRST_CHUNK;
  const step = () => {
    if (token !== renderToken || !box.isConnected) return; // superseded by a newer render
    if (i >= list.length) { onDone?.(); return; }
    box.insertAdjacentHTML('beforeend', list.slice(i, i + NEXT_CHUNK).map(html).join(''));
    i += NEXT_CHUNK;
    requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

// ── Detail view ──────────────────────────────────────────────────────────────
let bossData = null;
async function loadBossData() {
  if (bossData) return;
  try {
    const r = await fetch('data/bosses.json');
    if (r.ok) bossData = await r.json();
  } catch (e) {}
  if (!bossData) bossData = [];
}

const BOSS_CATEGORY_LABELS = {
  'Creep': 'Creep', 'Field': 'Field', 'Minor': 'Deltirama',
  'Coins': 'Neptinos', 'High': 'Gnosis', 'Late': 'Alteia', 'Endgame': 'Arcana',
};
const BOSS_CATEGORY_CSS = {
  'Creep': 'creep', 'Field': 'field', 'Minor': 'deltirama',
  'Coins': 'neptinos', 'High': 'gnosis', 'Late': 'alteia', 'Endgame': 'arcana',
};

function byTierThenName(a, b) {
  const d = tierIndex(getItem(a)) - tierIndex(getItem(b));
  return d || a.localeCompare(b);
}

function chipHtml(name, qty = 0) {
  const ri = rankInfo(getItem(name));
  return `<a href="${itemHref(name)}" class="idb-chiplink ${ri.css}" data-name="${esc(name)}">
    ${iconHtml(name, 'idb-chip-icon')}
    <span class="idb-chiplink-name">${esc(localizedNameByName(name))}</span>
    ${qty > 1 ? `<span class="idb-qty">×${qty}</span>` : ''}
  </a>`;
}

function sortSlots(recipe) {
  return [...recipe].sort((a, b) => byTierThenName(Object.keys(a)[0], Object.keys(b)[0]));
}

// Collapsible crafting tree. Each ingredient with its own recipe can be expanded.
function recipeNodeHtml(name, qty, ancestors) {
  const it = getItem(name);
  const row = chipHtml(name, qty);
  if (!it?.recipe?.length || ancestors.has(name)) return `<li class="rt-leaf">${row}</li>`;
  const next = new Set(ancestors).add(name);
  return `<li><details><summary>${row}</summary><ul>${recipeSlotsHtml(it.recipe, next)}</ul></details></li>`;
}

function recipeSlotsHtml(recipe, ancestors) {
  return sortSlots(recipe).map(slot => {
    const entries = Object.entries(slot);
    if (entries.length === 1) return recipeNodeHtml(entries[0][0], entries[0][1], ancestors);
    return `<li class="rt-alt"><span class="rt-alt-label">${t('items.or')}</span><ul>${entries.map(([n, q]) => recipeNodeHtml(n, q, ancestors)).join('')}</ul></li>`;
  }).join('');
}

function section(title, body, extraCls = '') {
  return `<section class="idb-section ${extraCls}"><h2>${title}</h2>${body}</section>`;
}

function renderDetail(item, items) {
  const ri = rankInfo(item);
  const loc = getLocale();
  const title = localizedItemName(item);
  const subtitle = loc === 'en' ? item.koreanname : item.name;

  const stats = numericStats(item);
  const statsHtml = stats.length ? `<dl class="idb-statlist">${stats.map(([k, v]) => {
    const aff = AFFINITY_ELEMENT[k] ? ` is-affinity affinity-${AFFINITY_ELEMENT[k]}` : '';
    return `<div class="idb-statrow${aff}"><dt>${esc(STAT_LABELS[k] || k)}</dt><dd>${formatStat(k, v)}</dd></div>`;
  }).join('')}</dl>` : '';

  const fxBlock = (label, lines, cls) => lines?.length
    ? `<div class="idb-fxblock ${cls}"><div class="idb-fxlabel">${label}</div>${lines.map(l => `<p>${esc(l)}</p>`).join('')}</div>` : '';

  let specHtml = '';
  if (item.stats?.spec?.length > 1) {
    const text = item.stats.spec[1];
    const m = text.match(/^([^-:]+?)\s+-\s+(.*)$/);
    specHtml = `<div class="idb-fxblock fx-spec"><div class="idb-fxlabel">${t('items.spec')}</div><p>${m ? `<strong>${esc(m[1])}</strong> — ${esc(m[2])}` : esc(text)}</p></div>`;
  }

  const notesHtml = item.notes?.length ? `<div class="idb-notes">${item.notes.map(n => `<p>${esc(n)}</p>`).join('')}</div>` : '';

  // ── Acquisition column ──
  const parts = [];
  if (item.dropped_by?.length) {
    parts.push(section(t('items.dropsFrom'), `<div class="idb-drops">${item.dropped_by.map(name => {
      const boss = bossData.find(b => b.name === name);
      const tag = boss ? 'a' : 'div';
      const href = boss ? ` href="#/bosses/${esc(boss.id)}"` : '';
      return `<${tag} class="idb-drop"${href}>
        ${iconHtml(name + ' Icon', 'idb-drop-icon')}
        <span class="idb-drop-name">${esc(name)}</span>
        ${boss?.category ? `<span class="boss-tier-badge tier-${BOSS_CATEGORY_CSS[boss.category] || boss.category.toLowerCase()}">${esc(BOSS_CATEGORY_LABELS[boss.category] || boss.category)}</span>` : ''}
        ${dropRateFor(item, name) ? `<span class="idb-drop-rate">${formatDropRate(dropRateFor(item, name))}</span>` : ''}
      </${tag}>`;
    }).join('')}</div>`));
  }

  if (item.drops?.length) {
    parts.push(section(t('items.unleashes'), `<div class="idb-chips">${item.drops.map(n => chipHtml(n)).join('')}</div>`));
  }

  if (item.recipe?.length) {
    parts.push(section(t('items.recipe'), `<ul class="idb-tree">${recipeSlotsHtml(item.recipe, new Set([item.name]))}</ul>`));
  }

  const usedIn = getUsedIn(item, items).sort(byTierThenName);
  if (usedIn.length) {
    parts.push(section(`${t('items.usedIn')} <span class="idb-count">${usedIn.length}</span>`, `<div class="idb-chips">${usedIn.map(n => chipHtml(n)).join('')}</div>`));
  }

  const group = typeGroup(item.type);
  return `
    <nav class="idb-crumbs">
      <button type="button" class="back-btn" onclick="appBack('#/items')">${t('items.back')}</button>
      <a href="#/items">${t('items.title')}</a>
      <span>/</span>
      <a href="#/items?type=${group}">${esc(getTypeName(item.type || ''))}</a>
    </nav>
    <div class="idb-detail ${parts.length ? '' : 'single'}">
      <article class="idb-card ${ri.css}">
        <header class="idb-card-head">
          ${iconHtml(item.name, 'idb-card-icon')}
          <div class="idb-card-title">
            <h1>${esc(title)}</h1>
            ${subtitle ? `<p class="idb-altname">${esc(subtitle)}</p>` : ''}
            <p class="idb-card-meta">
              ${ri.label ? `<span class="idb-card-tier">${ri.label}</span>` : ''}
              <span>${esc(getTypeName(item.type || ''))}</span>
              ${item.level ? `<span>${t('items.lv')} ${item.level}</span>` : ''}
            </p>
          </div>
          <div class="idb-card-actions">
          ${pinBtn(item.name, true)}
          ${trackBtn(item.name)}
          ${item.id ? `<button type="button" class="idb-id" data-id="${esc(item.id)}" title="Copy @create ${esc(item.id)}">${esc(item.id)}</button>` : ''}
          </div>
        </header>
        ${item.description ? `<p class="idb-desc">${esc(item.description)}</p>` : ''}
        ${statsHtml}
        ${fxBlock(t('items.passive'), item.stats?.passive, 'fx-passive')}
        ${fxBlock(t('items.active'), item.stats?.active, 'fx-active')}
        ${specHtml}
        ${notesHtml}
      </article>
      ${parts.length ? `<div class="idb-side">${parts.join('')}</div>` : ''}
    </div>
  `;
}

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
  } catch (e) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.cssText = 'position:fixed;opacity:0;pointer-events:none';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
  }
}

// ── Page entry point ─────────────────────────────────────────────────────────
export async function initItems({ params, query }) {
  const app = document.getElementById('app');
  const [items] = await Promise.all([loadItems(), loadBossData()]);

  if (params.name) {
    const itemName = decodeURIComponent(params.name);
    const item = getItem(itemName);
    if (!item) {
      app.innerHTML = `
        <nav class="idb-crumbs"><button type="button" class="back-btn" onclick="appBack('#/items')">${t('items.back')}</button><a href="#/items">${t('items.title')}</a></nav>
        <div class="coming-soon">
          <h2>${t('items.notFound')}</h2>
          <p>${esc(t('items.notFoundBody', { name: itemName }))}</p>
        </div>`;
      return;
    }
    app.innerHTML = renderDetail(item, items);
    appendPatchHistory(app.querySelector('.idb-detail'), [item.name]);
    const onClick = async e => {
      if (handlePinClick(e)) return;
      const tb = e.target.closest('[data-track]');
      if (tb) {
        const res = toggleTrackedInActiveProfile(tb.dataset.track);
        if (!res) {
          showToast(t('trk.needProfile'));
          return;
        }
        tb.outerHTML = trackBtn(tb.dataset.track);
        showToast(t(res.tracked ? 'trk.addedTo' : 'trk.removedFrom', { name: res.profile.name }));
        return;
      }
      const btn = e.target.closest('.idb-id');
      if (!btn) return;
      const cmd = `@create ${btn.dataset.id}`;
      await copyText(cmd);
      showToast(t('items.copied', { cmd }));
    };
    app.addEventListener('click', onClick);
    const unbindHover = bindItemHover(app.querySelector('.idb-side') || app);
    const offPins = onPinsChange(() => syncPinButtons(app));
    return () => { app.removeEventListener('click', onClick); offPins(); unbindHover(); };
  }

  // ── List ──
  const s = { ...DEFAULTS, view: localStorage.getItem(VIEW_KEY) || DEFAULTS.view };
  for (const k of Object.keys(DEFAULTS)) if (query[k]) s[k] = query[k];
  if (query.search) s.q = query.search;
  if (query.highlight) s.q = query.highlight;
  if (s.stat && !query.sort) s.sort = 'stat';
  if (s.sort === 'stat' && !s.stat) s.sort = 'tier';

  const statKeys = Object.keys(STAT_LABELS).filter(k => items.some(i => typeof i.stats?.[k] === 'number'));
  app.innerHTML = renderShell(s, statKeys);

  const facetsEl = document.getElementById('idbFacets');
  const metaEl = document.getElementById('idbMeta');
  const listEl = document.getElementById('idbList');
  const searchEl = document.getElementById('idbSearch');
  const sortSel = app.querySelector('select[data-k="sort"]');

  let listHash = location.hash;
  const syncUrl = () => {
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries(s)) if (k !== 'view' && v && v !== DEFAULTS[k]) p.set(k, v);
    const qs = p.toString();
    listHash = '#/items' + (qs ? '?' + qs : '');
    history.replaceState(null, '', listHash);
  };

  let filtered = [];
  const update = ({ facets = true, onDone } = {}) => {
    filtered = filterItems(items, s);
    if (facets) facetsEl.innerHTML = renderFacets(items, s);
    const active = s.q || s.type || s.rank || s.stat;
    metaEl.innerHTML = `<span>${t('items.count', { n: filtered.length })}</span>${active ? `<button type="button" class="idb-link" data-k="clear">${t('items.clear')}</button>` : ''}`;
    renderList(listEl, filtered, s, onDone);
    hideItemTooltip();
  };

  const set = (k, v) => {
    if (k === 'clear') {
      Object.assign(s, { q: '', type: '', sub: '', rank: '', stat: '', sort: 'tier' });
      searchEl.value = '';
      sortSel.value = 'tier';
      app.querySelector('select[data-k="stat"]').value = '';
    } else if (k === 'view') {
      s.view = v;
      localStorage.setItem(VIEW_KEY, v);
      app.querySelectorAll('[data-k="view"]').forEach(b => b.setAttribute('aria-pressed', b.dataset.v === v));
    } else {
      // Toggle: clicking the active tab/chip clears it.
      s[k] = (s[k] === v && k !== 'sort' && k !== 'stat') ? '' : v;
      if (k === 'type') s.sub = '';
      if (k === 'stat') {
        // Picking a stat ranks by it; clearing falls back to tier.
        if (v) s.sort = 'stat';
        else if (s.sort === 'stat') s.sort = 'tier';
      }
    }
    sortSel.querySelector('option[value="stat"]').hidden = !s.stat;
    sortSel.value = s.sort;
    syncUrl();
    update();
  };

  const onClick = e => {
    if (handlePinClick(e)) return;
    const btn = e.target.closest('button[data-k]');
    if (btn && !btn.disabled) set(btn.dataset.k, btn.dataset.v ?? '');
  };
  const onChange = e => {
    const sel = e.target.closest('select[data-k]');
    if (sel) set(sel.dataset.k, sel.value);
  };
  app.addEventListener('click', onClick);
  app.addEventListener('change', onChange);
  const offPins = onPinsChange(() => syncPinButtons(listEl));

  let raf = 0;
  searchEl.addEventListener('input', () => {
    s.q = searchEl.value;
    cancelAnimationFrame(raf);
    raf = requestAnimationFrame(() => { syncUrl(); update(); });
  });
  searchEl.addEventListener('keydown', e => {
    if (e.key === 'Enter' && filtered.length) {
      location.hash = itemHref(filtered[0].name);
    } else if (e.key === 'Escape' && searchEl.value) {
      e.preventDefault();
      searchEl.value = '';
      s.q = '';
      syncUrl();
      update();
    }
  });

  const onKey = e => {
    if (e.key !== '/' || e.ctrlKey || e.metaKey) return;
    const tag = document.activeElement?.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
    e.preventDefault();
    searchEl.focus();
    searchEl.select();
  };
  document.addEventListener('keydown', onKey);

  const unbindHover = bindItemHover(listEl);
  const saved = JSON.parse(sessionStorage.getItem(SCROLL_KEY) || 'null');
  update({ onDone: () => { if (saved && saved.hash === listHash) window.scrollTo(0, saved.y); } });


  return function cleanup() {
    sessionStorage.setItem(SCROLL_KEY, JSON.stringify({ hash: listHash, y: window.scrollY }));
    document.removeEventListener('keydown', onKey);
    app.removeEventListener('click', onClick);
    app.removeEventListener('change', onChange);
    offPins();
    unbindHover();
  };
}
