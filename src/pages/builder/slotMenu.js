import { state } from '../../state.js';
import { esc } from '../../ui/escape.js';
import { t } from '../../i18n.js';
import { getItem, rankInfo, localizedNameByName } from '../../data/items.js';
import { hideItemTooltip } from '../../ui/tooltip.js';
import { getSlotArr, clearSlot, clearSlotItem, swapSlotItems } from './slots.js';
import { openPicker } from './picker.js';

// One menu for both tap/click and right-click on a filled slot.
let menu = null;
let anchorEl = null;

function ensureMenu() {
  if (menu) return menu;
  menu = document.createElement('div');
  menu.id = 'slotMenu';
  menu.setAttribute('role', 'menu');
  menu.hidden = true;
  document.body.appendChild(menu);
  menu.addEventListener('click', onMenuClick);
  return menu;
}

function itemLine(item, label) {
  if (!item) return '';
  const ri = rankInfo(getItem(item.name));
  return `<div class="sm-item ${ri.css}"><span class="sm-tag">${label}</span><span class="sm-name">${esc(localizedNameByName(item.name))}</span></div>`;
}

export function openSlotMenu(drop, rowId, col, clientX = null, clientY = null) {
  const m = ensureMenu();
  closeSlotMenu();
  const [primary, alt] = getSlotArr(rowId, col);
  if (!primary) return;
  hideItemTooltip();
  state.ctxRowId = rowId;
  state.ctxCol = col;
  anchorEl = drop;
  drop.classList.add('pop-open');

  m.innerHTML = `
    ${itemLine(primary, t('builder.primary'))}
    ${itemLine(alt, t('builder.alt'))}
    <hr>
    <button type="button" role="menuitem" data-act="change">${t('builder.changeItem')}</button>
    <button type="button" role="menuitem" data-act="alt">${t(alt ? 'builder.changeAlt' : 'builder.addAlt')}</button>
    ${alt ? `<button type="button" role="menuitem" data-act="swap">${t('builder.swap')}</button>` : ''}
    <a role="menuitem" href="#/items/${encodeURIComponent(primary.name)}">${t('builder.viewItem')}</a>
    <hr>
    ${alt ? `<button type="button" role="menuitem" class="danger" data-act="clearAlt">${t('builder.removeAlt')}</button>` : ''}
    <button type="button" role="menuitem" class="danger" data-act="clear">${t('builder.clearSlot')}</button>
  `;
  m.hidden = false;

  // Position: at the cursor for right-click, otherwise under the slot; keep on-screen.
  const r = drop.getBoundingClientRect();
  const w = m.offsetWidth, h = m.offsetHeight, pad = 8;
  let x = clientX ?? r.left;
  let y = clientY ?? r.bottom + 4;
  if (clientY == null && y + h > window.innerHeight - pad) y = r.top - h - 4;
  x = Math.max(pad, Math.min(x, window.innerWidth - w - pad));
  y = Math.max(pad, Math.min(y, window.innerHeight - h - pad));
  m.style.transform = `translate(${Math.round(x)}px, ${Math.round(y)}px)`;
  m.querySelector('button')?.focus({ preventScroll: true });
}

export function closeSlotMenu() {
  if (menu) menu.hidden = true;
  anchorEl?.classList.remove('pop-open');
  anchorEl = null;
}

export function isSlotMenuOpen() {
  return !!menu && !menu.hidden;
}

function onMenuClick(e) {
  const el = e.target.closest('[data-act], a');
  if (!el) return;
  const rowId = state.ctxRowId, col = state.ctxCol;
  const act = el.dataset.act;
  closeSlotMenu();
  if (act === 'change') openPicker(rowId, col, 0);
  else if (act === 'alt') openPicker(rowId, col, 1);
  else if (act === 'swap') swapSlotItems(rowId, col);
  else if (act === 'clearAlt') clearSlotItem(rowId, col, 1);
  else if (act === 'clear') clearSlot(rowId, col);
}

// Global listeners (installed once): outside click, Escape, scroll/resize close the menu.
let bound = false;
export function bindSlotMenuGlobals() {
  if (bound) return;
  bound = true;
  document.addEventListener('pointerdown', e => {
    if (isSlotMenuOpen() && !e.target.closest('#slotMenu') && !e.target.closest('.slot-drop.pop-open')) closeSlotMenu();
  });
  document.addEventListener('keydown', e => {
    if (!isSlotMenuOpen()) return;
    if (e.key === 'Escape') { closeSlotMenu(); return; }
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const items = [...menu.querySelectorAll('button, a')];
      const i = items.indexOf(document.activeElement);
      items[(i + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length]?.focus();
    }
  });
  window.addEventListener('scroll', () => isSlotMenuOpen() && closeSlotMenu(), { passive: true, capture: true });
  window.addEventListener('resize', () => isSlotMenuOpen() && closeSlotMenu());
  window.addEventListener('hashchange', closeSlotMenu);
}
