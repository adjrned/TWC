import { state } from '../../state.js';
import { DEFAULT_ROWS } from '../../constants.js';
import { hasLocalData, loadBuildFile } from '../../data/builds.js';
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
import { openImport, closeImport, doImport, exportData, copyToClipboard } from './exportImport.js';
import { builderHTML } from './template.js';

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
  if (query.class) {
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

  // Expose handlers for inline onclick attributes in HTML
  Object.assign(window, {
    toggleClassDropdown, toggleBuildBrowser, resetToTemplate, clearAllRows, addRow,
    openImport, closeImport, doImport, exportData, copyToClipboard,
  });

  return function cleanup() {
    unbindGrid();
    closeSlotMenu();
    closePicker();
    hideItemTooltip();
  };
}
