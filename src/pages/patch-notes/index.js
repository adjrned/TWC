import { esc } from '../../ui/escape.js';
import { t, tf, getLocale, getClassName } from '../../i18n.js';
import { loadItems, getItem, rankInfo, iconSrc, localizedItemName } from '../../data/items.js';
import { getIndex, SECTION_KEYS, HERO_ALIASES, BOSS_ALIASES, minorOf, splitSubject } from '../../data/patches.js';
import { iconHtml, bindItemHover } from '../../ui/itemUi.js';
import { hideItemTooltip } from '../../ui/tooltip.js';
import { showToast } from '../../ui/toast.js';
import { ROSTER } from '../../constants.js';

const BATCH = 15;          // patches rendered per scroll batch (unfiltered view)
const SOURCE_URL = 'https://github.com/sfarmani/twrpg-info';

let bossByName = new Map();
let heroByClass = new Map();
let dataLoaded = false;
let allItems = [];

async function loadData() {
  if (dataLoaded) return;
  const [, items, bossesRes, heroesRes] = await Promise.all([
    getIndex(),
    loadItems(),
    fetch('data/bosses.json').catch(() => null),
    fetch('data/heroes.json').catch(() => null),
  ]);
  if (bossesRes?.ok) bossByName = new Map((await bossesRes.json()).map(b => [b.name, b]));
  if (heroesRes?.ok) heroByClass = new Map((await heroesRes.json()).map(h => [h.heroClass, h]));
  allItems = items || [];
  dataLoaded = true;
}

// ── Formatting ────────────────────────────────────────────────
function fmtMonth(iso) {
  if (!/^\d{4}-\d\d/.test(iso || '')) return '';
  const [y, m] = iso.split('-').map(Number);
  return new Date(y, m - 1, 1).toLocaleDateString(getLocale() === 'zh' ? 'zh-CN' : getLocale(), { year: 'numeric', month: 'short' });
}

function fmtDate(iso) {
  if (!iso || !/^\d{4}-\d\d-\d\d$/.test(iso)) return iso || '';
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString(getLocale() === 'zh' ? 'zh-CN' : getLocale(), { year: 'numeric', month: 'short', day: 'numeric' });
}

// Resolve a subject (subsection title or "X - …" prefix) to a linkable entity.
function resolve(name) {
  const heroClass = HERO_ALIASES[name] || name;
  const hero = heroByClass.get(heroClass);
  if (hero) return { kind: 'hero', href: `#/heroes/${hero.id}`, label: getClassName(heroClass), icon: iconSrc(hero.icon), css: '', hero };
  const item = getItem(name);
  if (item) return { kind: 'item', href: `#/items/${encodeURIComponent(name)}`, label: localizedItemName(item), icon: iconSrc(name), css: rankInfo(item).css, item };
  const boss = bossByName.get(BOSS_ALIASES[name] || name);
  if (boss) return { kind: 'boss', href: `#/bosses/${boss.id}`, label: name, icon: iconSrc(boss.name + ' Icon'), css: '' };
  return null;
}

// Escape, style "->" / "→" arrows, and wrap search terms in <mark>.
function fmt(text, terms) {
  let s = esc(text).replace(/\s*(?:-&gt;|→)\s*/g, ' <span class="pn-arrow">→</span> ');
  if (terms?.length) {
    const re = new RegExp(`(${terms.map(x => esc(x).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')})`, 'gi');
    // Only touch text outside tags.
    s = s.replace(/(^|>)([^<]+)/g, (m, a, txt) => a + txt.replace(re, '<mark>$1</mark>'));
  }
  return s;
}

function subjectLink(name, terms) {
  const r = resolve(name);
  if (!r) return `<b class="pn-subject">${fmt(name, terms)}</b>`;
  const tip = r.kind === 'item' ? ` data-name="${esc(name)}"` : '';
  return `<a href="${r.href}" class="pn-subject ${r.css}"${tip}>${fmt(r.label, terms)}</a>`;
}

function lineHtml(text, terms, inList) {
  const sp = inList ? splitSubject(text) : null;
  if (sp && resolve(sp.subject)) return `${subjectLink(sp.subject, terms)} <span class="pn-dash">—</span> ${fmt(sp.rest, terms)}`;
  return fmt(text, terms);
}

// Nested arrays are sub-points of the preceding line.
function listHtml(list, terms, inList) {
  let html = '';
  for (const x of list || []) {
    if (Array.isArray(x)) html += `<ul class="pn-lines pn-nested">${listHtml(x, terms, false)}</ul>`;
    else html += `<li>${lineHtml(x, terms, inList)}</li>`;
  }
  return html;
}

function subHeadHtml(name, terms) {
  const r = resolve(name);
  const style = r?.hero ? ` style="--hero:#${esc(r.hero.color)}"` : '';
  return r
    ? `<a href="${r.href}" class="pn-sub-head ${r.css}"${r.kind === 'item' ? ` data-name="${esc(name)}"` : ''}${style}>${iconHtml(name, 'pn-icon', r.icon)}<span>${fmt(r.label, terms)}</span></a>`
    : `<div class="pn-sub-head"><span class="pn-icon pn-icon-none"></span><span>${fmt(name, terms)}</span></div>`;
}

const SECTION_CSS = { 'Bug Fixes': 'fix', 'Events': 'events', 'Items': 'items', 'Monsters': 'monsters', 'Characters': 'heroes', 'Miscellaneous': 'misc' };
const sectionTitle = title => tf('pn.section.' + title, title);

function patchHead(patch, isLatest) {
  return `<header class="pn-head">
    <h2><a href="#/patch-notes/${esc(patch.version)}" class="pn-vlink">${esc(patch.version)}</a></h2>
    ${isLatest ? `<span class="pn-latest">${t('pn.latest')}</span>` : ''}
    ${patch.released ? `<time class="pn-date" datetime="${esc(patch.released)}">${esc(fmtDate(patch.released))}</time>` : ''}
    <span class="pn-compat">${patch.compatible ? t('pn.compatible', { v: esc(patch.compatible) }) : ''}</span>
    <button type="button" class="pn-copy" data-copy="${esc(patch.version)}" title="${esc(t('pn.copyLink'))}" aria-label="${esc(t('pn.copyLink'))}">
      <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66l-1 1"/><path d="M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1-1"/></svg>
    </button>
  </header>`;
}

// Full patch (unfiltered view)
function patchHtml(patch, i) {
  return `<article class="pn-patch" id="patch-${esc(patch.version)}" data-version="${esc(patch.version)}">
    ${patchHead(patch, i === 0)}
    ${patch.notice ? `<div class="pn-notice">${esc(patch.notice)}</div>` : ''}
    ${(patch.sections || []).map(section => {
      const count = (section.entries?.filter(x => !Array.isArray(x)).length || 0) + (section.subsections?.length || 0);
      return `<section class="pn-section pn-${SECTION_CSS[section.title] || 'misc'}">
        <h3>${esc(sectionTitle(section.title))} <span class="idb-count">${count}</span></h3>
        ${section.entries?.length ? `<ul class="pn-lines pn-fixes">${listHtml(section.entries, null, true)}</ul>` : ''}
        ${section.subsections?.length ? `<div class="pn-subs">${section.subsections.map(sub => `<div class="pn-sub">${subHeadHtml(sub.name)}<ul class="pn-lines">${listHtml(sub.entries, null, false)}</ul></div>`).join('')}</div>` : ''}
      </section>`;
    }).join('')}
  </article>`;
}

// Filtered patch: only matching lines, grouped by section → subject.
function filteredPatchHtml(patch, i, lines, terms) {
  const bySection = new Map();
  for (const l of lines) {
    if (!bySection.has(l.section)) bySection.set(l.section, []);
    bySection.get(l.section).push(l);
  }
  const ordered = [...bySection.entries()].sort((a, b) => SECTION_KEYS.indexOf(a[0]) - SECTION_KEYS.indexOf(b[0]));
  return `<article class="pn-patch" id="patch-${esc(patch.version)}" data-version="${esc(patch.version)}">
    ${patchHead(patch, i === 0)}
    ${ordered.map(([title, ls]) => {
      const isSubjectSection = ['Items', 'Monsters', 'Characters'].includes(title);
      let body = '';
      if (isSubjectSection) {
        const bySub = new Map();
        for (const l of ls) {
          if (!bySub.has(l.subject)) bySub.set(l.subject, []);
          bySub.get(l.subject).push(l);
        }
        body = `<div class="pn-subs">${[...bySub.entries()].map(([name, sl]) => `<div class="pn-sub">${subHeadHtml(name, terms)}<ul class="pn-lines">${sl.map(l => `<li class="d${Math.min(l.depth, 2)}">${fmt(l.text, terms)}</li>`).join('')}</ul></div>`).join('')}</div>`;
      } else {
        body = `<ul class="pn-lines pn-fixes">${ls.map(l => `<li class="d${Math.min(l.depth, 2)}">${lineHtml(l.text, terms, l.depth === 0)}</li>`).join('')}</ul>`;
      }
      return `<section class="pn-section pn-${SECTION_CSS[title] || 'misc'}"><h3>${esc(sectionTitle(title))} <span class="idb-count">${ls.length}</span></h3>${body}</section>`;
    }).join('')}
  </article>`;
}

// ── Search ────────────────────────────────────────────────────
// Lets "핏빛 장미" or "스나이퍼" find English notes: a whole-query match on a
// localized item/class name is swapped for its English name.
function englishQuery(q) {
  const lq = q.trim().toLowerCase();
  if (!lq || getLocale() === 'en') return q;
  for (const list of Object.values(ROSTER)) {
    for (const cls of list) if (getClassName(cls).toLowerCase() === lq) return cls;
  }
  const item = allItems.find(i => localizedItemName(i).toLowerCase() === lq || (i.koreanname || '').toLowerCase() === lq);
  return item ? item.name : q;
}

function termsOf(q) {
  return englishQuery(q).toLowerCase().trim().split(/\s+/).filter(Boolean);
}

function matchLines(lines, s) {
  const terms = termsOf(s.q);
  return lines.filter(l => {
    if (s.sec && l.section !== s.sec) return false;
    if (!terms.length) return true;
    const hay = (l.subject + ' ' + l.text).toLowerCase();
    return terms.every(x => hay.includes(x));
  });
}

// ── Timeline ──────────────────────────────────────────────────
function timelineHtml(patches, visible) {
  const groups = new Map();
  patches.forEach((p, i) => {
    if (visible && !visible.has(i)) return;
    const k = minorOf(p.version);
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push({ p, i });
  });
  if (!groups.size) return '';
  return [...groups.entries()].map(([minor, list], gi) => {
    const dated = list.map(x => x.p.released).filter(d => /^\d{4}-/.test(d)).sort();
    const range = dated.length ? fmtMonth(dated[dated.length - 1]) : '';
    return `<details class="pn-tl-group" ${gi < 2 ? 'open' : ''}>
      <summary><span>v${esc(minor)}</span><span class="pn-tl-meta">${esc(range)} · ${list.length}</span></summary>
      <div class="pn-tl-list">${list.map(({ p }) => `<a href="#/patch-notes/${esc(p.version)}" class="pn-tl-link" data-jump="${esc(p.version)}">${esc(p.version)}</a>`).join('')}</div>
    </details>`;
  }).join('');
}

// ── Page ──────────────────────────────────────────────────────
function shellHtml(patches, s) {
  const dated = patches.map(p => p.released).filter(d => /^\d{4}-/.test(d)).sort();
  const first = patches[patches.length - 1], last = patches[0];
  const sources = patches.some(p => p.source === 'twrpg-info');
  return `
    <div class="page-header">
      <h1>${t('pn.title')}</h1>
      <p class="page-subtitle">${t('pn.meta', { n: patches.length, from: esc(first?.version || ''), to: esc(last?.version || ''), since: esc(dated.length ? fmtDate(dated[0]) : '') })}</p>
    </div>
    <div class="idb-toolbar">
      <label class="idb-search">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/></svg>
        <input type="search" id="pnSearch" placeholder="${esc(t('pn.search'))}" value="${esc(s.q)}" autocomplete="off" spellcheck="false">
        <kbd>/</kbd>
      </label>
    </div>
    <div class="idb-facets" id="pnFacets"></div>
    <div class="idb-meta" id="pnMeta"></div>
    <div class="pn-layout">
      <div class="pn-list" id="pnList"></div>
      <aside class="pn-timeline" id="pnTimeline" aria-label="${esc(t('pn.timeline'))}"></aside>
    </div>
    ${sources ? `<p class="pn-credit">${t('pn.credit', { link: `<a href="${SOURCE_URL}" target="_blank" rel="noopener">sfarmani/twrpg-info</a>` })}</p>` : ''}
  `;
}

export async function initPatchNotes({ params = {}, query = {} } = {}) {
  const app = document.getElementById('app');
  await loadData();
  const { patches, lines } = await getIndex();
  if (!patches.length) {
    app.innerHTML = `<div class="idb-empty">${t('pn.empty')}</div>`;
    return;
  }

  const s = { q: query.q || '', sec: query.sec || '' };
  app.innerHTML = shellHtml(patches, s);
  const listEl = document.getElementById('pnList');
  const facetsEl = document.getElementById('pnFacets');
  const metaEl = document.getElementById('pnMeta');
  const tlEl = document.getElementById('pnTimeline');
  const searchEl = document.getElementById('pnSearch');

  let rendered = 0;          // unfiltered: how many patches are in the DOM
  let observer = null;
  let filtered = null;       // filtered: Map(patchIndex → lines)

  const syncUrl = () => {
    const p = new URLSearchParams();
    if (s.q) p.set('q', s.q);
    if (s.sec) p.set('sec', s.sec);
    const qs = p.toString();
    history.replaceState(null, '', '#/patch-notes' + (qs ? '?' + qs : ''));
  };

  const renderMore = (upTo = rendered + BATCH) => {
    const end = Math.min(upTo, patches.length);
    if (end <= rendered) return;
    listEl.querySelector('.pn-sentinel')?.remove();
    listEl.insertAdjacentHTML('beforeend', patches.slice(rendered, end).map((p, k) => patchHtml(p, rendered + k)).join(''));
    rendered = end;
    if (rendered < patches.length) {
      listEl.insertAdjacentHTML('beforeend', '<div class="pn-sentinel"></div>');
      observer?.observe(listEl.querySelector('.pn-sentinel'));
    }
  };

  const update = () => {
    observer?.disconnect();
    hideItemTooltip();
    const active = s.q.trim() || s.sec;
    // Section chip counts reflect the search, ignoring the section filter itself.
    const forCounts = matchLines(lines, { ...s, sec: '' });
    const counts = new Map();
    forCounts.forEach(l => counts.set(l.section, (counts.get(l.section) || 0) + 1));
    facetsEl.innerHTML = `<div class="idb-tiers">${['', ...SECTION_KEYS].map(k => {
      const n = k ? counts.get(k) || 0 : forCounts.length;
      return `<button type="button" class="idb-chip pn-chip pn-${SECTION_CSS[k] || 'all'}" data-sec="${esc(k)}" aria-pressed="${s.sec === k}" ${n ? '' : 'disabled'}>${k ? '<i></i>' : ''}${esc(k ? sectionTitle(k) : t('items.all'))}<span>${n}</span></button>`;
    }).join('')}</div>`;

    if (!active) {
      filtered = null;
      metaEl.innerHTML = '';
      listEl.innerHTML = '';
      rendered = 0;
      renderMore();
      tlEl.innerHTML = timelineHtml(patches);
      return;
    }

    const hits = matchLines(lines, s);
    filtered = new Map();
    hits.forEach(l => {
      if (!filtered.has(l.p)) filtered.set(l.p, []);
      filtered.get(l.p).push(l);
    });
    const terms = termsOf(s.q);
    metaEl.innerHTML = `<span>${t('pn.results', { n: hits.length, p: filtered.size })}</span><button type="button" class="idb-link" data-clear>${t('items.clear')}</button>`;
    listEl.innerHTML = filtered.size
      ? [...filtered.entries()].slice(0, 120).map(([p, ls]) => filteredPatchHtml(patches[p], p, ls, terms)).join('')
        + (filtered.size > 120 ? `<p class="pn-more-hint">${t('pn.narrow', { n: filtered.size - 120 })}</p>` : '')
      : `<div class="idb-empty">${t('pn.noResults')}</div>`;
    tlEl.innerHTML = timelineHtml(patches, new Set(filtered.keys()));
  };

  // Scroll a version into view, rendering batches up to it if needed.
  const jumpTo = version => {
    const idx = patches.findIndex(p => p.version === version);
    if (idx < 0) return false;
    if (!filtered) renderMore(idx + 1);
    const el = document.getElementById('patch-' + version);
    if (!el) return false;
    // Patches use content-visibility, so heights above the target settle as they
    // render; re-align for a few frames until the target stays put.
    let tries = 0;
    const align = () => {
      el.scrollIntoView({ block: 'start' });
      if (++tries < 4 && Math.abs(el.getBoundingClientRect().top - 16) > 2) requestAnimationFrame(align);
    };
    align();
    el.classList.add('pn-flash');
    setTimeout(() => el.classList.remove('pn-flash'), 1600);
    return true;
  };

  observer = new IntersectionObserver(entries => {
    if (entries.some(e => e.isIntersecting) && !filtered) renderMore();
  }, { rootMargin: '1200px' });

  const onClick = async e => {
    const chip = e.target.closest('[data-sec]');
    if (chip && !chip.disabled) {
      s.sec = s.sec === chip.dataset.sec ? '' : chip.dataset.sec;
      syncUrl(); update(); return;
    }
    if (e.target.closest('[data-clear]')) {
      s.q = ''; s.sec = ''; searchEl.value = '';
      syncUrl(); update(); return;
    }
    const jump = e.target.closest('[data-jump]');
    if (jump) {
      e.preventDefault();
      jumpTo(jump.dataset.jump);
      return;
    }
    const copy = e.target.closest('[data-copy]');
    if (copy) {
      const url = `${location.origin}${location.pathname}#/patch-notes/${copy.dataset.copy}`;
      try { await navigator.clipboard.writeText(url); showToast(t('pn.linkCopied')); }
      catch (err) { showToast(url); }
    }
  };
  const onKey = e => {
    if (e.key !== '/' || e.ctrlKey || e.metaKey) return;
    const tag = document.activeElement?.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
    e.preventDefault();
    searchEl.focus();
  };

  let debounce = 0;
  searchEl.addEventListener('input', () => {
    clearTimeout(debounce);
    debounce = setTimeout(() => { s.q = searchEl.value; syncUrl(); update(); }, 120);
  });
  app.addEventListener('click', onClick);
  document.addEventListener('keydown', onKey);
  const unbindHover = bindItemHover(listEl);

  update();
  // Deep link: #/patch-notes/v0.69e
  if (params.version) requestAnimationFrame(() => { if (!jumpTo(decodeURIComponent(params.version))) showToast(t('pn.unknownVersion')); });

  return () => {
    observer?.disconnect();
    app.removeEventListener('click', onClick);
    document.removeEventListener('keydown', onKey);
    clearTimeout(debounce);
    unbindHover();
  };
}
