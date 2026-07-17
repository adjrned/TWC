import { state } from '../../state.js';
import { DEFAULT_ROWS } from '../../constants.js';
import { loadIconLibrary } from '../../data/icons.js';
import { hasLocalData, loadBuildFile } from '../../data/builds.js';
import { save, load } from '../../data/storage.js';
import { initTooltip } from '../../ui/tooltip.js';
import { buildClassSelect, syncClassUI, toggleClassDropdown, toggleCreatorDropdown, onCreatorChange, resetToTemplate, clearAllRows } from './classPicker.js';
import { render } from './render.js';
import { addRow } from './rows.js';
import { openPicker, filterPicker, closePicker, closePickerOnBg } from './picker.js';
import { closeAllPopovers, closeCtx, ctxOpenPicker, ctxClear, ctxClearAlt, ctxDelete } from './contextMenu.js';
import { openImport, closeImport, doImport, exportData, copyToClipboard } from './exportImport.js';
import { builderHTML } from './template.js';

let docClickHandler = null;
let docKeyHandler = null;

export async function initBuilder(ctx) {
  const app = document.getElementById('app');
  app.innerHTML = builderHTML();

  await buildClassSelect();
  await loadIconLibrary();
  load();
  if (!state.rows.length) {
    DEFAULT_ROWS.forEach(n => state.rows.push({ id: state.uid++, name: n }));
    save();
  }

  // Deep link: auto-select class/creator from query params
  const query = ctx?.query || {};
  if (query.class) {
    state.selectedClass = query.class;
    if (query.creator) state.selectedCreator = query.creator;
    if (!hasLocalData(state.selectedClass)) {
      await loadBuildFile(state.selectedClass, state.selectedCreator);
    }
  } else if (state.selectedClass && !hasLocalData(state.selectedClass)) {
    await loadBuildFile(state.selectedClass, state.selectedCreator);
  }

  await syncClassUI();
  render();

  initTooltip();

  docClickHandler = e => {
    if (state.activePopoverDrop && !e.target.closest('.slot-drop')) closeAllPopovers();
    if (!e.target.closest('#ctxMenu')) closeCtx();
  };
  docKeyHandler = e => {
    if (e.key === 'Escape') { closeAllPopovers(); closeCtx(); }
  };
  document.addEventListener('click', docClickHandler);
  document.addEventListener('keydown', docKeyHandler);

  // Expose handlers for inline onclick attributes in HTML
  window.toggleClassDropdown = toggleClassDropdown;
  window.toggleCreatorDropdown = toggleCreatorDropdown;
  window.onCreatorChange = onCreatorChange;
  window.resetToTemplate = resetToTemplate;
  window.clearAllRows = clearAllRows;
  window.addRow = addRow;
  window.openPicker = openPicker;
  window.filterPicker = filterPicker;
  window.closePicker = closePicker;
  window.closePickerOnBg = closePickerOnBg;
  window.ctxOpenPicker = ctxOpenPicker;
  window.ctxClear = ctxClear;
  window.ctxClearAlt = ctxClearAlt;
  window.ctxDelete = ctxDelete;
  window.openImport = openImport;
  window.closeImport = closeImport;
  window.doImport = doImport;
  window.exportData = exportData;
  window.copyToClipboard = copyToClipboard;

  return function cleanup() {
    if (docClickHandler) document.removeEventListener('click', docClickHandler);
    if (docKeyHandler) document.removeEventListener('keydown', docKeyHandler);
    docClickHandler = null;
    docKeyHandler = null;
  };
}
