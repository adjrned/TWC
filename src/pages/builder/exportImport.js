import { state } from '../../state.js';
import { COLS, buildFileName, buildFileNameForCreator } from '../../constants.js';
import { importExportBuildData } from '../../data/builds.js';
import { save } from '../../data/storage.js';
import { showToast } from '../../ui/toast.js';
import { t } from '../../i18n.js';
import { syncClassUI } from './classPicker.js';
import { render } from './render.js';
import { buildShareUrl } from './share.js';

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
  showToast(t('builder.exported'));
}

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
  } catch (e) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.cssText = 'position:fixed;opacity:0;pointer-events:none';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
  }
}

export async function copyToClipboard() {
  if (!state.selectedClass) { showToast(t('builder.selectFirst')); return; }
  await copyText(JSON.stringify(buildExportJson(), null, 2));
  showToast(t('builder.jsonCopied'));
}

export async function copyShareLink() {
  if (!state.selectedClass) { showToast(t('builder.selectFirst')); return; }
  await copyText(await buildShareUrl());
  showToast(t('builder.linkCopied'));
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
    if (!importExportBuildData(d)) { showToast(t('builder.badFormat')); return; }
    save(); syncClassUI(); render(); closeImport(); showToast(t('builder.imported'));
  } catch(e) { showToast(t('builder.badJson')); }
}
