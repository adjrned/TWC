import { esc } from '../../ui/escape.js';
import { t, tf, getTypeName } from '../../i18n.js';
import { loadItems, iconSrc as itemIconSrc, getItem, rankInfo, tierIndex, localizedItemName, dropRateFor } from '../../data/items.js';
import { iconHtml, bindItemHover } from '../../ui/itemUi.js';
import { hideItemTooltip } from '../../ui/tooltip.js';
import { appendPatchHistory } from '../../ui/patchHistory.js';

let bossData = null;
let itemData = null;

async function loadBossData() {
  if (bossData) return bossData;
  try {
    const [br, items] = await Promise.all([
      fetch('data/bosses.json'),
      loadItems(),
    ]);
    if (br.ok) bossData = await br.json();
    itemData = items;
  } catch (e) {}
  if (!bossData) bossData = [];
  if (!itemData) itemData = [];
  return bossData;
}


// Display labels using rarity tier names
const CATEGORY_LABELS = {
  'Creep':   'Creep',
  'Field':   'Field',
  'Minor':   'Deltirama',
  'Coins':   'Neptinos',
  'High':    'Gnosis',
  'Late':    'Alteia',
  'Endgame': 'Arcana',
};

// Creep / Field are translated; the tier names (Arcana, Gnosis…) are proper nouns.
function catLabel(cat) {
  return tf('bosses.cat.' + cat, CATEGORY_LABELS[cat] || cat || '');
}

function typeLabel(type) {
  return type ? tf('bosses.type.' + type, type) : '';
}

function iconSrc(name) {
  return itemIconSrc(name + ' Icon');
}

// ── Stat label mapping ────────────────────────────────────────────────────────
const STAT_LABELS = {
  health:       'Health',
  healthRegen:  'HP Regen',
  mana:         'Mana',
  manaRegen:    'Mana Regen',
  armor:        'Armor',
  armorType:    'Armor Type',
  magicResist:  'Magic Resist',
  damageResist: 'Damage Resist',
  attackDamage: 'Attack Damage',
  attackSpread: 'Attack Spread',
  attackRange:  'Attack Range',
  attackSpeed:  'Attack Speed',
  moveSpeed:    'Move Speed',
};

// "30000000" → "30,000,000", ".5" → "0.5"; non-numeric strings pass through.
function fmtNum(v) {
  const s = String(v).trim();
  if (!/^-?\d*\.?\d+$/.test(s)) return s;
  return Number(s).toLocaleString('en-US', { maximumFractionDigits: 3 });
}

// Compact HP for list rows: 30000000 → "30M".
function fmtShort(v) {
  const n = Number(v);
  if (!isFinite(n) || !String(v ?? '').trim()) return '';
  if (n >= 1e6) return parseFloat((n / 1e6).toFixed(1)) + 'M';
  if (n >= 1e3) return parseFloat((n / 1e3).toFixed(1)) + 'K';
  return String(n);
}

function renderStatTable(stats) {
  if (!stats) return '';
  const rows = Object.entries(stats)
    .filter(([, v]) => v !== '' && v !== null && v !== undefined)
    .map(([k, v]) => `<div class="mdb-statrow"><dt>${esc(tf('bstat.' + k, STAT_LABELS[k] || k))}</dt><dd>${esc(fmtNum(v))}</dd></div>`)
    .join('');
  return `<dl class="mdb-stats">${rows}</dl>`;
}

// ── List view ─────────────────────────────────────────────────────────────────
// Highest tier first, matching the item database.
const CATEGORY_ORDER = ['Endgame', 'Late', 'High', 'Coins', 'Minor', 'Field', 'Creep'];
const TIER_CSS = {
  Endgame: 'rarity-arcana', Late: 'rarity-alteia', High: 'rarity-gnosis', Coins: 'rarity-neptinos',
  Minor: 'rarity-deltirama', Field: 'mtier-field', Creep: 'mtier-creep',
};

const SORTS = [
  { key: 'tier',   label: () => t('items.sortTier') },
  { key: 'level',  label: () => t('items.sortLevel') },
  { key: 'health', label: () => t('bosses.sortHealth') },
  { key: 'name',   label: () => t('items.sortName') },
];

let dropsByBoss = null;
function bossDrops(name) {
  if (!dropsByBoss) {
    dropsByBoss = new Map();
    for (const it of itemData) {
      for (const b of it.dropped_by || []) {
        if (!dropsByBoss.has(b)) dropsByBoss.set(b, []);
        dropsByBoss.get(b).push(it);
      }
    }
    for (const list of dropsByBoss.values()) list.sort((a, b) => tierIndex(a) - tierIndex(b) || a.name.localeCompare(b.name));
  }
  return dropsByBoss.get(name) || [];
}

function filterBosses(bosses, s, ignoreCat = false) {
  const q = s.q.toLowerCase().trim();
  const out = bosses.filter(b =>
    (ignoreCat || !s.cat || b.category === s.cat) &&
    (!q || b.name.toLowerCase().includes(q) || (b.location || '').toLowerCase().includes(q) ||
      bossDrops(b.name).some(i => i.name.toLowerCase().includes(q))));
  const tier = b => CATEGORY_ORDER.indexOf(b.category);
  const num = v => Number(v) || 0;
  const by = {
    tier:   (a, b) => tier(a) - tier(b) || num(b.level) - num(a.level) || a.name.localeCompare(b.name),
    level:  (a, b) => num(b.level) - num(a.level) || a.name.localeCompare(b.name),
    health: (a, b) => num(b.stats?.health) - num(a.stats?.health) || a.name.localeCompare(b.name),
    name:   (a, b) => a.name.localeCompare(b.name),
  }[s.sort] || ((a, b) => tier(a) - tier(b));
  return out.sort(by);
}

function bossRowHtml(boss) {
  const drops = bossDrops(boss.name);
  const shown = drops.slice(0, 6);
  return `<a href="#/bosses/${esc(boss.id)}" class="mdb-row ${TIER_CSS[boss.category] || ''}">
    ${iconHtml(boss.name, 'idb-icon', iconSrc(boss.name))}
    <span class="idb-main">
      <span class="idb-name">${esc(boss.name)}${boss.name === 'Arcane Lord' ? ' <span class="nav-wip">WIP</span>' : ''}</span>
      <span class="idb-type">${esc(boss.location || '')}</span>
    </span>
    <span class="mdb-kind">${esc(typeLabel(boss.type))}</span>
    <span class="idb-lv">${boss.level ? esc(boss.level) : ''}</span>
    <span class="mdb-hp" title="${esc(fmtNum(boss.stats?.health || ''))}">${esc(fmtShort(boss.stats?.health))}</span>
    <span class="mdb-drops">${shown.map(i => `<span class="mdb-dropicon ${rankInfo(i).css}" data-name="${esc(i.name)}">${iconHtml(i.name, 'idb-chip-icon')}</span>`).join('')}${drops.length > shown.length ? `<span class="idb-more">+${drops.length - shown.length}</span>` : ''}</span>
    <span class="idb-tier">${esc(catLabel(boss.category))}</span>
  </a>`;
}

function renderBossShell(s) {
  return `
    <div class="page-header">
      <h1>${t('bosses.title')}</h1>
      <p class="page-subtitle">${t('bosses.subtitle')}</p>
    </div>
    <div class="idb-toolbar">
      <label class="idb-search">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/></svg>
        <input type="search" id="bossSearchInput" placeholder="${esc(t('bosses.search'))}" value="${esc(s.q)}" autocomplete="off" spellcheck="false">
        <kbd>/</kbd>
      </label>
      <label class="idb-select">
        <span>${t('items.sort')}</span>
        <select data-k="sort">${SORTS.map(o => `<option value="${o.key}" ${s.sort === o.key ? 'selected' : ''}>${o.label()}</option>`).join('')}</select>
      </label>
    </div>
    <div class="idb-facets" id="bossFacets"></div>
    <div class="idb-meta" id="bossMeta"></div>
    <div id="bossList"></div>
  `;
}

function renderBossFacets(bosses, s) {
  const counts = new Map();
  const all = filterBosses(bosses, s, true);
  for (const b of all) counts.set(b.category, (counts.get(b.category) || 0) + 1);
  const tab = (key, label, n, css = '') =>
    `<button type="button" class="idb-tab ${css}" data-k="cat" data-v="${esc(key)}" aria-pressed="${s.cat === key}" ${n ? '' : 'disabled'}>${css ? '<i class="mdb-swatch"></i>' : ''}${esc(label)}<span>${n}</span></button>`;
  return `<div class="idb-tabs">${tab('', t('items.all'), all.length)}${CATEGORY_ORDER.map(c => tab(c, catLabel(c), counts.get(c) || 0, TIER_CSS[c])).join('')}</div>`;
}

// ── Drop rate calculator ──────────────────────────────────────────────────────
let bossDropData = null;

async function loadBossDropData() {
  if (bossDropData) return;
  try {
    const r = await fetch('data/boss-drops.json');
    if (r.ok) bossDropData = await r.json();
  } catch(e) {}
  if (!bossDropData) bossDropData = {};
}

const NO_WISH_BOSSES = new Set(['Styrix, the Harvester of Souls', 'Lightbringer Kamael', 'Arcane Lord']);

const PLAYER_BONUS = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 47.5];

// Boss-specific player scaling rules
const BOSS_PLAYER_RULES = {
  'Styrix, the Harvester of Souls': { min: 5, max: 10, perPlayer: 20 },
  'Lightbringer Kamael': { min: 5, max: 10, perPlayer: 20 },
  'Arcane Construct': { min: 3, max: 6, perPlayer: 7.5 },
  'Arcane Lord': { min: 3, max: 6, perPlayer: 33.3 },
};
const DEFAULT_PLAYER_RULES = { min: 3, max: 10 };

// Hard mode drop bonus per boss (multiplier). Nereid/Agareth give +75%, the rest +50%.
const HARDMODE_MULT = {
  'Ifrit': 1.5,
  'Death Fiend': 1.5,
  'Lightning God Valtora': 1.5,
  'Nereid': 1.75,
  'Underlord Agareth': 1.75,
};
const HARDMODE_BOSSES = new Set(Object.keys(HARDMODE_MULT));

function getPlayerBonus(playerCount, bossName) {
  const rules = BOSS_PLAYER_RULES[bossName];
  if (rules) {
    const effectivePlayers = Math.max(0, playerCount - rules.min);
    return effectivePlayers * rules.perPlayer;
  }
  // Default: bonus starts at 3 players, +5% per player from 3 onwards
  const effectivePlayers = Math.max(0, playerCount - 2);
  return effectivePlayers * 5;
}

function isCurrencyItem(item) {
  const l = item.name.toLowerCase();
  return l.includes('soulstone') || l.includes('token') || l.includes('coin');
}

function calcDropRate(item, { wishing, hasIcon, seasonal, hardmode, playerCount, sacrifice = 0 }, bossName) {
  if (isCurrencyItem(item)) return item.base;

  const playerPct = getPlayerBonus(playerCount, bossName);
  const seasonalMult = seasonal ? 2 : 1;
  const hardmodeMult = (hardmode && HARDMODE_BOSSES.has(bossName)) ? HARDMODE_MULT[bossName] : 1;
  const sacMult = 1 + SACRIFICE_BONUSES[sacrifice];
  const combined = (1 + playerPct / 100) * seasonalMult * hardmodeMult * sacMult;

  let wishMult = 1;
  if (!NO_WISH_BOSSES.has(bossName)) {
    if (wishing && hasIcon) wishMult = item.wishIconMult;
    else if (wishing) wishMult = item.wishMult;
    else if (hasIcon) wishMult = item.iconMult;
  }

  return item.base * combined * wishMult;
}

// Drop table row shared by the calculator and the simple list.
function dropRowHtml(item, rateHtml, extraCls = '') {
  const db = getItem(item.name);
  return `<a href="#/items/${encodeURIComponent(item.name)}" class="mdb-drop ${rankInfo(db).css} ${extraCls}" data-name="${esc(item.name)}">
    ${iconHtml(item.name, 'idb-chip-icon')}
    <span class="mdb-drop-name">${esc(db ? localizedItemName(db) : item.name)}</span>
    <span class="mdb-drop-type">${esc(getTypeName(db?.type || item.type || ''))}</span>
    ${rateHtml}
  </a>`;
}

function renderDropCalculator(boss) {
  const dropInfo = bossDropData?.[boss.name];
  if (!dropInfo) return '';

  const isNoWish = NO_WISH_BOSSES.has(boss.name);
  const iconLabel = t(dropInfo.iconType === 'Immortal' ? 'bosses.iconImmortal' : 'bosses.iconLegend');
  const rules = BOSS_PLAYER_RULES[boss.name] || DEFAULT_PLAYER_RULES;
  const bossObj = bossData.find(b => b.name === boss.name);
  const showSacrifice = !isNoWish && bossObj && ['Late', 'Endgame'].includes(bossObj.category);

  return `
    <section class="boss-section">
      <h2>${t('bosses.dropRates')}</h2>
      <div class="mdb-calc">
        ${!isNoWish ? `
          <label class="mdb-check"><input type="checkbox" id="calcWish"><span>${t('bosses.wish')}</span></label>
          <label class="mdb-check"><input type="checkbox" id="calcIcon"><span>${t('bosses.iconBonus', { type: iconLabel })}</span></label>
        ` : ''}
        ${HARDMODE_BOSSES.has(boss.name) ? `
          <label class="mdb-check"><input type="checkbox" id="calcHardmode"><span>${t('bosses.hardMode', { n: Math.round((HARDMODE_MULT[boss.name] - 1) * 100) })}</span></label>
        ` : ''}
        <label class="mdb-check"><input type="checkbox" id="calcSeasonal"><span>${t('bosses.seasonal')}</span></label>
        <label class="mdb-range">
          <span>${t('bosses.party')}</span>
          <input type="range" id="calcPlayers" min="${rules.min}" max="${rules.max}" value="${rules.min}">
          <b id="calcPlayersVal">${rules.min}</b>
        </label>
        ${showSacrifice ? `
        <label class="mdb-range">
          <span>${t('bosses.sacrifice')}</span>
          <input type="range" id="calcSacrifice" min="0" max="3" step="1" value="0">
          <b id="calcSacrificeVal">0%</b>
        </label>` : ''}
      </div>
      <div class="mdb-droplist" id="dropCalcList">
        ${dropInfo.items.map((item, i) => {
          const rate = calcDropRate(item, { wishing: false, hasIcon: false, seasonal: false, hardmode: false, playerCount: rules.min }, boss.name);
          return dropRowHtml(item, `<span class="boss-drop-rate" data-idx="${i}">${rate.toFixed(4)}%</span>`);
        }).join('')}
      </div>
    </section>
  `;
}

function initDropCalc(boss) {
  const dropInfo = bossDropData?.[boss.name];
  if (!dropInfo) return;

  const isNoWish = NO_WISH_BOSSES.has(boss.name);
  const update = () => {
    const wishing = !isNoWish && document.getElementById('calcWish')?.checked;
    const hasIcon = !isNoWish && document.getElementById('calcIcon')?.checked;
    const hardmode = document.getElementById('calcHardmode')?.checked || false;
    const seasonal = document.getElementById('calcSeasonal')?.checked;
    const playerCount = parseInt(document.getElementById('calcPlayers')?.value || '1');
    const sacrifice = parseInt(document.getElementById('calcSacrifice')?.value || '0');
    document.getElementById('calcPlayersVal').textContent = playerCount;
    const sacValEl = document.getElementById('calcSacrificeVal');
    if (sacValEl) {
      const sacBonus = SACRIFICE_BONUSES[sacrifice];
      sacValEl.textContent = sacBonus ? `+${Math.round(sacBonus * 100)}%` : '0%';
    }

    const rates = document.querySelectorAll('#dropCalcList .boss-drop-rate');
    rates.forEach(el => {
      const idx = parseInt(el.dataset.idx);
      const item = dropInfo.items[idx];
      if (!item) return;
      const calc = calcDropRate(item, { wishing, hasIcon, seasonal, hardmode, playerCount, sacrifice }, boss.name);
      el.textContent = calc.toFixed(4) + '%';
    });
  };

  ['calcWish', 'calcIcon', 'calcHardmode', 'calcSeasonal', 'calcPlayers', 'calcSacrifice'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.addEventListener('input', update);
  });
}

// ── Simple drops list (for bosses without calculator data) ───────────────────
function isSpecialDrop(item) {
  return item.name.includes('Soulstone') || item.name.includes('Token');
}

const SACRIFICE_BONUSES = [0, 0.8, 1.6, 2.0];

function calcWishRate(item, boss, wishTarget, sacrifice = 0) {
  const base = dropRateFor(item, boss.name);
  if (!base || !boss.dropFormula) {
    return base ? base * (1 + SACRIFICE_BONUSES[sacrifice]) : base;
  }
  if (isSpecialDrop(item)) return base;

  const formula = boss.dropFormula;
  const drops = itemData.filter(i => (i.dropped_by || []).includes(boss.name) && !isSpecialDrop(i));
  const n = drops.length;
  const sacMult = 1 + SACRIFICE_BONUSES[sacrifice];

  if (wishTarget === item.name) {
    return base * (formula.wish || 1) * sacMult;
  } else if (boss.wishable && wishTarget) {
    if (formula.nonWishFormula === '(1/n)*1.15') {
      return base * (1 / n) * 1.15 * sacMult;
    }
    return base * (formula.nonWish || 1) * sacMult;
  }
  return base * sacMult;
}

function renderSimpleDrops(bossName, wishTarget, sacrifice = 0) {
  if (!itemData) return '';
  const boss = bossData.find(b => b.name === bossName);
  const drops = bossDrops(bossName);
  if (!drops.length) return '';

  const showWish = boss && boss.wishable;
  const showSacrifice = showWish && ['Late', 'Endgame'].includes(boss.category);
  const sacBonus = SACRIFICE_BONUSES[sacrifice];
  const sacLabel = sacBonus ? `+${Math.round(sacBonus * 100)}%` : '0%';

  return `
    <section class="boss-section">
      <h2>${t('bosses.drops')}</h2>
      ${showWish || showSacrifice ? `<div class="mdb-calc">
        ${showWish ? `
          <label class="idb-select">
            <span>${t('bosses.wish')}</span>
            <select id="wishSelect">
              <option value="">${t('bosses.none')}</option>
              ${drops.filter(i => !isSpecialDrop(i)).map(i => `<option value="${esc(i.name)}" ${wishTarget === i.name ? 'selected' : ''}>${esc(i.name)}</option>`).join('')}
            </select>
          </label>` : ''}
        ${showSacrifice ? `
          <label class="mdb-range">
            <span>${t('bosses.sacrifice')}</span>
            <input type="range" id="sacrificeSlider" min="0" max="3" step="1" value="${sacrifice}">
            <b id="sacrificeValue">${sacLabel}</b>
          </label>` : ''}
      </div>` : ''}
      <div class="mdb-droplist">
        ${drops.map(item => {
          const effectiveRate = boss ? calcWishRate(item, boss, wishTarget, sacrifice) : dropRateFor(item, bossName);
          const rate = effectiveRate ? parseFloat((effectiveRate * 100).toFixed(4)) + '%' : '';
          return dropRowHtml(item, rate ? `<span class="boss-drop-rate">${rate}</span>` : '<span></span>', wishTarget === item.name ? 'drop-wished' : '');
        }).join('')}
      </div>
    </section>
  `;
}

// ── Detail view ───────────────────────────────────────────────────────────────
function renderBossDetail(boss) {
  const hasCalcData = !!bossDropData?.[boss.name];
  const drops = hasCalcData ? renderDropCalculator(boss) : renderSimpleDrops(boss.name);
  const tierCss = TIER_CSS[boss.category] || '';

  return `
    <nav class="idb-crumbs">
      <button type="button" class="back-btn" onclick="appBack('#/bosses')">${t('items.back')}</button>
      <a href="#/bosses">${t('bosses.title')}</a>
      <span>/</span>
      <a href="#/bosses?cat=${esc(boss.category || '')}">${esc(catLabel(boss.category))}</a>
    </nav>
    <div class="idb-detail ${drops ? '' : 'single'}">
      <article class="idb-card ${tierCss}">
        <header class="idb-card-head mdb-head">
          ${iconHtml(boss.name, 'idb-card-icon', iconSrc(boss.name))}
          <div class="idb-card-title">
            <h1>${esc(boss.name)}</h1>
            <p class="idb-card-meta">
              <span class="idb-card-tier">${esc(catLabel(boss.category))}</span>
              ${boss.type ? `<span>${esc(typeLabel(boss.type))}</span>` : ''}
              ${boss.level ? `<span>${t('items.lv')} ${esc(boss.level)}</span>` : ''}
            </p>
          </div>
        </header>
        ${boss.location ? `<p class="mdb-location">${esc(boss.location)}</p>` : ''}
        ${boss.stats && Object.keys(boss.stats).length ? renderStatTable(boss.stats) : ''}
      </article>
      ${drops ? `<div class="idb-side">${drops}</div>` : ''}
    </div>
  `;
}

// ── Drops controls handler ───────────────────────────────────────────────────
function initDropsControls(boss) {
  const select = document.getElementById('wishSelect');
  const slider = document.getElementById('sacrificeSlider');

  function rerender() {
    const wishVal = select ? select.value : '';
    const sacVal = slider ? parseInt(slider.value) : 0;
    const section = document.querySelector('.boss-section');
    if (section) {
      section.outerHTML = renderSimpleDrops(boss.name, wishVal, sacVal);
      initDropsControls(boss);
    }
  }

  if (select) select.addEventListener('change', rerender);
  if (slider) {
    slider.addEventListener('input', () => {
      const val = parseInt(slider.value);
      const label = document.getElementById('sacrificeValue');
      if (label) label.textContent = SACRIFICE_BONUSES[val] ? `+${Math.round(SACRIFICE_BONUSES[val] * 100)}%` : '0%';
    });
    slider.addEventListener('change', rerender);
  }
}

// ── Entry point ───────────────────────────────────────────────────────────────
export async function initBosses({ params, query }) {
  const app = document.getElementById('app');
  const bosses = await loadBossData();
  await loadBossDropData();

  if (params.id) {
    const boss = bosses.find(b => b.id === params.id);
    if (boss) {
      app.innerHTML = renderBossDetail(boss);
      appendPatchHistory(app.querySelector('.idb-detail'), [boss.name]);
      initDropCalc(boss);
      initDropsControls(boss);
      bindItemHover(app.querySelector('.idb-side'));
      return () => hideItemTooltip();
    }
    app.innerHTML = `
      <nav class="idb-crumbs"><button type="button" class="back-btn" onclick="appBack('#/bosses')">${t('items.back')}</button><a href="#/bosses">${t('bosses.title')}</a></nav>
      <div class="coming-soon">
        <h2>${t('page.notFound')}</h2>
        <p>${t('bosses.notFoundBody')}</p>
      </div>
    `;
    return;
  }

  // ── List ── (defaults to Arcana bosses, as before; ?cat= shows all)
  const s = { q: query.q || '', cat: 'cat' in query ? query.cat : 'Endgame', sort: query.sort || 'tier' };
  app.innerHTML = renderBossShell(s);
  const facetsEl = document.getElementById('bossFacets');
  const metaEl = document.getElementById('bossMeta');
  const listEl = document.getElementById('bossList');
  const searchEl = document.getElementById('bossSearchInput');

  const syncUrl = () => {
    const p = new URLSearchParams();
    if (s.cat !== 'Endgame') p.set('cat', s.cat);
    if (s.q) p.set('q', s.q);
    if (s.sort !== 'tier') p.set('sort', s.sort);
    const qs = p.toString();
    history.replaceState(null, '', '#/bosses' + (qs ? '?' + qs : ''));
  };

  const update = () => {
    const list = filterBosses(bosses, s);
    facetsEl.innerHTML = renderBossFacets(bosses, s);
    metaEl.innerHTML = `<span>${list.length === 1 ? t('bosses.entry') : t('bosses.entries', { n: list.length })}</span>`;
    listEl.innerHTML = list.length
      ? `<div class="idb-list">${list.map(bossRowHtml).join('')}</div>`
      : `<div class="idb-empty">${t('bosses.empty')}</div>`;
    hideItemTooltip();
  };

  const onClick = e => {
    const btn = e.target.closest('button[data-k="cat"]');
    if (!btn || btn.disabled) return;
    s.cat = btn.dataset.v;
    syncUrl();
    update();
  };
  const onChange = e => {
    const sel = e.target.closest('select[data-k="sort"]');
    if (!sel) return;
    s.sort = sel.value;
    syncUrl();
    update();
  };
  const onKey = e => {
    if (e.key !== '/' || e.ctrlKey || e.metaKey) return;
    const tag = document.activeElement?.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
    e.preventDefault();
    searchEl.focus();
  };

  let raf = 0;
  searchEl.addEventListener('input', () => {
    s.q = searchEl.value;
    cancelAnimationFrame(raf);
    raf = requestAnimationFrame(() => { syncUrl(); update(); });
  });
  app.addEventListener('click', onClick);
  app.addEventListener('change', onChange);
  document.addEventListener('keydown', onKey);
  bindItemHover(listEl);
  update();

  return function cleanup() {
    app.removeEventListener('click', onClick);
    app.removeEventListener('change', onChange);
    document.removeEventListener('keydown', onKey);
    hideItemTooltip();
  };
}
