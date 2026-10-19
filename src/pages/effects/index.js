import { esc } from '../../ui/escape.js';
import { t, getClassName } from '../../i18n.js';
import { loadItems, getItem, rankInfo, iconSrc, localizedNameByName, stemQuery } from '../../data/items.js';
import { iconHtml, bindItemHover } from '../../ui/itemUi.js';
import { loadSkills, getSkill } from '../../data/skills.js';

// Buff / debuff stacking types (data/effects.json): effects of the same type don't stack.
let effectsData = null;
let heroData = null;

async function loadData() {
  if (effectsData) return;
  try {
    const [er, hr] = await Promise.all([
      fetch('data/effects.json'),
      fetch('data/heroes.json'),
      loadSkills(),
      loadItems(),
    ]);
    if (er.ok) effectsData = await er.json();
    if (hr.ok) heroData = await hr.json();
  } catch (e) {}
  if (!effectsData) effectsData = { rules: [], sections: [] };
  if (!heroData) heroData = [];
}

const heroOf = cls => heroData.find(h => h.heroClass === cls);

function entryText(e) {
  return [e.item && localizedNameByName(e.item), e.item, e.hero, e.hero && getClassName(e.hero), e.skill, e.text, e.via, e.value, ...(e.examples || [])]
    .filter(Boolean).join(' ').toLowerCase();
}

function itemLink(name) {
  return `<a href="#/items/${encodeURIComponent(name)}" class="fx-name ${rankInfo(getItem(name)).css}" data-name="${esc(name)}">${iconHtml(name, 'fx-icon')}<span>${esc(localizedNameByName(name))}</span></a>`;
}

function entryHtml(e) {
  let main;
  if (e.item) {
    main = itemLink(e.item);
  } else if (e.hero) {
    const hero = heroOf(e.hero);
    const sk = getSkill(e.hero, e.skill);
    const keys = String(e.key || '').split('→').map(k => `<kbd class="hs-key">${esc(k.trim())}</kbd>`).join('<span class="hs-arrow">→</span>');
    main = `<a href="#/heroes/${esc(hero?.id || '')}" class="fx-name" data-skill="${esc(e.hero + '|' + e.skill)}" data-color="${esc(hero?.color || '')}">${iconHtml(e.skill, 'fx-icon', iconSrc(sk?.icon || e.skill))}
      <span><b${hero?.color ? ` style="color:#${esc(hero.color)}"` : ''}>${esc(getClassName(e.hero))}</b> ${esc(e.skill)}</span>${keys ? `<span class="fx-keys">${keys}</span>` : ''}</a>`;
  } else {
    main = `<span class="fx-name fx-text"><span>${esc(e.text)}</span>${e.examples?.length
      ? `<span class="fx-examples">${e.examples.map(itemLink).join('')}</span>` : ''}</span>`;
  }
  return `<li class="fx-entry">
    ${main}
    ${e.via ? `<span class="fx-via">${esc(e.via)}</span>` : '<span></span>'}
    <span class="fx-value">${esc(e.value || '')}</span>
  </li>`;
}

// Type-A..D badge, a plain group label (e.g. "Base stats"), or nothing for Unique categories,
// whose section heading already says they stack with everything.
function typeLabelHtml(c, tp) {
  if (tp.type) {
    return `<div class="fx-type-label"><span class="fx-badge fx-badge-${esc(tp.type.toLowerCase())}">${esc(t('fx.type', { t: tp.type }))}</span>${tp.label ? `<span class="fx-type-sub">${esc(tp.label)}</span>` : ''}</div>`;
  }
  if (tp.label) return `<div class="fx-type-label"><span class="fx-badge">${esc(tp.label)}</span></div>`;
  if (c.group === 'unique') return '';
  return `<div class="fx-type-label"><span class="fx-badge">${esc(t('fx.stacks'))}</span></div>`;
}

const FORMULA = 'formula';
const SECTION_TITLE = { buff: 'fx.buffs', debuff: 'fx.debuffs', unique: 'fx.uniqueSection' };

function categoryHtml(c, q) {
  const types = c.types
    .map(tp => ({ ...tp, entries: q ? tp.entries.filter(e => entryText(e).includes(q) || c.name.toLowerCase().includes(q)) : tp.entries }))
    .filter(tp => tp.entries.length);
  if (!types.length) return '';
  return `<article class="fx-cat" id="fx-${esc(c.id)}">
    <header class="fx-cat-head">
      <h3>${esc(c.name)}</h3>
      ${c.stacking ? `<span class="fx-stacking">${esc(c.stacking)}</span>` : ''}
    </header>
    ${c.note ? `<p class="fx-note">${esc(c.note)}</p>` : ''}
    ${c.group === 'unique' ? splitHtml(types.flatMap(tp => tp.entries)) : `<div class="fx-body">${types.map(tp => `<div class="fx-type">
      ${typeLabelHtml(c, tp)}
      <ul class="fx-entries">${tp.entries.map(entryHtml).join('')}</ul>
    </div>`).join('')}</div>`}
  </article>`;
}

// Unique cards span the full width with items on the left and hero abilities on the right.
function splitHtml(entries) {
  const col = (label, list) => `<div class="fx-split-col">
    <div class="fx-type-label"><span class="fx-badge">${label}</span><span class="fx-type-sub">${list.length}</span></div>
    ${list.length
      ? `<div class="fx-body"><div class="fx-type"><ul class="fx-entries">${list.map(entryHtml).join('')}</ul></div></div>`
      : `<p class="fx-none">—</p>`}
  </div>`;
  return `<div class="fx-split">${col(t('fx.items'), entries.filter(e => !e.hero))}${col(t('fx.abilities'), entries.filter(e => e.hero))}</div>`;
}

// Entries in a category that match the search.
function matchCount(c, q) {
  return c.types.reduce((n, tp) => n + (q
    ? tp.entries.filter(e => entryText(e).includes(q) || c.name.toLowerCase().includes(q)).length
    : tp.entries.length), 0);
}

// Category groups in page order: [{ id, kind, cats }] (Offense / Defense / Stats / Debuffs).
function categoryGroups() {
  const groups = [];
  for (const sec of effectsData.sections) {
    for (const c of sec.categories) {
      let g = groups.find(x => x.id === c.group);
      if (!g) groups.push(g = { id: c.group, kind: sec.kind, cats: [] });
      g.cats.push(c);
    }
  }
  return groups;
}

// Damage formula reference (effectsData.formula): the steps in calculation order.
function formulaHtml() {
  const f = effectsData.formula;
  if (!f) return `<div class="idb-empty">${t('fx.empty')}</div>`;
  let n = 0;
  const step = st => `<li class="fx-step${st.sub ? ' sub' : ''}">
    <span class="fx-step-num">${st.sub ? '' : ++n}</span>
    <div class="fx-step-body">
      <div class="fx-step-head">
        <h3>${esc(st.name)}</h3>
        ${st.stacking ? `<span class="fx-stacking">${esc(st.stacking)}</span>` : ''}
        ${st.cat ? `<a class="fx-step-link" href="#/effects?cat=${encodeURIComponent(st.cat)}">${t('fx.seeEffects')}</a>` : ''}
      </div>
      <p>${esc(st.text)}${st.example ? ` <span class="fx-step-ex">${esc(st.example)}</span>` : ''}</p>
      ${st.examples?.length ? `<ul class="fx-step-list">${st.examples.map(x => `<li>${esc(x)}</li>`).join('')}</ul>` : ''}
    </div>
  </li>`;
  return `<section class="fx-formula">
    <header class="fx-cat-head"><h3>${t('fx.group.formula')}</h3>${f.version ? `<span class="fx-stacking">${esc(f.version)}</span>` : ''}</header>
    ${f.intro ? `<p class="fx-note">${esc(f.intro)}</p>` : ''}
    <ol class="fx-steps">${f.steps.map(step).join('')}</ol>
    ${f.after ? `<p class="fx-note fx-formula-after">${esc(f.after)}</p>` : ''}
  </section>`;
}

const shown = (c, s) => (s.cat ? c.id === s.cat : !s.group || c.group === s.group);

function renderList(s) {
  if (s.group === FORMULA) return formulaHtml();
  const q = stemQuery(s.q.toLowerCase()).trim();
  // All: buffs and debuffs side by side, Unique below them. A group or category shows on its own across the full width.
  const filtered = s.group || s.cat;
  const sections = effectsData.sections
    .map(sec => ({ sec, cats: sec.categories.filter(c => shown(c, s)).map(c => categoryHtml(c, q)).join('') }))
    .filter(x => !filtered || x.cats);
  if (!sections.some(x => x.cats)) return `<div class="idb-empty">${t('fx.empty')}</div>`;
  return `<div class="fx-columns${sections.length === 1 ? ' single' : ''}">${sections.map(({ sec, cats }) =>
    `<section class="fx-section fx-${esc(sec.kind)}">
      <h2>${t(SECTION_TITLE[sec.kind])}</h2>
      ${cats ? `<div class="fx-grid">${cats}</div>` : `<p class="fx-none">${t('fx.empty')}</p>`}
    </section>`).join('')}</div>`;
}

// Tabs: All / Offense / Defense / Stats / Debuffs. A picked group adds a row of its categories.
function renderTabs(s) {
  const q = stemQuery(s.q.toLowerCase()).trim();
  const groups = categoryGroups();
  const count = cats => cats.reduce((n, c) => n + matchCount(c, q), 0);
  const tab = (id, label, n, kind = '') =>
    `<button type="button" class="idb-tab${kind ? ' fx-tab-' + kind : ''}" data-group="${esc(id)}" aria-pressed="${s.group === id}" ${n || !id ? '' : 'disabled'}>${label}<span>${n}</span></button>`;
  const active = groups.find(g => g.id === s.group);
  // Damage formula is reference info, not a category group: anchored to the right, no count.
  const formula = effectsData.formula
    ? `<button type="button" class="idb-tab fx-tab-formula" data-group="${FORMULA}" aria-pressed="${s.group === FORMULA}">${t('fx.group.formula')}</button>` : '';
  return `<div class="idb-tabs">${tab('', t('items.all'), count(groups.flatMap(g => g.cats)))}${groups.map(g => tab(g.id, t('fx.group.' + g.id), count(g.cats), g.kind)).join('')}${formula}</div>
    ${active ? `<div class="idb-tiers">${active.cats.map(c => {
      const n = matchCount(c, q);
      return `<button type="button" class="idb-chip" data-cat="${esc(c.id)}" aria-pressed="${s.cat === c.id}" title="${esc(c.name)}" ${n ? '' : 'disabled'}>${esc(c.short || c.name)}<span>${n}</span></button>`;
    }).join('')}</div>` : ''}`;
}

export async function initEffects({ query }) {
  const app = document.getElementById('app');
  await loadData();
  const allCats = effectsData.sections.flatMap(sec => sec.categories);
  const cat = allCats.find(c => c.id === query.cat);
  const group = cat ? cat.group : (allCats.some(c => c.group === query.group) || (query.group === FORMULA && effectsData.formula) ? query.group : '');
  const s = { q: query.q || '', group, cat: cat ? cat.id : '' };

  app.innerHTML = `
    <div class="page-header">
      <h1>${t('fx.title')}</h1>
      <p class="page-subtitle">${t('fx.subtitle')}</p>
    </div>
    <ul class="fx-rules">${effectsData.rules.map(r => `<li>${esc(r)}</li>`).join('')}</ul>
    <div class="idb-toolbar">
      <label class="idb-search">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/></svg>
        <input type="search" id="fxSearch" placeholder="${esc(t('fx.search'))}" value="${esc(s.q)}" autocomplete="off" spellcheck="false">
        <kbd>/</kbd>
      </label>
    </div>
    <div class="idb-facets" id="fxTabs"></div>
    <div id="fxList"></div>
  `;
  const tabsEl = document.getElementById('fxTabs');
  const listEl = document.getElementById('fxList');
  const searchEl = document.getElementById('fxSearch');

  const syncUrl = () => {
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries(s)) if (v) p.set(k, v);
    const qs = p.toString();
    history.replaceState(null, '', '#/effects' + (qs ? '?' + qs : ''));
  };
  const update = () => {
    tabsEl.innerHTML = renderTabs(s);
    listEl.innerHTML = renderList(s);
    syncUrl();
  };
  update();

  searchEl.addEventListener('input', () => { s.q = searchEl.value; update(); });
  tabsEl.addEventListener('click', e => {
    const btn = e.target.closest('[data-group], [data-cat]');
    if (!btn || btn.disabled) return;
    if ('group' in btn.dataset) {
      s.group = btn.dataset.group;
      s.cat = '';
    } else {
      // Clicking the selected category again shows the whole group.
      s.cat = s.cat === btn.dataset.cat ? '' : btn.dataset.cat;
    }
    update();
  });
  const onKey = e => {
    const tag = document.activeElement?.tagName;
    if (e.key === '/' && tag !== 'INPUT' && tag !== 'TEXTAREA') { e.preventDefault(); searchEl.focus(); }
  };
  document.addEventListener('keydown', onKey);
  const unbindHover = bindItemHover(listEl);
  return () => { document.removeEventListener('keydown', onKey); unbindHover(); };
}
