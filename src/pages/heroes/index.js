import { esc } from '../../ui/escape.js';
import { t, getClassName, getTypeName } from '../../i18n.js';
import { loadItems, iconSrc as sharedIconSrc, getItem, rankInfo, localizedItemName } from '../../data/items.js';
import { iconHtml, bindItemHover } from '../../ui/itemUi.js';
import { hideItemTooltip } from '../../ui/tooltip.js';
import { slotIcon } from '../../ui/slotIcons.js';
import { appendPatchHistory } from '../../ui/patchHistory.js';

let heroData = null;
let skillData = null;

async function loadData() {
  if (heroData && skillData) return;
  try {
    const [hr, sr] = await Promise.all([
      fetch('data/heroes.json'),
      fetch('data/skills.json'),
      loadItems(),
    ]);
    if (hr.ok) heroData = await hr.json();
    if (sr.ok) skillData = await sr.json();
  } catch (e) {}
  if (!heroData) heroData = [];
  if (!skillData) skillData = [];
}

function getSpecDescription(weaponName, heroClass) {
  const item = getItem(weaponName);
  if (!item?.stats?.spec) return '';
  const specLine = item.stats.spec.find(s => s.startsWith(heroClass + ' - '));
  if (specLine) return specLine.slice(heroClass.length + 3);
  if (item.stats.spec.length > 1) return item.stats.spec[1].replace(/^[^-]+ - /, '');
  return '';
}

const STAT_ORDER = ['STR', 'AGI', 'INT'];
const STAT_CSS = { STR: 'stat-str', AGI: 'stat-agi', INT: 'stat-int' };

function iconSrc(name) {
  return sharedIconSrc(name);
}

// ── Role classification ───────────────────────────────────────
const SUPPORT_CLASSES = new Set([
  'Soul Weaver', 'Wind Mage', 'Priest', 'Merchant',
  'Elementalist', 'Dark Knight', 'Paladin', 'Hermit', 'Shooter', 'Witch',
]);
const DPS_CLASSES = new Set([
  'Sniper', 'Fire Mage', 'Lightning Mage', 'Reaper', 'Assassin',
  'Martial Artist', 'Thunderer', 'Berserker', 'Bow Master', 'Fighter',
  'Trickster', 'Lightseeker', 'Blaster', 'Sword Saint', 'Phantom Blade',
  'Swordsman', 'Gunner', 'Sword Enchanter', 'Lancer', 'Crusader',
  'Warlock', 'Dark Knight', 'Paladin', 'Knight', 'Blood Weaver',
  'Water Mage', 'Hermit', 'Shooter',
]);

function heroMatchesRole(hero, role) {
  if (!role) return true;
  if (role === 'DPS') return DPS_CLASSES.has(hero.heroClass);
  if (role === 'Support') return SUPPORT_CLASSES.has(hero.heroClass);
  return true;
}

// ── Hero list ─────────────────────────────────────────────────
function filterHeroes(heroes, s, skip) {
  const q = s.q.toLowerCase().trim();
  return heroes.filter(h =>
    (skip === 'stat' || !s.stat || h.mainstat === s.stat) &&
    (skip === 'role' || heroMatchesRole(h, s.role)) &&
    (!q || [h.name, h.heroClass, ...(h.role || [])].join(' ').toLowerCase().includes(q)));
}

function heroCardHtml(hero) {
  return `<a href="#/heroes/${esc(hero.id)}" class="hl-card" style="--hero:#${esc(hero.color)}">
    ${iconHtml(hero.name, 'hl-portrait', iconSrc(hero.icon))}
    <span class="hl-text">
      <span class="hl-name">${esc(hero.name)}</span>
      <span class="hl-class">${esc(getClassName(hero.heroClass))}</span>
      ${hero.role?.length ? `<span class="hl-role">${esc(hero.role.join(' · '))}</span>` : ''}
    </span>
  </a>`;
}

function renderListShell(s) {
  return `
    <div class="page-header">
      <h1>${t('heroes.title')}</h1>
      <p class="page-subtitle">${t('heroes.subtitle')}</p>
    </div>
    <div class="idb-toolbar">
      <label class="idb-search">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/></svg>
        <input type="search" id="heroSearchInput" placeholder="${esc(t('heroes.search'))}" value="${esc(s.q)}" autocomplete="off" spellcheck="false">
        <kbd>/</kbd>
      </label>
    </div>
    <div class="idb-facets" id="heroFacets"></div>
    <div id="heroList"></div>
  `;
}

function renderFacets(heroes, s) {
  const byStat = filterHeroes(heroes, s, 'stat');
  const byRole = filterHeroes(heroes, s, 'role');
  const tab = (key, label, n) =>
    `<button type="button" class="idb-tab ${key ? STAT_CSS[key] : ''}" data-k="stat" data-v="${key}" aria-pressed="${s.stat === key}" ${n ? '' : 'disabled'}>${key ? '<i class="hl-swatch"></i>' : ''}${label}<span>${n}</span></button>`;
  const chip = role => {
    const n = byRole.filter(h => heroMatchesRole(h, role)).length;
    return `<button type="button" class="idb-chip" data-k="role" data-v="${role}" aria-pressed="${s.role === role}" ${n ? '' : 'disabled'}>${t(role === 'DPS' ? 'heroes.dps' : 'heroes.support')}<span>${n}</span></button>`;
  };
  return `<div class="idb-tabs">${tab('', t('items.all'), byStat.length)}${STAT_ORDER.map(k => tab(k, t('stat.' + k), byStat.filter(h => h.mainstat === k).length)).join('')}</div>
    <div class="idb-tiers">${chip('DPS')}${chip('Support')}</div>`;
}

function renderList(list) {
  if (!list.length) return `<div class="idb-empty">${t('heroes.empty')}</div>`;
  return STAT_ORDER.map(stat => {
    const group = list.filter(h => h.mainstat === stat).sort((a, b) => a.heroClass.localeCompare(b.heroClass));
    if (!group.length) return '';
    return `<section class="hl-group ${STAT_CSS[stat]}">
      <h2><i class="hl-swatch"></i>${t('stat.' + stat)} <span>${group.length}</span></h2>
      <div class="hl-grid">${group.map(heroCardHtml).join('')}</div>
    </section>`;
  }).join('');
}

// ── Hero detail ───────────────────────────────────────────────
// Hotkeys come as "[Q]", "[Q] → [W]", "[Q] -> [W]", "[R → R]"; normalise to key lists.
function hotkeyPath(hotkey) {
  const keys = String(hotkey || '').match(/Passive|[A-Z]/g) || [];
  return keys.length ? keys : ['?'];
}

const KEY_ORDER = ['Passive', 'A', 'D', 'Q', 'W', 'E', 'R', 'T', 'F'];

function groupSkills(skills) {
  const groups = new Map();
  for (const sk of skills) {
    const path = hotkeyPath(sk.hotkey);
    const root = path[0];
    if (!groups.has(root)) groups.set(root, []);
    groups.get(root).push({ sk, depth: path.length - 1, path });
  }
  const rootIdx = k => (KEY_ORDER.includes(k) ? KEY_ORDER.indexOf(k) : 99);
  return [...groups.entries()]
    .sort((a, b) => Math.min(...a[1].map(x => x.sk.order || 0)) - Math.min(...b[1].map(x => x.sk.order || 0)) || rootIdx(a[0]) - rootIdx(b[0]))
    .map(([key, list]) => ({ key, list: list.sort((a, b) => a.depth - b.depth || (a.sk.order || 0) - (b.sk.order || 0)) }));
}

function keycaps(path) {
  return path.map(k => `<kbd class="hs-key">${esc(k)}</kbd>`).join('<span class="hs-arrow">→</span>');
}

function skillHtml({ sk, depth, path }) {
  const lines = (arr, flavorFirst) => `<ul class="hs-lines">${arr.map((l, i) => `<li class="${flavorFirst && i === 0 ? 'hs-flavor' : ''}">${esc(l)}</li>`).join('')}</ul>`;
  const hasP = sk.passive?.length, hasA = sk.active?.length;
  const meta = [
    sk.cooldown != null ? t('heroes.cooldown', { n: sk.cooldown }) : '',
    sk.proc_rate != null ? t('heroes.proc', { n: Math.round(sk.proc_rate * 100) }) : '',
    sk.toggle ? t('heroes.toggle') : '',
  ].filter(Boolean);
  return `<article class="hs-skill" data-depth="${Math.min(depth, 2)}" style="--skill:#${esc(sk.color || '888888')}">
    <header class="hs-head">
      ${iconHtml(sk.name, 'hs-icon', iconSrc(sk.icon))}
      <div class="hs-title">
        <h3>${esc(sk.name)}</h3>
        <div class="hs-meta">${keycaps(path)}${meta.map(m => `<span>${esc(m)}</span>`).join('')}</div>
      </div>
    </header>
    ${hasP ? `${hasA ? `<div class="hs-label">${t('items.passive')}</div>` : ''}${lines(sk.passive, true)}` : ''}
    ${hasA ? `${hasP ? `<div class="hs-label hs-label-active">${t('items.active')}</div>` : ''}${lines(sk.active, !hasP)}` : ''}
  </article>`;
}

function weaponTypeChip(w) {
  const sub = (w.match(/\(([^)]+)\)/) || [])[1] || w;
  return `<span class="hd-weapon">${slotIcon('weapon', 13)}${esc(getTypeName(sub))}</span>`;
}

function renderHeroDetail(hero, skills) {
  const heroSkills = skills.filter(s => s.heroClass === hero.heroClass);
  const groups = groupSkills(heroSkills);
  const weaponTypes = (hero.wearable || []).filter(w => w.startsWith('Weapon'));
  const specs = hero.spec?.length && hero.spec[0] !== 'No Specs!' ? hero.spec : [];

  const specHtml = specs.length ? `<section class="idb-section">
    <h2>${t('heroes.specs')} <span class="idb-count">${specs.length}</span></h2>
    <div class="hd-specs">${specs.map(s => {
      const [weapon = '', ability = ''] = s.split(' - ');
      const item = getItem(weapon);
      const desc = getSpecDescription(weapon, hero.heroClass);
      const chip = item
        ? `<a href="#/items/${encodeURIComponent(weapon)}" class="idb-chiplink ${rankInfo(item).css}" data-name="${esc(weapon)}">${iconHtml(weapon, 'idb-chip-icon')}<span class="idb-chiplink-name">${esc(localizedItemName(item))}</span></a>`
        : `<span class="idb-chiplink">${esc(weapon)}</span>`;
      return `<div class="hd-spec">
        ${chip}
        <div class="hd-spec-text">
          ${ability ? `<div class="hd-spec-ability">${esc(ability)}</div>` : ''}
          ${desc ? `<p>${esc(desc)}</p>` : ''}
        </div>
      </div>`;
    }).join('')}</div>
  </section>` : '';

  const skillsHtml = groups.length ? `<section class="idb-section">
    <h2>${t('heroes.skills')} <span class="idb-count">${heroSkills.length}</span></h2>
    ${groups.length > 1 ? `<nav class="hd-keys" aria-label="${esc(t('heroes.jump'))}">${groups.map(g => `<button type="button" class="hs-key" data-jump="${esc(g.key)}" title="${esc(g.list[0].sk.name)}">${esc(g.key)}</button>`).join('')}</nav>` : ''}
    <div class="hd-skills">${groups.map(g => `<div class="hs-group" data-key="${esc(g.key)}">${g.list.map(skillHtml).join('')}</div>`).join('')}</div>
  </section>` : '';

  return `
    <nav class="idb-crumbs">
      <button type="button" class="back-btn" onclick="appBack('#/heroes')">${t('items.back')}</button>
      <a href="#/heroes">${t('heroes.title')}</a>
      <span>/</span>
      <a href="#/heroes?stat=${esc(hero.mainstat)}">${esc(t('stat.' + hero.mainstat))}</a>
    </nav>
    <div class="idb-detail hd-layout">
      <article class="idb-card hd-card ${STAT_CSS[hero.mainstat] || ''}" style="--hero:#${esc(hero.color)}">
        <header class="hd-head">
          ${iconHtml(hero.name, 'hd-portrait', iconSrc(hero.icon))}
          <div class="idb-card-title">
            <h1>${esc(hero.name)}</h1>
            <p class="idb-card-meta">
              <span class="hd-class">${esc(getClassName(hero.heroClass))}</span>
              <span class="hd-stat">${esc(t('stat.' + hero.mainstat))}</span>
            </p>
          </div>
        </header>
        ${hero.role?.length ? `<div class="hd-block"><div class="idb-fxlabel">${t('heroes.role')}</div>${hero.role.map(r => `<p>${esc(r)}</p>`).join('')}</div>` : ''}
        ${weaponTypes.length ? `<div class="hd-block"><div class="idb-fxlabel">${t('heroes.weapons')}</div><div class="hd-weapons">${weaponTypes.map(weaponTypeChip).join('')}</div></div>` : ''}
        ${hero.description?.length ? `<div class="hd-block hd-desc">${hero.description.map(d => `<p>${esc(d)}</p>`).join('')}</div>` : ''}
      </article>
      <div class="idb-side">${specHtml}${skillsHtml}</div>
    </div>
  `;
}

// ── Entry point ───────────────────────────────────────────────
export async function initHeroes({ params, query }) {
  const app = document.getElementById('app');
  await loadData();

  if (params.id) {
    const hero = heroData.find(h => h.id === params.id);
    if (!hero) {
      app.innerHTML = `
        <nav class="idb-crumbs"><button type="button" class="back-btn" onclick="appBack('#/heroes')">${t('items.back')}</button><a href="#/heroes">${t('heroes.title')}</a></nav>
        <div class="coming-soon">
          <h2>${t('heroes.notFound')}</h2>
          <p>${t('heroes.notFoundBody')}</p>
        </div>
      `;
      return;
    }
    app.innerHTML = renderHeroDetail(hero, skillData);
    appendPatchHistory(app.querySelector('.idb-detail'), [hero.heroClass]);
    const onClick = e => {
      const key = e.target.closest('[data-jump]')?.dataset.jump;
      if (key) app.querySelector(`.hs-group[data-key="${CSS.escape(key)}"]`)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    };
    app.addEventListener('click', onClick);
    bindItemHover(app.querySelector('.hd-specs'));
    return () => { app.removeEventListener('click', onClick); hideItemTooltip(); };
  }

  // ── List ──
  const s = { q: query.q || '', stat: query.stat || '', role: query.role || '' };
  app.innerHTML = renderListShell(s);
  const facetsEl = document.getElementById('heroFacets');
  const listEl = document.getElementById('heroList');
  const searchEl = document.getElementById('heroSearchInput');

  const syncUrl = () => {
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries(s)) if (v) p.set(k, v);
    const qs = p.toString();
    history.replaceState(null, '', '#/heroes' + (qs ? '?' + qs : ''));
  };
  const update = () => {
    facetsEl.innerHTML = renderFacets(heroData, s);
    listEl.innerHTML = renderList(filterHeroes(heroData, s));
  };

  const onClick = e => {
    const btn = e.target.closest('button[data-k]');
    if (!btn || btn.disabled) return;
    const k = btn.dataset.k, v = btn.dataset.v;
    s[k] = k === 'role' && s.role === v ? '' : v;
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
  searchEl.addEventListener('input', () => { s.q = searchEl.value; syncUrl(); update(); });
  app.addEventListener('click', onClick);
  document.addEventListener('keydown', onKey);
  update();

  return () => {
    app.removeEventListener('click', onClick);
    document.removeEventListener('keydown', onKey);
  };
}
