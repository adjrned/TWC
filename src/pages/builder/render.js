import { state } from '../../state.js';
import { COLS } from '../../constants.js';
import { esc } from '../../ui/escape.js';
import { getItem, rankInfo } from '../../data/items.js';
import { getSlotsFor, iconSrc } from './slots.js';
import { deleteRow, renameRow, onDragStart, onDragOver, onDrop, onDragEnd } from './rows.js';
import { openPicker } from './picker.js';
import { openSlotMenu } from './slotMenu.js';
import { getRowName, t } from '../../i18n.js';

function tileHtml(item, cls) {
  const ri = rankInfo(getItem(item.name));
  return `<div class="slot-icon-tile ${cls} ${ri.css}">
    <img src="${esc(iconSrc(item))}" alt="${esc(item.name)}" loading="lazy" decoding="async" onerror="this.parentNode.classList.add('no-img');this.remove()">
    ${cls === 'tile-alt' ? `<span class="tile-alt-tag">${t('builder.altShort')}</span>` : ''}
  </div>`;
}

export function render() {
  const tbody = document.getElementById('tbody');
  if (!tbody) return;
  const hasClass = !!state.selectedClass;
  document.getElementById('bpGrid').hidden = !hasClass;
  document.getElementById('bpEmpty').hidden = hasClass;
  if (!hasClass) { tbody.innerHTML = ''; return; }

  tbody.innerHTML = state.rows.map(row => {
    const slotMap = getSlotsFor(row.id);
    return `<tr data-id="${row.id}" draggable="true">
      <td class="row-cell">
        <div class="row-inner">
          <span class="drag-handle" title="${esc(t('builder.dragHint'))}">⠿</span>
          <input class="row-name-input" value="${esc(getRowName(row.name))}" title="${esc(t('builder.renameHint'))}" aria-label="${esc(t('builder.renameHint'))}">
          <button type="button" class="del-btn" title="${esc(t('builder.removeRow'))}" aria-label="${esc(t('builder.removeRow'))}">✕</button>
        </div>
      </td>
      ${COLS.map(col => {
        const [primary, alt] = slotMap[col] || [];
        const cls = ['slot-drop', primary ? 'filled' : '', alt ? 'has-alt' : ''].filter(Boolean).join(' ');
        return `<td class="slot-cell">
          <button type="button" class="${cls}" data-rowid="${row.id}" data-col="${col}" aria-label="${esc(t('col.' + col))}${primary ? ': ' + esc(primary.name) : ''}">
            ${primary ? tileHtml(primary, 'tile-primary') + (alt ? tileHtml(alt, 'tile-alt') : '') : '<span class="slot-plus">+</span>'}
          </button>
        </td>`;
      }).join('')}
    </tr>`;
  }).join('');

  document.getElementById('emptyState').style.display = state.rows.length === 0 ? 'block' : 'none';
}

// Delegated handlers — bound once per builder visit (see index.js).
export function bindGridEvents(root) {
  const rowIdOf = el => +el.closest('tr').dataset.id;

  const onClick = e => {
    const del = e.target.closest('.del-btn');
    if (del) return deleteRow(rowIdOf(del));
    const drop = e.target.closest('.slot-drop');
    if (!drop) return;
    const rowId = +drop.dataset.rowid, col = drop.dataset.col;
    if (!drop.classList.contains('filled')) return openPicker(rowId, col, 0);
    openSlotMenu(drop, rowId, col);
  };
  const onContext = e => {
    const drop = e.target.closest('.slot-drop.filled');
    if (!drop) return;
    e.preventDefault();
    openSlotMenu(drop, +drop.dataset.rowid, drop.dataset.col, e.clientX, e.clientY);
  };
  const onChange = e => {
    const input = e.target.closest('.row-name-input');
    if (input) renameRow(rowIdOf(input), input.value);
  };
  const onDrag = e => {
    const tr = e.target.closest?.('tr[data-id]');
    if (!tr) return;
    const id = +tr.dataset.id;
    if (e.type === 'dragstart') onDragStart(e, id);
    else if (e.type === 'dragover') onDragOver(e, id);
    else if (e.type === 'drop') onDrop(e, id);
  };

  root.addEventListener('click', onClick);
  root.addEventListener('contextmenu', onContext);
  root.addEventListener('change', onChange);
  root.addEventListener('focusout', onChange);
  for (const ev of ['dragstart', 'dragover', 'drop']) root.addEventListener(ev, onDrag);
  root.addEventListener('dragend', onDragEnd);

  return () => {
    root.removeEventListener('click', onClick);
    root.removeEventListener('contextmenu', onContext);
    root.removeEventListener('change', onChange);
    root.removeEventListener('focusout', onChange);
    for (const ev of ['dragstart', 'dragover', 'drop']) root.removeEventListener(ev, onDrag);
    root.removeEventListener('dragend', onDragEnd);
  };
}
