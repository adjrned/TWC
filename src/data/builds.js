import { state } from '../state.js';
import { COLS, ICONS_PATH, buildFileName, buildFileNameForCreator } from '../constants.js';
import { save } from './storage.js';

let _buildsIndexCache = null;

export async function getBuildsIndex() {
  if (_buildsIndexCache !== null) return _buildsIndexCache;
  try {
    const r = await fetch('builds/index.json');
    if (r.ok) { _buildsIndexCache = await r.json(); return _buildsIndexCache; }
  } catch(e) {}
  _buildsIndexCache = [];
  return _buildsIndexCache;
}

export async function fetchBuildCountsForAllClasses() {
  const files = await getBuildsIndex();
  const counts = {};
  for (const f of files) {
    if (!f.endsWith('.json')) continue;
    const stem = f.slice(0, -5);
    const parts = stem.split('.');
    if (parts.length < 1) continue;
    const className = parts[0].replace(/_/g, ' ');
    counts[className] = (counts[className] || 0) + 1;
  }
  return counts;
}

export async function fetchCreatorsForClass(className) {
  const files = await getBuildsIndex();
  const prefix = className.replace(/\s+/g,'_') + '.';
  return files
    .filter(f => f.startsWith(prefix) && f.endsWith('.json'))
    .map(f => {
      const stem = f.slice(prefix.length, -5);
      return stem ? stem.replace(/_/g,' ') : null;
    })
    .filter(Boolean);
}

export function normalizeItem(raw) {
  if (!raw?.name) return null;
  return { type: raw.type || 'library', name: raw.name, src: raw.src || ICONS_PATH + encodeURIComponent(raw.name) + '.jpg' };
}

export function normalizeSlotToArray(raw) {
  if (!raw) return [];
  if (Array.isArray(raw)) return raw.map(normalizeItem).filter(Boolean).slice(0, 2);
  const item = normalizeItem(raw);
  return item ? [item] : [];
}

export function importExportBuildData(data) {
  if (!data?.class || !Array.isArray(data.rows)) return false;
  const cls = data.class;
  const importedRows = data.rows.map(r => ({ id: state.uid++, name: r.name || 'Row' }));
  const importedBuilds = { [cls]: {} };
  importedRows.forEach((localRow, i) => {
    const slots = data.rows[i]?.slots || {};
    importedBuilds[cls][localRow.id] = {};
    COLS.forEach(col => {
      const arr = normalizeSlotToArray(slots[col]);
      if (arr.length) importedBuilds[cls][localRow.id][col] = arr;
    });
  });
  state.rows = importedRows;
  state.builds = importedBuilds;
  state.selectedClass = cls;
  state.creatorName = data.createdBy || '';
  return true;
}

export function importLegacyBuildFile(data, className) {
  if (!data || !Array.isArray(data.rows) || !data.builds?.[className]) return false;
  const importedRows = data.rows.map(r => ({ id: state.uid++, name: r.name || 'Row' }));
  const idMap = new Map();
  data.rows.forEach((r, i) => idMap.set(String(r.id), importedRows[i].id));
  const importedBuilds = { [className]: {} };
  for (const [oldId, slotGroup] of Object.entries(data.builds[className])) {
    const newId = idMap.get(String(oldId));
    if (newId == null) continue;
    importedBuilds[className][newId] = {};
    COLS.forEach(col => {
      const arr = normalizeSlotToArray(slotGroup[col]);
      if (arr.length) importedBuilds[className][newId][col] = arr;
    });
  }
  state.rows = importedRows;
  state.builds = importedBuilds;
  state.selectedClass = className;
  state.creatorName = data.createdBy || '';
  return true;
}

export function hasLocalData(className) {
  if (!state.builds[className]) return false;
  return Object.values(state.builds[className]).some(
    rowSlots => rowSlots && Object.values(rowSlots).some(arr => Array.isArray(arr) && arr.length > 0)
  );
}

export async function loadBuildFile(className, creator) {
  if (!className) return false;
  if (hasLocalData(className)) return false;
  const urls = [];
  if (creator) urls.push('builds/' + buildFileNameForCreator(className, creator));
  urls.push('builds/' + buildFileName(className));
  for (const url of urls) {
    try {
      const r = await fetch(url);
      if (!r.ok) continue;
      const data = await r.json();
      if (importExportBuildData(data) || importLegacyBuildFile(data, className)) { save(); return true; }
    } catch(e) {}
  }
  return false;
}
