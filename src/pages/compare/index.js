import { esc } from '../../ui/escape.js';
import { t, getTypeName } from '../../i18n.js';
import {
  loadItems, getItem, rankInfo, formatStat, formatDropRate, dropRates, STAT_LABELS, AFFINITY_ELEMENT,
  localizedItemName,
} from '../../data/items.js';
import { getPins, setPins, togglePin, onPinsChange, COMPARE_MAX } from '../../data/compare.js';
import { iconHtml } from '../../ui/itemUi.js';
import { showToast } from '../../ui/toast.js';

// Stats where a lower (more negative) value is the better one.
const LOWER_IS_BETTER = new Set(['dtpercent', 'revivaltimepercent']);

function itemHref(name) {
  return `#/items/${encodeURIComponent(name)}`;
}

function headCell(item) {
  const ri = rankInfo(item);
  return `<th class="cmp-head ${ri.css}" scope="col">
    <button type="button" class="cmp-remove" data-remove="${esc(item.name)}" aria-label="${esc(t('compare.remove'))}" title="${esc(t('compare.remove'))}">×</button>
    <a href="${itemHref(item.name)}" class="cmp-head-link">
      ${iconHtml(item.name, 'cmp-icon')}
      <span class="cmp-name">${esc(localizedItemName(item))}</span>
    </a>
    <span class="cmp-sub">${[ri.label, getTypeName(item.type || ''), item.level ? `${t('items.lv')} ${item.level}` : ''].filter(Boolean).map(esc).join(' · ')}</span>
  </th>`;
}

function statRows(items) {
  // Union of numeric stats, in canonical label order.
  const keys = Object.keys(STAT_LABELS).filter(k => items.some(i => typeof i.stats?.[k] === 'number'));
  return keys.map(k => {
    const vals = items.map(i => (typeof i.stats?.[k] === 'number' ? i.stats[k] : null));
    const present = vals.filter(v => v !== null);
    const best = LOWER_IS_BETTER.has(k) ? Math.min(...present) : Math.max(...present);
    // Only highlight when it actually distinguishes items.
    const highlight = items.length > 1 && (present.length < items.length || new Set(present).size > 1);
    const aff = AFFINITY_ELEMENT[k] ? ` is-affinity affinity-${AFFINITY_ELEMENT[k]}` : '';
    return `<tr class="cmp-stat${aff}">
      <th scope="row">${esc(STAT_LABELS[k])}</th>
      ${vals.map(v => v === null
        ? '<td class="cmp-none">—</td>'
        : `<td class="${highlight && v === best ? 'cmp-best' : ''}">${formatStat(k, v)}</td>`).join('')}
    </tr>`;
  }).join('');
}

function textRow(label, items, fn, cls = '') {
  const cells = items.map(fn);
  if (cells.every(c => !c)) return '';
  return `<tr class="cmp-text ${cls}"><th scope="row">${label}</th>${cells.map(c => `<td>${c || '<span class="cmp-none">—</span>'}</td>`).join('')}</tr>`;
}

const lines = arr => arr?.length ? `<ul class="cmp-lines">${arr.map(l => `<li>${esc(l)}</li>`).join('')}</ul>` : '';

function renderTable(items) {
  return `
    <div class="cmp-scroll">
      <table class="cmp-table" style="--cols:${items.length}">
        <thead><tr><th class="cmp-corner" scope="col"></th>${items.map(headCell).join('')}</tr></thead>
        <tbody>
          ${statRows(items)}
          ${textRow(t('items.passive'), items, i => lines(i.stats?.passive), 'fx-passive')}
          ${textRow(t('items.active'), items, i => lines(i.stats?.active), 'fx-active')}
          ${textRow(t('items.spec'), items, i => (i.stats?.spec?.length > 1 ? esc(i.stats.spec[1]) : ''))}
          ${textRow(t('items.dropsFrom'), items, i => (i.dropped_by?.length
            ? dropRates(i).map(({ boss, rate }) => esc(boss) + (rate ? ` <span class="cmp-rate">${formatDropRate(rate)}</span>` : '')).join('<br>')
            : ''))}
        </tbody>
      </table>
    </div>`;
}

function renderPage(items, allItems) {
  const full = items.length >= COMPARE_MAX;
  return `
    <div class="page-header page-header-actions">
      <div class="page-header-titles">
        <h1>${t('compare.title')}</h1>
        <p class="page-subtitle">${t('compare.subtitle', { n: COMPARE_MAX })}</p>
      </div>
      <div class="header-actions">
        <button type="button" class="btn" data-share ${items.length ? '' : 'disabled'}>${t('compare.share')}</button>
        <button type="button" class="btn danger-btn" data-clear ${items.length ? '' : 'disabled'}>${t('compare.clear')}</button>
      </div>
    </div>
    <div class="cmp-add">
      <label class="idb-search">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>
        <input type="search" id="cmpAdd" list="cmpAddList" placeholder="${esc(full ? t('compare.full', { n: COMPARE_MAX }) : t('compare.addPlaceholder'))}" ${full ? 'disabled' : ''} autocomplete="off">
      </label>
      <datalist id="cmpAddList">
        ${allItems.filter(i => i.stats).map(i => `<option value="${esc(i.name)}">${esc(localizedItemName(i) !== i.name ? localizedItemName(i) : '')}</option>`).join('')}
      </datalist>
    </div>
    ${items.length
      ? renderTable(items)
      : `<div class="idb-empty">${t('compare.empty')} <a class="idb-link" href="#/items">${t('items.title')}</a></div>`}
  `;
}

export async function initCompare({ query }) {
  const app = document.getElementById('app');
  const allItems = await loadItems();

  // A shared link (?i=A|B) replaces the current pins.
  if (query.i) setPins(query.i.split('|').filter(n => getItem(n)));

  const draw = () => {
    const items = getPins().map(getItem).filter(Boolean);
    const qs = items.length ? '?i=' + items.map(i => encodeURIComponent(i.name)).join('|') : '';
    history.replaceState(null, '', '#/items/compare' + qs);
    app.innerHTML = renderPage(items, allItems);
    const input = document.getElementById('cmpAdd');
    input?.addEventListener('change', () => {
      const item = getItem(input.value.trim());
      if (item && !getPins().includes(item.name)) togglePin(item.name);
      else input.value = '';
    });
  };

  const onClick = async e => {
    const rm = e.target.closest('[data-remove]');
    if (rm) return togglePin(rm.dataset.remove);
    if (e.target.closest('[data-clear]')) return setPins([]);
    if (e.target.closest('[data-share]')) {
      try { await navigator.clipboard.writeText(location.href); } catch (err) {}
      showToast(t('compare.linkCopied'));
    }
  };

  app.addEventListener('click', onClick);
  const off = onPinsChange(draw);
  draw();
  if (!getPins().length) document.getElementById('cmpAdd')?.focus();

  return () => {
    off();
    app.removeEventListener('click', onClick);
  };
}
