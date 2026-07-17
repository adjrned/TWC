import { state } from '../../state.js';
import { ROSTER, classIconPath } from '../../constants.js';
import { fetchBuildCountsForAllClasses, fetchCreatorsForClass, hasLocalData, loadBuildFile } from '../../data/builds.js';
import { save } from '../../data/storage.js';
import { showToast } from '../../ui/toast.js';
import { render } from './render.js';
import { t, getClassName } from '../../i18n.js';

export async function buildClassSelect() {
  const dropdown = document.getElementById('classPickerDropdown');
  const hiddenSel = document.getElementById('classSelect');
  dropdown.innerHTML = '';
  hiddenSel.innerHTML = '<option value=""></option>';

  const counts = await fetchBuildCountsForAllClasses();

  for (const [type, list] of Object.entries(ROSTER)) {
    const groupLabel = document.createElement('div');
    groupLabel.className = 'custom-select-group-label';
    groupLabel.dataset.stat = type;
    groupLabel.textContent = t('stat.' + type);
    dropdown.appendChild(groupLabel);

    list.forEach(name => {
      const count = counts[name] || 0;
      const opt = document.createElement('div');
      opt.className = 'custom-select-option';
      opt.dataset.value = name;
      const nameSpan = document.createElement('span');
      nameSpan.className = 'opt-name';
      nameSpan.textContent = getClassName(name);
      opt.appendChild(nameSpan);
      if (count > 0) {
        const badge = document.createElement('span');
        badge.className = 'opt-count';
        badge.textContent = `${count} build${count > 1 ? 's' : ''}`;
        opt.appendChild(badge);
      }
      opt.addEventListener('click', () => selectClass(name));
      dropdown.appendChild(opt);

      const hiddenOpt = document.createElement('option');
      hiddenOpt.value = name;
      hiddenOpt.textContent = name;
      hiddenSel.appendChild(hiddenOpt);
    });
  }

  document.addEventListener('click', e => {
    if (!e.target.closest('#classPickerWrap')) closeClassDropdown();
    if (!e.target.closest('#creatorPickerWrap')) closeCreatorDropdown();
  });
}

export function toggleClassDropdown() {
  document.getElementById('classPickerWrap').classList.toggle('open');
  document.getElementById('creatorPickerWrap').classList.remove('open');
}

export function closeClassDropdown() {
  document.getElementById('classPickerWrap').classList.remove('open');
}

export function toggleCreatorDropdown() {
  document.getElementById('creatorPickerWrap').classList.toggle('open');
  document.getElementById('classPickerWrap').classList.remove('open');
}

export function closeCreatorDropdown() {
  document.getElementById('creatorPickerWrap').classList.remove('open');
}

export async function selectClass(name) {
  closeClassDropdown();
  const label = document.getElementById('classPickerLabel');
  label.textContent = getClassName(name);
  label.classList.remove('placeholder');
  document.querySelectorAll('.custom-select-option').forEach(el => {
    el.classList.toggle('selected', el.dataset.value === name);
  });
  document.getElementById('classSelect').value = name;
  state.selectedClass = name;
  state.selectedCreator = null;
  state.creatorName = '';
  if (!hasLocalData(state.selectedClass)) await loadBuildFile(state.selectedClass, null);
  save(); await syncClassUI(); render();
}

export async function onCreatorChange() {
  const val = document.getElementById('creatorSelect').value;
  state.selectedCreator = val || null;
  if (state.selectedClass && state.builds[state.selectedClass]) delete state.builds[state.selectedClass];
  save();
  await loadBuildFile(state.selectedClass, state.selectedCreator);
  save(); syncClassUI(); render();
}

async function selectCreator(name) {
  closeCreatorDropdown();
  const label = document.getElementById('creatorPickerLabel');
  label.textContent = name || '— Choose build —';
  label.classList.toggle('placeholder', !name);
  document.querySelectorAll('#creatorPickerDropdown .custom-select-option').forEach(el => {
    el.classList.toggle('selected', el.dataset.value === name);
  });
  document.getElementById('creatorSelect').value = name || '';
  state.selectedCreator = name || null;
  if (state.selectedClass && state.builds[state.selectedClass]) delete state.builds[state.selectedClass];
  save();
  await loadBuildFile(state.selectedClass, state.selectedCreator);
  save(); syncClassUI(); render();
}

export async function resetToTemplate() {
  if (!state.selectedClass) return;
  const label = state.selectedCreator ? `${state.selectedClass} (${state.selectedCreator})` : state.selectedClass;
  if (!confirm(`Reset to the published template for ${label}? Your local edits will be lost.`)) return;
  if (state.builds[state.selectedClass]) delete state.builds[state.selectedClass];
  save();
  const loaded = await loadBuildFile(state.selectedClass, state.selectedCreator);
  if (!loaded) showToast('No published template found for this class.');
  syncClassUI(); render();
}

export function clearAllRows() {
  if (!state.selectedClass) return;
  if (!confirm('Clear all items from every row? This cannot be undone.')) return;
  if (state.builds[state.selectedClass]) {
    for (const rowId of Object.keys(state.builds[state.selectedClass])) {
      state.builds[state.selectedClass][rowId] = {};
    }
  }
  save(); render(); showToast('All rows cleared.');
}

export async function syncClassUI() {
  document.getElementById('classSelect').value = state.selectedClass || '';
  const colName = document.getElementById('heroColName');
  const colSubtitle = document.getElementById('heroColSubtitle');
  const iconWrap = document.getElementById('heroColIconWrap');
  const imgEl = document.getElementById('heroColIconImg');
  const ph = document.getElementById('heroColIconPlaceholder');
  const resetBtn = document.getElementById('resetTemplateBtn');
  const clearBtn = document.getElementById('clearAllBtn');
  const creatorWrap = document.getElementById('creatorPickerWrap');
  const creatorSel = document.getElementById('creatorSelect');

  if (state.selectedClass) {
    const label = document.getElementById('classPickerLabel');
    label.textContent = getClassName(state.selectedClass);
    label.classList.remove('placeholder');
    document.querySelectorAll('.custom-select-option').forEach(el =>
      el.classList.toggle('selected', el.dataset.value === state.selectedClass)
    );
    const creators = await fetchCreatorsForClass(state.selectedClass);
    if (creators.length > 0) {
      creatorSel.innerHTML = '';
      const defaultOpt = document.createElement('option');
      defaultOpt.value = '';
      defaultOpt.textContent = '— Choose build —';
      creatorSel.appendChild(defaultOpt);
      creators.forEach(c => {
        const opt = document.createElement('option');
        opt.value = c;
        opt.textContent = c;
        creatorSel.appendChild(opt);
      });
      creatorSel.value = state.selectedCreator || '';

      const creatorDropdown = document.getElementById('creatorPickerDropdown');
      creatorDropdown.innerHTML = '';
      creators.forEach(c => {
        const opt = document.createElement('div');
        opt.className = 'custom-select-option';
        opt.dataset.value = c;
        if (c === state.selectedCreator) opt.classList.add('selected');
        const nameSpan = document.createElement('span');
        nameSpan.className = 'opt-name';
        nameSpan.textContent = c;
        opt.appendChild(nameSpan);
        opt.addEventListener('click', () => selectCreator(c));
        creatorDropdown.appendChild(opt);
      });

      const creatorLabel = document.getElementById('creatorPickerLabel');
      creatorLabel.textContent = state.selectedCreator || t('builder.chooseBuild');
      creatorLabel.classList.toggle('placeholder', !state.selectedCreator);

      creatorWrap.style.display = '';
    } else {
      creatorWrap.style.display = 'none';
    }

    colName.textContent = getClassName(state.selectedClass);
    colSubtitle.textContent = state.creatorName ? `by ${state.creatorName}` : '';
    colName.classList.add('active');
    iconWrap.classList.add('visible');
    const p = classIconPath(state.selectedClass);
    imgEl.style.display = 'none';
    ph.style.display = '';
    const testImg = new Image();
    testImg.onload = () => { imgEl.src = p; imgEl.style.display = 'block'; ph.style.display = 'none'; };
    testImg.onerror = () => { imgEl.style.display = 'none'; ph.style.display = ''; };
    testImg.src = p;
    resetBtn.style.display = '';
    clearBtn.style.display = '';
  } else {
    const label = document.getElementById('classPickerLabel');
    label.textContent = t('builder.selectClass');
    label.classList.add('placeholder');
    document.querySelectorAll('.custom-select-option').forEach(el => el.classList.remove('selected'));
    creatorWrap.style.display = 'none';
    colName.textContent = 'Heroes';
    colSubtitle.textContent = '';
    colName.classList.remove('active');
    iconWrap.classList.remove('visible');
    resetBtn.style.display = 'none';
    clearBtn.style.display = 'none';
  }
}
