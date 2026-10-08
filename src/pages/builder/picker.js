import { state } from '../../state.js';
import { showToast } from '../../ui/toast.js';
import { t } from '../../i18n.js';
import { iconSrc } from '../../data/items.js';
import { openItemPicker, closePicker as closeItemPicker, EQUIP_TABS, ALL_TAB } from '../../ui/itemPicker.js';
import { setSlotItem, getSlotArr } from './slots.js';

// Builder columns ↔ item type groups.
const COL_TO_GROUP = { weapon: 'weapon', helm: 'headwear', body: 'armor', wings: 'wings', accessory: 'accessory' };

export async function openPicker(rowId, col, idx) {
  if (!state.selectedClass) { showToast(t('builder.selectFirst')); return; }
  state.pickerTargetRow = rowId;
  state.pickerTargetCol = col;
  state.pickerTargetIdx = idx;
  await openItemPicker({
    title: t('col.' + col),
    titleIcon: col,
    pill: idx === 1 ? { text: t('builder.alt'), cls: 'mode-alt' } : { text: t('builder.primary'), cls: 'mode-primary' },
    tabs: [...EQUIP_TABS, ALL_TAB],
    tab: COL_TO_GROUP[col] || 'all',
    current: () => new Set(getSlotArr(state.pickerTargetRow, state.pickerTargetCol).filter(Boolean).map(i => i.name)),
    currentLabel: t('picker.equipped'),
    onPick: item => {
      setSlotItem(state.pickerTargetRow, state.pickerTargetCol, state.pickerTargetIdx, { type: 'library', name: item.name, src: iconSrc(item.name) });
    },
    onClose: () => {
      state.pickerTargetRow = null;
      state.pickerTargetCol = null;
      state.pickerTargetIdx = 0;
    },
  });
}

export function closePicker() {
  closeItemPicker();
}
