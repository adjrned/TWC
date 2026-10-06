import { esc } from './escape.js';
import { t } from '../i18n.js';
import { getPins, togglePin, setPins, onPinsChange } from '../data/compare.js';
import { rankInfo, getItem, localizedNameByName, loadItems } from '../data/items.js';
import { iconHtml } from './itemUi.js';

// Floating tray listing pinned items; shown on item database pages only.
let tray = null;

function visible() {
  const h = location.hash;
  return getPins().length > 0 && h.startsWith('#/items') && !h.startsWith('#/items/compare');
}

function render() {
  if (!tray) return;
  const pins = getPins();
  tray.hidden = !visible();
  document.body.classList.toggle('has-compare-tray', !tray.hidden);
  if (tray.hidden) return;
  tray.innerHTML = `
    <div class="ct-items">
      ${pins.map(n => `
        <span class="ct-item ${rankInfo(getItem(n)).css}" title="${esc(localizedNameByName(n))}">
          ${iconHtml(n, 'ct-icon')}
          <button type="button" class="ct-remove" data-remove="${esc(n)}" aria-label="${esc(t('compare.remove'))}">×</button>
        </span>`).join('')}
    </div>
    <button type="button" class="ct-clear" data-clear>${t('compare.clear')}</button>
    <a class="btn primary ct-open" href="#/items/compare">${t('compare.open', { n: pins.length })}</a>
  `;
}

export function initCompareTray() {
  tray = document.createElement('div');
  tray.id = 'compareTray';
  tray.hidden = true;
  document.body.appendChild(tray);
  tray.addEventListener('click', e => {
    const rm = e.target.closest('[data-remove]');
    if (rm) togglePin(rm.dataset.remove);
    else if (e.target.closest('[data-clear]')) setPins([]);
  });
  onPinsChange(render);
  window.addEventListener('hashchange', render);
  // Tier colours / names need the item DB.
  loadItems().then(render);
}
