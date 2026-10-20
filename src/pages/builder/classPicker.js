import { state } from '../../state.js';
import { ROSTER, classIconPath } from '../../constants.js';
import { fetchBuildCountsForAllClasses, fetchCreatorsForClass, hasLocalData, loadBuildFile } from '../../data/builds.js';
import { save } from '../../data/storage.js';
import { showToast } from '../../ui/toast.js';
import { render } from './render.js';
import { withUndo } from './rows.js';
import { openBuildBrowser, closeBuildBrowser, isBuildBrowserOpen, fmtBuildDate, fetchBuild } from './buildBrowser.js';
import { t, getClassName } from '../../i18n.js';
import { loadSkills, hotkeyPath } from '../../data/skills.js';
import { iconSrc } from '../../data/items.js';
import { esc } from '../../ui/escape.js';

export function updateBuildHash() {
  const params = new URLSearchParams();
  if (state.selectedClass) params.set('class', state.selectedClass);
  if (state.selectedCreator) params.set('creator', state.selectedCreator);
  const qs = params.toString();
  const newHash = qs ? `#/?${qs}` : '#/';
  if (location.hash !== newHash) history.replaceState(null, '', newHash);
}

let docClickBound = false;

export async function buildClassSelect() {
  const dropdown = document.getElementById('classPickerDropdown');
  dropdown.innerHTML = `
    <div class="custom-select-search"><input type="text" id="classPickerSearch" autocomplete="off" spellcheck="false"></div>
    <div class="custom-select-list" id="classPickerList"></div>
    <div class="custom-select-empty" id="classPickerEmpty" hidden></div>`;
  const search = document.getElementById('classPickerSearch');
  const listEl = document.getElementById('classPickerList');
  search.placeholder = t('builder.searchClass');
  document.getElementById('classPickerEmpty').textContent = t('builder.noClassMatch');
  search.addEventListener('input', filterClassOptions);
  search.addEventListener('keydown', onSearchKey);
  const counts = await fetchBuildCountsForAllClasses();

  for (const [type, list] of Object.entries(ROSTER)) {
    const groupLabel = document.createElement('div');
    groupLabel.className = 'custom-select-group-label';
    groupLabel.dataset.stat = type;
    groupLabel.textContent = t('stat.' + type);
    listEl.appendChild(groupLabel);

    list.forEach(name => {
      const count = counts[name] || 0;
      const opt = document.createElement('div');
      opt.className = 'custom-select-option';
      opt.dataset.value = name;
      opt.dataset.search = `${name} ${getClassName(name)}`.toLowerCase();
      opt.innerHTML = `<img class="opt-icon" src="${classIconPath(name)}" alt="" loading="lazy" onerror="this.remove()"><span class="opt-name"></span>`;
      opt.querySelector('.opt-name').textContent = getClassName(name);
      if (count > 0) {
        const badge = document.createElement('span');
        badge.className = 'opt-count';
        badge.textContent = t(count > 1 ? 'builder.nBuilds' : 'builder.oneBuild', { n: count });
        opt.appendChild(badge);
      }
      opt.addEventListener('click', () => selectClass(name));
      opt.addEventListener('mousemove', () => setActiveOption(opt));
      listEl.appendChild(opt);
    });
  }

  // The builder page is re-created on each visit; bind the outside-click closer once.
  if (!docClickBound) {
    docClickBound = true;
    document.addEventListener('click', e => {
      if (!e.target.closest('#classPickerWrap')) closeClassDropdown();
    });
  }
}

function visibleOptions() {
  return [...document.querySelectorAll('#classPickerList .custom-select-option:not([hidden])')];
}

function setActiveOption(opt) {
  document.querySelectorAll('#classPickerList .custom-select-option.active').forEach(el => el.classList.remove('active'));
  if (opt) {
    opt.classList.add('active');
    opt.scrollIntoView({ block: 'nearest' });
  }
}

function filterClassOptions() {
  const q = document.getElementById('classPickerSearch').value.trim().toLowerCase();
  let label = null, labelHasMatch = false, any = false;
  const finishGroup = () => { if (label) label.hidden = !labelHasMatch; };
  for (const el of document.getElementById('classPickerList').children) {
    if (el.classList.contains('custom-select-group-label')) {
      finishGroup();
      label = el; labelHasMatch = false;
    } else {
      const match = !q || el.dataset.search.includes(q);
      el.hidden = !match;
      if (match) { labelHasMatch = true; any = true; }
    }
  }
  finishGroup();
  document.getElementById('classPickerEmpty').hidden = any;
  setActiveOption(q ? visibleOptions()[0] : null);
}

function onSearchKey(e) {
  const opts = visibleOptions();
  const idx = opts.findIndex(el => el.classList.contains('active'));
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault();
    if (!opts.length) return;
    const next = e.key === 'ArrowDown' ? (idx + 1) % opts.length : (idx <= 0 ? opts.length - 1 : idx - 1);
    setActiveOption(opts[next]);
  } else if (e.key === 'Enter') {
    e.preventDefault();
    const pick = opts[idx] || opts[0];
    if (pick) selectClass(pick.dataset.value);
  } else if (e.key === 'Escape') {
    closeClassDropdown();
  }
}

export function toggleClassDropdown() {
  const wrap = document.getElementById('classPickerWrap');
  if (!wrap.classList.toggle('open')) return;
  const search = document.getElementById('classPickerSearch');
  search.value = '';
  filterClassOptions();
  document.querySelector('#classPickerList .custom-select-option.selected')?.scrollIntoView({ block: 'nearest' });
  search.focus();
}

export function closeClassDropdown() {
  document.getElementById('classPickerWrap')?.classList.remove('open');
}

export async function selectClass(name) {
  closeClassDropdown();
  state.selectedClass = name;
  state.selectedCreator = null;
  state.creatorName = '';
  state.publishedAt = '';
  save();
  await syncClassUI();
  render();
  updateBuildHash();
  // No saved work for this class yet → show its community builds to start from.
  if (!hasLocalData(name)) await showBuildBrowser();
}

export async function showBuildBrowser() {
  await openBuildBrowser(async () => {
    await syncClassUI();
    render();
    updateBuildHash();
  });
}

export async function toggleBuildBrowser() {
  if (isBuildBrowserOpen()) closeBuildBrowser();
  else await showBuildBrowser();
}

export async function resetToTemplate() {
  if (!state.selectedClass) return;
  const label = state.selectedCreator ? `${state.selectedClass} (${state.selectedCreator})` : state.selectedClass;
  if (!confirm(t('builder.resetConfirm', { label }))) return;
  if (state.builds[state.selectedClass]) delete state.builds[state.selectedClass];
  save();
  const loaded = await loadBuildFile(state.selectedClass, state.selectedCreator);
  if (!loaded) showToast(t('builder.noTemplate'));
  await syncClassUI(); render();
}

export function clearAllRows() {
  if (!state.selectedClass) return;
  withUndo(t('builder.cleared'), () => {
    for (const rowId of Object.keys(state.builds[state.selectedClass] || {})) state.builds[state.selectedClass][rowId] = {};
  });
}

// Hero roster (name, main stat, tags) for the banner, fetched once.
let heroesPromise = null;
function loadHeroes() {
  if (!heroesPromise) heroesPromise = fetch('data/heroes.json').then(r => (r.ok ? r.json() : [])).catch(() => []);
  return heroesPromise;
}

export async function syncClassUI() {
  const cls = state.selectedClass;
  const label = document.getElementById('classPickerLabel');
  const icon = document.getElementById('classPickerIcon');
  const buildBtn = document.getElementById('buildBrowserBtn');

  document.querySelectorAll('#classPickerDropdown .custom-select-option').forEach(el =>
    el.classList.toggle('selected', el.dataset.value === cls));
  document.getElementById('resetTemplateBtn').hidden = !(cls && state.selectedCreator);
  document.getElementById('clearAllBtn').hidden = !cls;
  document.getElementById('bpHero').hidden = !cls;
  document.getElementById('bpShareBtn').hidden = !cls;

  if (!cls) {
    label.textContent = t('builder.selectClass');
    label.classList.add('placeholder');
    icon.hidden = true;
    buildBtn.hidden = true;
    closeBuildBrowser();
    return;
  }

  label.textContent = getClassName(cls);
  label.classList.remove('placeholder');
  icon.onerror = () => { icon.hidden = true; };
  icon.src = classIconPath(cls);
  icon.hidden = false;

  const [creators, heroes, skills] = await Promise.all([fetchCreatorsForClass(cls), loadHeroes(), loadSkills()]);
  creators.forEach(c => fetchBuild(cls, c)); // warm the cache so the build browser opens with previews
  buildBtn.hidden = false;
  document.getElementById('buildBrowserValue').textContent =
    state.selectedCreator || (hasLocalData(cls) ? t('builder.custom') : t('builder.chooseBuild'));
  buildBtn.title = t(creators.length === 1 ? 'builder.oneBuild' : 'builder.nBuilds', { n: creators.length });
  syncHeroBanner(cls, (Array.isArray(heroes) ? heroes : Object.values(heroes)).find(h => h.heroClass === cls),
    skills.filter(sk => sk.heroClass === cls).sort((a, b) => (a.order ?? 99) - (b.order ?? 99)));
}

// Banner above the grid: who the hero is, and whose build this is.
function syncHeroBanner(cls, hero, skills = []) {
  const heroHref = hero ? '#/heroes/' + encodeURIComponent(hero.id) : '#/heroes';
  const img = document.getElementById('bpHeroImg');
  img.onerror = () => { img.hidden = true; };
  img.hidden = false;
  img.src = classIconPath(cls);
  document.getElementById('bpHeroPortrait').href = heroHref;
  document.getElementById('bpHero').style.setProperty('--hero', hero ? '#' + hero.color : '');

  // Character name (links to the hero page) · main stat · range · difficulty, then tags and overview.
  const diff = hero?.difficulty
    ? `<span class="hd-diff" title="${esc(t('heroes.difficulty'))} ${hero.difficulty}/3">${esc(t('heroes.difficulty'))} ${[1, 2, 3].map(n => `<i class="${n <= hero.difficulty ? 'on' : ''}"></i>`).join('')}</span>`
    : '';
  const facts = hero ? [
    `<a class="bp-hero-name" href="${heroHref}">${esc(hero.name)}</a>`,
    hero.mainstat ? esc(t('stat.' + hero.mainstat)) : '',
    hero.range ? esc(t(hero.range === 'Ranged' ? 'heroes.ranged' : 'heroes.melee')) : '',
    diff,
  ].filter(Boolean) : [esc(getClassName(cls))];
  document.getElementById('bpHeroSub').innerHTML = facts.join('<span class="bp-sep">·</span>')
    + (hero?.tags?.length ? `<span class="bp-hero-tags">${hero.tags.map(tag => `<span class="hd-tag">${esc(tag)}</span>`).join('')}</span>` : '');
  document.getElementById('bpHeroOverview').textContent = hero?.overview || '';

  // Skill icons: hover shows the skill tooltip (desktop); tapping opens the hero page.
  document.getElementById('bpHeroSkills').innerHTML = skills.map(sk => {
    const keys = hotkeyPath(sk.hotkey).map(k => (k === 'Passive' ? t('builder.passiveKey') : k)).join('→');
    return `<a class="bp-skill" href="${heroHref}" data-skill="${esc(cls + '|' + sk.name)}" data-color="${esc(hero?.color || '')}" aria-label="${esc(sk.name)}">
      <span class="bp-skill-icon"><img src="${esc(iconSrc(sk.icon || sk.name))}" alt="" loading="lazy" onerror="this.remove()"></span>
      <span class="bp-skill-key">${esc(keys)}</span>
    </a>`;
  }).join('');

  // Community builds show their publish date beside the Build picker.
  const author = state.creatorName || state.selectedCreator;
  const date = author ? fmtBuildDate(state.publishedAt) : '';
  const dateEl = document.getElementById('bpBuildDate');
  dateEl.textContent = date ? t('builder.updated', { date }) : '';
  dateEl.title = author ? t('builder.by', { name: author }) : '';
}
