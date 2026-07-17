import { state } from '../state.js';
import { LABELS } from '../constants.js';
import { getSlotArr, iconSrc } from '../pages/builder/slots.js';
import { t, getLocale } from '../i18n.js';
import { translateItemName } from '../data/translate.js';

let ttTarget = null;
let itemDb = null;
let itemDbLoading = false;

async function loadItemDb() {
  if (itemDb || itemDbLoading) return;
  itemDbLoading = true;
  try {
    const r = await fetch('data/items.json');
    if (r.ok) itemDb = await r.json();
  } catch(e) {}
  if (!itemDb) itemDb = [];
  itemDbLoading = false;
}

function findItem(name) {
  if (!itemDb) return null;
  return itemDb.find(i => i.name.toLowerCase() === name.toLowerCase());
}

function buildStatsHtml(dbItem) {
  if (!dbItem) return '';
  const parts = [];
  if (dbItem.description) {
    parts.push(`<div class="tt-desc">${dbItem.description}</div>`);
  }
  const tierLabel = getTierLabel(dbItem);
  if (tierLabel) {
    parts.push(`<div class="tt-tier">${tierLabel}</div>`);
  }
  if (dbItem.koreanname) {
    parts.push(`<div class="tt-korean">${dbItem.koreanname}</div>`);
  }
  return parts.join('');
}

function getTierLabel(item) {
  if (item.rank === '[Epic]' && item.grade >= 1) {
    const tiers = { 1: 'Deltirama', 2: 'Neptinos', 3: 'Gnosis', 4: 'Alteia', 5: 'Arcana' };
    return tiers[item.grade] || '';
  }
  const map = { '[Normal]': 'Normal', '[Magic]': 'Magic', '[Rare]': 'Rare' };
  return map[item.rank] || '';
}

export function initTooltip() {
  loadItemDb();

  document.addEventListener('mousemove', e => {
    const drop = e.target.closest('.slot-drop.filled');
    if (drop && !drop.classList.contains('pop-open')) {
      const ft = document.getElementById('floatTooltip');
      ft.style.left = e.clientX + 'px';
      ft.style.top = e.clientY + 'px';
      const tile = e.target.closest('.slot-icon-tile');
      const isAlt = tile?.classList.contains('tile-alt');
      const rowId = parseInt(drop.dataset.rowid);
      const col = drop.dataset.col;
      const arr = getSlotArr(rowId, col);
      const item = isAlt ? (arr[1] || arr[0]) : (arr[0] || null);
      const hoverKey = drop.dataset.rowid + col + (isAlt ? '1' : '0');
      if (ttTarget !== hoverKey) {
        ttTarget = hoverKey;
        if (item) {
          document.getElementById('ftImg').src = iconSrc(item);
          document.getElementById('ftName').textContent = translateItemName(item.name, getLocale());
          document.getElementById('ftSlot').textContent = (isAlt ? 'Alt — ' : '') + t('col.' + col);
          const dbItem = findItem(item.name);
          document.getElementById('ftStats').innerHTML = buildStatsHtml(dbItem);
          ft.classList.add('show');
        }
      }
    } else {
      if (ttTarget) {
        document.getElementById('floatTooltip').classList.remove('show');
        ttTarget = null;
      }
    }
  });
}
