import { state } from '../../state.js';
import { DEFAULT_ROWS } from '../../constants.js';
import { hasLocalData, loadBuildFile } from '../../data/builds.js';
import { save, load } from '../../data/storage.js';
import { loadItems } from '../../data/items.js';
import { initTooltip, hideItemTooltip } from '../../ui/tooltip.js';
import { buildClassSelect, syncClassUI, toggleClassDropdown, toggleBuildBrowser, resetToTemplate, clearAllRows, updateBuildHash } from './classPicker.js';
import { render, bindGridEvents } from './render.js';
import { addRow } from './rows.js';
import { filterPicker, closePicker, closePickerOnBg } from './picker.js';
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
    state.selectedClass = query.class;
    if (query.creator) state.selectedCreator = query.creator;
    if (!hasLocalData(state.selectedClass)) await loadBuildFile(state.selectedClass, state.selectedCreator);
  } else if (state.selectedClass && !hasLocalData(state.selectedClass)) {
    await loadBuildFile(state.selectedClass, state.selectedCreator);
  }

  await syncClassUI();
  render();
  updateBuildHash();

  initTooltip();
  bindSlotMenuGlobals();
  const unbindGrid = bindGridEvents(document.getElementById('bpGrid'));

  const onKey = e => {
    if (e.key === 'Escape' && document.getElementById('pickerOverlay').classList.contains('show')) closePicker();
  };
  document.addEventListener('keydown', onKey);

  // Expose handlers for inline onclick attributes in HTML
  Object.assign(window, {
    toggleClassDropdown, toggleBuildBrowser, resetToTemplate, clearAllRows, addRow,
    filterPicker, closePicker, closePickerOnBg,
    openImport, closeImport, doImport, exportData, copyToClipboard,
  });

  return function cleanup() {
    unbindGrid();
    document.removeEventListener('keydown', onKey);
    closeSlotMenu();
    closePicker();
    hideItemTooltip();
  };
}
