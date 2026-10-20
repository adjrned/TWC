import { state } from '../../state.js';
import { DEFAULT_ROWS } from '../../constants.js';
import { hasLocalData, loadBuildFile, importExportBuildData } from '../../data/builds.js';
import { t, getClassName } from '../../i18n.js';
import { chooseBuild } from './buildBrowser.js';
import { save, load } from '../../data/storage.js';
import { loadItems } from '../../data/items.js';
import { initTooltip, hideItemTooltip } from '../../ui/tooltip.js';
import { buildClassSelect, syncClassUI, toggleClassDropdown, toggleBuildBrowser, resetToTemplate, clearAllRows, updateBuildHash } from './classPicker.js';
import { render, bindGridEvents } from './render.js';
import { addRow } from './rows.js';
import { closePicker } from './picker.js';
import { closeSlotMenu, bindSlotMenuGlobals } from './slotMenu.js';
import { openImport, closeImport, doImport, exportData, copyToClipboard, copyShareLink } from './exportImport.js';
import { builderHTML } from './template.js';
import { decodeShareCode } from './share.js';
import { showToast } from '../../ui/toast.js';
import { bindItemHover } from '../../ui/itemUi.js';

// "More" menu in the toolbar: import/export and the rarely used reset/clear actions.
function bindMoreMenu() {
  const btn = document.getElementById('bpMoreBtn');
  const menu = document.getElementById('bpMoreMenu');
  const setOpen = open => {
    menu.hidden = !open;
    btn.setAttribute('aria-expanded', String(open));
    if (open) menu.querySelector('button:not([hidden])')?.focus({ preventScroll: true });
  };
  const ACTIONS = { import: openImport, export: exportData, copy: copyToClipboard, reset: resetToTemplate, clear: clearAllRows };

  btn.addEventListener('click', () => setOpen(menu.hidden));
  menu.addEventListener('click', e => {
    const item = e.target.closest('[data-act]');
    if (!item) return;
    setOpen(false);
    ACTIONS[item.dataset.act]?.();
  });
  const onDocDown = e => { if (!menu.hidden && !e.target.closest('#bpMore')) setOpen(false); };
  const onKey = e => { if (!menu.hidden && e.key === 'Escape') { setOpen(false); btn.focus(); } };
  document.addEventListener('pointerdown', onDocDown);
  document.addEventListener('keydown', onKey);
  return () => {
    document.removeEventListener('pointerdown', onDocDown);
    document.removeEventListener('keydown', onKey);
  };
}

export async function initBuilder(ctx) {
  const app = document.getElementById('app');
  app.innerHTML = builderHTML();

  await Promise.all([buildClassSelect(), loadItems()]);
  load();
  if (!state.rows.length) {
    DEFAULT_ROWS.forEach(n => state.rows.push({ id: state.uid++, name: n }));
    save();
  }

  const query = ctx?.query || {};
  if (query.b) {
    // Share link: the whole build is in the URL. Replacing saved work needs confirmation.
    const shared = await decodeShareCode(query.b);
    if (!shared) showToast(t('builder.badLink'));
    else if (!hasLocalData(shared.class) || confirm(t('builder.replaceConfirm', { cls: getClassName(shared.class) }))) {
      importExportBuildData(shared);
      state.selectedCreator = null;
      save();
    }
  } else if (query.class) {
    // Deep link: auto-select class/creator from query params
    const classChanged = query.class !== state.selectedClass;
    const switching = query.creator && (classChanged || query.creator !== state.selectedCreator);
    state.selectedClass = query.class;
    if (switching && hasLocalData(query.class)) {
      // A link to a different community build (e.g. from a hero page): replace the saved planner only if confirmed.
      if (confirm(t('builder.replaceConfirm', { cls: getClassName(query.class) }))) await chooseBuild(query.class, query.creator);
      else if (classChanged) state.selectedCreator = null;
    } else {
      if (query.creator) state.selectedCreator = query.creator;
      if (!hasLocalData(state.selectedClass)) await loadBuildFile(state.selectedClass, state.selectedCreator);
    }
  } else if (state.selectedClass && !hasLocalData(state.selectedClass)) {
    await loadBuildFile(state.selectedClass, state.selectedCreator);
  }

  await syncClassUI();
  render();
  updateBuildHash();

  initTooltip();
  bindSlotMenuGlobals();
  const unbindGrid = bindGridEvents(document.getElementById('bpGrid'));

  const unbindMore = bindMoreMenu();
  const unbindSkills = bindItemHover(document.getElementById('bpHero'));
  document.getElementById('bpShareBtn').addEventListener('click', copyShareLink);

  // Expose handlers for inline onclick attributes in HTML
  Object.assign(window, { toggleClassDropdown, toggleBuildBrowser, addRow, closeImport, doImport });

  return function cleanup() {
    unbindMore();
    unbindSkills();
    unbindGrid();
    closeSlotMenu();
    closePicker();
    hideItemTooltip();
  };
}
