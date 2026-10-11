import { esc } from '../../ui/escape.js';
import { t, getClassName } from '../../i18n.js';
import { loadItems, getItem, rankInfo, iconSrc, localizedNameByName } from '../../data/items.js';
import { iconHtml, bindItemHover } from '../../ui/itemUi.js';

// Buff / debuff stacking types (data/effects.json): effects of the same type don't stack.
let effectsData = null;
let heroData = null;
let skillData = null;

async function loadData() {
  if (effectsData) return;
  try {
    const [er, hr, sr] = await Promise.all([
      fetch('data/effects.json'),
      fetch('data/heroes.json'),
      fetch('data/skills.json'),
      loadItems(),
    ]);
    if (er.ok) effectsData = await er.json();
    if (hr.ok) heroData = await hr.json();
    if (sr.ok) skillData = await sr.json();
  } catch (e) {}
  if (!effectsData) effectsData = { rules: [], sections: [] };
  if (!heroData) heroData = [];
  if (!skillData) skillData = [];
}

const heroOf = cls => heroData.find(h => h.heroClass === cls);
const skillOf = (cls, name) => skillData.find(s => s.heroClass === cls && s.name === name);

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
    const sk = skillOf(e.hero, e.skill);
    const keys = String(e.key || '').split('→').map(k => `<kbd class="hs-key">${esc(k.trim())}</kbd>`).join('<span class="hs-arrow">→</span>');
    main = `<a href="#/heroes/${esc(hero?.id || '')}" class="fx-name">${iconHtml(e.skill, 'fx-icon', iconSrc(sk?.icon || e.skill))}
      <span title="${esc(getClassName(e.hero) + ' ' + e.skill)}"><b>${esc(getClassName(e.hero))}</b> ${esc(e.skill)}</span>${keys ? `<span class="fx-keys">${keys}</span>` : ''}</a>`;
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
    ${types.map(tp => `<div class="fx-type">
      <div class="fx-type-label">${tp.type ? `<span class="fx-badge fx-badge-${esc(tp.type.toLowerCase())}">${esc(t('fx.type', { t: tp.type }))}</span>` : `<span class="fx-badge">${esc(t('fx.stacks'))}</span>`}${tp.label ? `<span class="fx-type-sub">${esc(tp.label)}</span>` : ''}</div>
      <ul class="fx-entries">${tp.entries.map(entryHtml).join('')}</ul>
    </div>`).join('')}
  </article>`;
}

function renderList(s) {
  const q = s.q.toLowerCase().trim();
  // Buffs and debuffs side by side; a single kind (tab) spreads across the full width.
  const sections = effectsData.sections.filter(sec => !s.kind || sec.kind === s.kind)
    .map(sec => ({ sec, cats: sec.categories.map(c => categoryHtml(c, q)).join('') }));
  if (!sections.some(x => x.cats)) return `<div class="idb-empty">${t('fx.empty')}</div>`;
  return `<div class="fx-columns${sections.length === 1 ? ' single' : ''}">${sections.map(({ sec, cats }) =>
    `<section class="fx-section fx-${esc(sec.kind)}">
      <h2>${t(sec.kind === 'buff' ? 'fx.buffs' : 'fx.debuffs')}</h2>
      ${cats ? `<div class="fx-grid">${cats}</div>` : `<p class="fx-none">${t('fx.empty')}</p>`}
    </section>`).join('')}</div>`;
}

function renderTabs(s) {
  const tab = (kind, label) => `<button type="button" class="idb-tab" data-kind="${kind}" aria-pressed="${s.kind === kind}">${label}</button>`;
  return `<div class="idb-tabs">${tab('', t('items.all'))}${tab('buff', t('fx.buffs'))}${tab('debuff', t('fx.debuffs'))}</div>`;
}

export async function initEffects({ query }) {
  const app = document.getElementById('app');
  await loadData();
  const s = { q: query.q || '', kind: ['buff', 'debuff'].includes(query.kind) ? query.kind : '' };

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
    const btn = e.target.closest('[data-kind]');
    if (!btn) return;
    s.kind = btn.dataset.kind;
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
