import { state } from '../../state.js';
import { COLS } from '../../constants.js';
import { esc } from '../../ui/escape.js';
import { getSlotsFor, iconSrc } from './slots.js';
import { deleteRow, renameRow, onDragStart, onDragOver, onDrop, onDragEnd } from './rows.js';
import { openPicker } from './picker.js';
import { openCtx } from './contextMenu.js';

export function render() {
  const tbody = document.getElementById('tbody');
  tbody.innerHTML = '';
  const locked = !state.selectedClass;

  state.rows.forEach(row => {
    const slotMap = getSlotsFor(row.id);
    const tr = document.createElement('tr');
    tr.dataset.id = row.id;
    tr.draggable = true;
    tr.addEventListener('dragstart', e => onDragStart(e, row.id));
    tr.addEventListener('dragover', e => onDragOver(e, row.id));
    tr.addEventListener('drop', e => onDrop(e, row.id));
    tr.addEventListener('dragend', onDragEnd);

    const tdName = document.createElement('td');
    tdName.className = 'row-cell';
    tdName.innerHTML = `<div class="row-inner">
      <span class="drag-handle" title="Drag to reorder">⠿</span>
      <input class="row-name-input" value="${esc(row.name)}" title="Click to rename">
      <button class="del-btn">✕</button>
    </div>`;
    const nameInput = tdName.querySelector('.row-name-input');
    nameInput.addEventListener('change', () => renameRow(row.id, nameInput.value));
    nameInput.addEventListener('blur', () => renameRow(row.id, nameInput.value));
    tdName.querySelector('.del-btn').addEventListener('click', () => deleteRow(row.id));
    tr.appendChild(tdName);

    COLS.forEach(col => {
      const td = document.createElement('td');
      td.className = 'slot-cell';
      const arr = slotMap[col] || [];
      const primary = arr[0] || null;
      const alt = arr[1] || null;

      const drop = document.createElement('div');
      drop.className = ['slot-drop', primary?'filled':'', alt?'has-alt':'', locked?'locked':''].filter(Boolean).join(' ');
      drop.dataset.rowid = row.id;
      drop.dataset.col = col;

      if (primary) {
        const tileP = document.createElement('div');
        tileP.className = 'slot-icon-tile tile-primary';
        const imgP = document.createElement('img');
        imgP.className = 'slot-img-primary';
        imgP.src = iconSrc(primary);
        imgP.alt = primary.name;
        imgP.onerror = () => { imgP.remove(); const p = document.createElement('span'); p.className='slot-plus'; p.textContent='+'; tileP.appendChild(p); };
        tileP.appendChild(imgP);
        drop.appendChild(tileP);

        if (alt) {
          const tileA = document.createElement('div');
          tileA.className = 'slot-icon-tile tile-alt';
          const imgA = document.createElement('img');
          imgA.className = 'slot-img-alt';
          imgA.src = iconSrc(alt);
          imgA.alt = alt.name;
          imgA.onerror = () => { imgA.remove(); const p = document.createElement('span'); p.className='slot-plus'; p.textContent='+'; tileA.appendChild(p); };
          tileA.appendChild(imgA);
          drop.appendChild(tileA);
        }
      } else {
        const plus = document.createElement('span');
        plus.className = 'slot-plus';
        plus.textContent = locked ? '·' : '+';
        drop.appendChild(plus);
      }

      if (!locked) {
        drop.addEventListener('click', e => {
          const tile = e.target.closest('.slot-icon-tile');
          if (tile) {
            const idx = tile.classList.contains('tile-alt') ? 1 : 0;
            openPicker(row.id, col, idx);
          } else if (!primary) {
            openPicker(row.id, col, 0);
          }
        });
        drop.addEventListener('contextmenu', e => openCtx(e, row.id, col));
        const anchor = document.createElement('div');
        anchor.className = 'slot-popover-anchor';
        drop.appendChild(anchor);
      }

      td.appendChild(drop);
      tr.appendChild(td);
    });

    tbody.appendChild(tr);
  });

  document.getElementById('emptyState').style.display = state.rows.length === 0 ? 'block' : 'none';
}
