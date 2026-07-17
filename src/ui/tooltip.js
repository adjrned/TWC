import { state } from '../state.js';
import { LABELS } from '../constants.js';
import { getSlotArr, iconSrc } from '../pages/builder/slots.js';

let ttTarget = null;

export function initTooltip() {
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
          document.getElementById('ftName').textContent = item.name;
          document.getElementById('ftSlot').textContent = (isAlt ? 'Alt — ' : '') + (LABELS[col] || col);
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
