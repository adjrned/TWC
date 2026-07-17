import { state } from '../state.js';
import { COLS, STORAGE_KEY } from '../constants.js';
import { normalizeSlotToArray } from './builds.js';

export function save() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({
      rows: state.rows,
      builds: state.builds,
      selectedClass: state.selectedClass,
      selectedCreator: state.selectedCreator,
    }));
  } catch(e) {}
}

export function load() {
  try {
    let d = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
    if (!d) d = JSON.parse(localStorage.getItem('twrpg_v6') || 'null');
    if (d) {
      state.rows = (d.rows || []).map(r => ({ ...r }));
      const maxId = state.rows.reduce((m, r) => Math.max(m, r.id ?? -1), -1);
      state.uid = maxId + 1;
      state.builds = {};
      for (const [cls, rowMap] of Object.entries(d.builds || {})) {
        state.builds[cls] = {};
        for (const [rowId, slotGroup] of Object.entries(rowMap)) {
          state.builds[cls][rowId] = {};
          COLS.forEach(col => {
            const arr = normalizeSlotToArray(slotGroup[col]);
            if (arr.length) state.builds[cls][rowId][col] = arr;
          });
        }
      }
      state.selectedClass = d.selectedClass || null;
      state.selectedCreator = d.selectedCreator || null;
    }
  } catch(e) {}
}
