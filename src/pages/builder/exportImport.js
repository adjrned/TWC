import { state } from '../../state.js';
import { COLS, buildFileName, buildFileNameForCreator } from '../../constants.js';
import { importExportBuildData } from '../../data/builds.js';
import { save } from '../../data/storage.js';
import { showToast } from '../../ui/toast.js';
import { syncClassUI } from './classPicker.js';
import { render } from './render.js';

export function buildExportJson() {
  return {
    class: state.selectedClass,
    createdBy: state.creatorName || undefined,
    publishedAt: new Date().toISOString(),
    rows: state.rows.map(r => ({
      id: r.id, name: r.name,
      slots: Object.fromEntries(COLS.map(col => {
        const arr = ((state.builds[state.selectedClass]||{})[r.id]||{})[col];
        if (!arr?.length) return [col, null];
        const exp = arr.map(item => item ? { name: item.name, src: item.src||null } : null).filter(Boolean);
        return [col, exp.length ? exp : null];
      }))
    }))
  };
}

export function exportData() {
  const out = buildExportJson();
  const blob = new Blob([JSON.stringify(out,null,2)], { type:'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  const dlName = state.selectedClass
    ? (state.selectedCreator ? buildFileNameForCreator(state.selectedClass, state.selectedCreator) : buildFileName(state.selectedClass))
    : 'twrpg-builds.json';
  a.download = dlName;
  a.click();
  showToast('Exported! Commit to builds/ folder to publish.');
}

export async function copyToClipboard() {
  if (!state.selectedClass) { showToast('Select a hero class first!'); return; }
  const json = JSON.stringify(buildExportJson(), null, 2);
  try {
    await navigator.clipboard.writeText(json);
    showToast('JSON copied to clipboard!');
  } catch(e) {
    const ta = document.createElement('textarea');
    ta.value = json;
    ta.style.cssText = 'position:fixed;opacity:0;pointer-events:none';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
    showToast('JSON copied to clipboard!');
  }
}

export function openImport() {
  document.getElementById('importModal').classList.add('show');
}

export function closeImport() {
  document.getElementById('importModal').classList.remove('show');
}

export function doImport() {
  try {
    const d = JSON.parse(document.getElementById('importText').value.trim());
    if (!importExportBuildData(d)) { showToast('Unrecognised format.'); return; }
    save(); syncClassUI(); render(); closeImport(); showToast('Imported!');
  } catch(e) { showToast('Invalid JSON — check your data.'); }
}
