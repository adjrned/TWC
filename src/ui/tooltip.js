import { getSlotArr } from '../pages/builder/slots.js';
import { t } from '../i18n.js';
import { esc } from './escape.js';
import {
  loadItems, getItemCI, rankInfo, numericStats, formatStat,
  STAT_LABELS, AFFINITY_ELEMENT, localizedItemName, localizedNameByName,
} from '../data/items.js';

let ttTarget = null;
let initialized = false;

// Game-style tooltip body: tier, numeric stats, passive / active text.
export function buildStatsHtml(dbItem) {
  if (!dbItem) return '';
  const parts = [];
  const ri = rankInfo(dbItem);
  const meta = [ri.label, dbItem.type, dbItem.level ? `${t('items.lv')} ${dbItem.level}` : ''].filter(Boolean);
  if (meta.length) parts.push(`<div class="tt-tier ${ri.css}">${esc(meta.join(' · '))}</div>`);

  const stats = numericStats(dbItem);
  if (stats.length) {
    parts.push(`<div class="tt-stat-block">${stats.map(([k, v]) => {
      const aff = AFFINITY_ELEMENT[k] ? ` is-affinity affinity-${AFFINITY_ELEMENT[k]}` : '';
      return `<div class="tt-stat-line${aff}"><span class="tt-stat-label">${esc(STAT_LABELS[k] || k)}</span><span class="tt-stat-val">${formatStat(k, v)}</span></div>`;
    }).join('')}</div>`);
  }
  if (dbItem.stats?.passive?.length) {
    parts.push(`<div class="tt-passive">${dbItem.stats.passive.map(l => `<div>${esc(l)}</div>`).join('')}</div>`);
  }
  if (dbItem.stats?.active?.length) {
    parts.push(`<div class="tt-active"><span class="tt-active-label">${t('items.active')}</span>${dbItem.stats.active.map(l => `<div>${esc(l)}</div>`).join('')}</div>`);
  }
  if (dbItem.description && !dbItem.stats) {
    parts.push(`<div class="tt-desc">${esc(dbItem.description)}</div>`);
  }
  return parts.join('');
}

// Position the floating tooltip near (x, y), flipping below the cursor when
// there is no room above and clamping to the viewport horizontally.
function place(ft, x, y) {
  const pad = 12;
  const w = ft.offsetWidth;
  const h = ft.offsetHeight;
  let left = Math.min(Math.max(x - w / 2, pad), window.innerWidth - w - pad);
  let top = y - h - 18;
  if (top < pad) top = y + 22;
  ft.style.transform = `translate(${Math.round(left)}px, ${Math.round(top)}px)`;
}

export function showItemTooltip(dbItem, x, y, slotLabel = '') {
  const ft = document.getElementById('floatTooltip');
  if (!ft || !dbItem) return;
  const ri = rankInfo(dbItem);
  const name = document.getElementById('ftName');
  name.textContent = localizedItemName(dbItem);
  name.className = `tt-name ${ri.css}`;
  document.getElementById('ftSlot').textContent = slotLabel;
  document.getElementById('ftStats').innerHTML = buildStatsHtml(dbItem);
  ft.classList.add('show');
  place(ft, x, y);
}

export function moveItemTooltip(x, y) {
  const ft = document.getElementById('floatTooltip');
  if (ft?.classList.contains('show')) place(ft, x, y);
}

export function hideItemTooltip() {
  document.getElementById('floatTooltip')?.classList.remove('show');
}

export function initTooltip() {
  loadItems();
  // The builder re-inits on every visit; only ever attach one listener.
  if (initialized) return;
  initialized = true;

  document.addEventListener('mousemove', e => {
    const drop = e.target.closest?.('.slot-drop.filled');
    if (drop && !drop.classList.contains('pop-open')) {
      const tile = e.target.closest('.slot-icon-tile');
      const isAlt = tile?.classList.contains('tile-alt');
      const col = drop.dataset.col;
      const hoverKey = drop.dataset.rowid + col + (isAlt ? '1' : '0');
      if (ttTarget !== hoverKey) {
        ttTarget = hoverKey;
        const arr = getSlotArr(parseInt(drop.dataset.rowid), col);
        const item = isAlt ? (arr[1] || arr[0]) : (arr[0] || null);
        if (item) {
          const dbItem = getItemCI(item.name) || { name: item.name };
          showItemTooltip(dbItem, e.clientX, e.clientY, (isAlt ? 'Alt — ' : '') + t('col.' + col));
          if (!getItemCI(item.name)) document.getElementById('ftName').textContent = localizedNameByName(item.name);
        }
      } else {
        moveItemTooltip(e.clientX, e.clientY);
      }
    } else if (ttTarget) {
      hideItemTooltip();
      ttTarget = null;
    }
  });
}
