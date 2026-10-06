import { esc } from '../../ui/escape.js';
import { iconSrc as sharedIconSrc } from '../../data/items.js';
import { iconHtml } from '../../ui/itemUi.js';
import { t, tf, getClassName } from '../../i18n.js';

let awakeningData = null;
let heroData = null;
let skillData = null;

async function loadData() {
  if (awakeningData) return;
  try {
    const [ar, hr, sr] = await Promise.all([
      fetch('data/awakenings.json'),
      fetch('data/heroes.json'),
      fetch('data/skills.json'),
    ]);
    if (ar.ok) awakeningData = await ar.json();
    if (hr.ok) heroData = await hr.json();
    if (sr.ok) skillData = await sr.json();
  } catch (e) {}
  if (!awakeningData) awakeningData = [];
  if (!heroData) heroData = [];
  if (!skillData) skillData = [];
}

function getHero(heroClass) {
  return heroData.find(h => h.heroClass === heroClass);
}

// The awakened skill's base version, when its name matches the skill list.
function findSkill(heroClass, name) {
  const n = name.toLowerCase();
  return skillData.find(s => s.heroClass === heroClass && s.name.toLowerCase() === n) || null;
}

function iconSrc(name) {
  return sharedIconSrc(name);
}

const STAT_ORDER = ['STR', 'AGI', 'INT'];
const STAT_CSS = { STR: 'stat-str', AGI: 'stat-agi', INT: 'stat-int' };

const EFFECT_TYPE_LABELS = {
  'STR': 'STR Path',
  'AGI': 'AGI Path',
  'INT': 'INT Path',
  'Passive': 'Passive',
  'Skill': 'Skill',
  'Active': 'Active',
};

function matches(awk, s) {
  const hero = getHero(awk.heroClass);
  if (s.stat && hero?.mainstat !== s.stat) return false;
  const q = s.q.toLowerCase().trim();
  if (!q) return true;
  return [awk.heroClass, hero?.name, awk.original, awk.awakened, ...awk.effects.map(e => e.description)]
    .join(' ').toLowerCase().includes(q);
}

function entryHtml(awk) {
  const hero = getHero(awk.heroClass);
  const skill = findSkill(awk.heroClass, awk.original);
  const heroBlock = hero
    ? `<a href="#/heroes/${esc(hero.id)}" class="aw-hero" style="--hero:#${esc(hero.color)}">
        ${iconHtml(hero.name, 'hl-portrait', iconSrc(hero.icon))}
        <span class="hl-text"><span class="hl-name">${esc(getClassName(awk.heroClass))}</span><span class="hl-class">${esc(hero.name)}</span></span>
      </a>`
    : `<div class="aw-hero"><span class="hl-text"><span class="hl-name">${esc(awk.heroClass)}</span></span></div>`;
  const keys = skill ? (String(skill.hotkey).match(/Passive|[A-Z]/g) || []) : [];

  return `<article class="aw-entry">
    ${heroBlock}
    <div class="aw-body">
      <div class="aw-skill">
        ${skill ? iconHtml(skill.name, 'hs-icon', iconSrc(skill.icon)) : ''}
        <span class="aw-original">${esc(awk.original)}</span>
        ${keys.map(k => `<kbd class="hs-key">${esc(k)}</kbd>`).join('')}
        <span class="aw-arrow">→</span>
        <span class="aw-awakened">${esc(awk.awakened)}</span>
      </div>
      <ul class="aw-effects">
        ${awk.effects.map(e => `<li>
          <span class="aw-tag awt-${esc(String(e.type).toLowerCase())}">${esc(tf('awk.type.' + e.type, EFFECT_TYPE_LABELS[e.type] || e.type))}</span>
          <p>${esc(e.description)}</p>
        </li>`).join('')}
      </ul>
    </div>
  </article>`;
}

function renderShell(s) {
  const documented = new Set(awakeningData.map(a => a.heroClass));
  const pct = heroData.length ? Math.round((documented.size / heroData.length) * 100) : 0;
  return `
    <div class="page-header">
      <h1>${t('awk.title')}</h1>
      <p class="page-subtitle">${t('awk.subtitle')}</p>
    </div>
    <div class="aw-notice">
      <div class="aw-progress">
        <span>${t('awk.documented', { n: documented.size, total: heroData.length })}</span>
        <span class="aw-bar"><i style="width:${pct}%"></i></span>
      </div>
      <p>${t('awk.notice')}</p>
    </div>
    <div class="idb-toolbar">
      <label class="idb-search">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/></svg>
        <input type="search" id="awkSearch" placeholder="${esc(t('awk.search'))}" value="${esc(s.q)}" autocomplete="off" spellcheck="false">
        <kbd>/</kbd>
      </label>
    </div>
    <div class="idb-facets" id="awkFacets"></div>
    <div id="awkList"></div>
  `;
}

function renderFacets(s) {
  const base = awakeningData.filter(a => matches(a, { ...s, stat: '' }));
  const tab = (key, label, n) =>
    `<button type="button" class="idb-tab ${key ? STAT_CSS[key] : ''}" data-v="${key}" aria-pressed="${s.stat === key}" ${n ? '' : 'disabled'}>${key ? '<i class="hl-swatch"></i>' : ''}${label}<span>${n}</span></button>`;
  return `<div class="idb-tabs">${tab('', t('items.all'), base.length)}${STAT_ORDER.map(k =>
    tab(k, t('stat.' + k), base.filter(a => getHero(a.heroClass)?.mainstat === k).length)).join('')}</div>`;
}

function renderList(s) {
  const list = awakeningData.filter(a => matches(a, s));
  if (!list.length) return `<div class="idb-empty">${t('awk.empty')}</div>`;
  const groups = STAT_ORDER.map(stat => {
    const group = list.filter(a => getHero(a.heroClass)?.mainstat === stat).sort((a, b) => a.heroClass.localeCompare(b.heroClass));
    if (!group.length) return '';
    return `<section class="hl-group ${STAT_CSS[stat]}">
      <h2><i class="hl-swatch"></i>${t('stat.' + stat)} <span>${group.length}</span></h2>
      <div class="aw-list">${group.map(entryHtml).join('')}</div>
    </section>`;
  }).join('');

  // Heroes without an entry yet — only when not searching, so the list stays relevant.
  const documented = new Set(awakeningData.map(a => a.heroClass));
  const missing = s.q ? [] : heroData
    .filter(h => !documented.has(h.heroClass) && (!s.stat || h.mainstat === s.stat))
    .sort((a, b) => a.heroClass.localeCompare(b.heroClass));
  const missingHtml = missing.length ? `<section class="aw-missing">
      <h2>${t('awk.missing')} <span>${missing.length}</span></h2>
      <div class="aw-missing-list">${missing.map(h => `<a href="#/heroes/${esc(h.id)}">${esc(getClassName(h.heroClass))}</a>`).join('')}</div>
    </section>` : '';
  return groups + missingHtml;
}

export async function initAwakening({ query }) {
  const app = document.getElementById('app');
  await loadData();

  const s = { q: query.q || '', stat: query.stat || '' };
  app.innerHTML = renderShell(s);
  const facetsEl = document.getElementById('awkFacets');
  const listEl = document.getElementById('awkList');
  const searchEl = document.getElementById('awkSearch');

  const syncUrl = () => {
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries(s)) if (v) p.set(k, v);
    const qs = p.toString();
    history.replaceState(null, '', '#/awakening' + (qs ? '?' + qs : ''));
  };
  const update = () => {
    facetsEl.innerHTML = renderFacets(s);
    listEl.innerHTML = renderList(s);
  };

  const onClick = e => {
    const btn = e.target.closest('#awkFacets button[data-v]');
    if (!btn || btn.disabled) return;
    s.stat = btn.dataset.v;
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
