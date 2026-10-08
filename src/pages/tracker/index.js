import { esc } from '../../ui/escape.js';
import {
  loadItems, getItem, iconSrc, rankInfo, tierIndex, dropRateFor, formatDropRate, localizedItemName,
} from '../../data/items.js';
import { translateItemName } from '../../data/translate.js';
import { t, tf, getLocale, getClassName } from '../../i18n.js';
import { showToast } from '../../ui/toast.js';
import { iconHtml, bindItemHover } from '../../ui/itemUi.js';
import { hideItemTooltip } from '../../ui/tooltip.js';
import { openItemPicker, closePicker, EQUIP_TABS, MATERIAL_TAB, ALL_TAB } from '../../ui/itemPicker.js';
import { parseSaveFile } from './parser.js';
import {
  saveProfiles, loadProfileState, saveProfileState,
  deleteProfileState, migrateToProfiles, addCodeToProfileState,
} from './storage.js';
import { buildItemMap, buildOwnedMap, buildRecipeTree, buildComprehensiveData, flattenToLeaves, isExcluded } from './tree.js';
import { supportsFileHandles, pickFile, storeFileHandle, getFileHandle, removeFileHandle, readFileFromHandle } from './filehandle.js';

let itemData = null;
let bossData = null;
let heroData = null;
let heroIconMap = null;
let itemMap = null;
let profilesData = null;
let trackerState = null;
let currentView = 'split';
let fileStatusMessage = '';
let fileStatusTimer = null;

const EMPTY_STATE = () => ({ version: 1, trackedItems: [], lastSave: null, loadCodeHistory: [] });
const SECTION_ORDER = ['Hero Inventory', 'Bag', 'Storage'];

// Small inline icons (same stroke style as the nav)
const SVG = {
  upload: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 15V4M7 9l5-5 5 5"/><path d="M4 15v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4"/></svg>',
  link: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66l-1 1"/><path d="M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1-1"/></svg>',
  search: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/></svg>',
  check: '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12l5 5 9-10"/></svg>',
};

function activeProfileId() {
  return profilesData?.activeProfileId || null;
}

function activeProfile() {
  if (!profilesData) return null;
  return profilesData.profiles.find(p => p.id === profilesData.activeProfileId) || null;
}

async function loadItemData() {
  if (itemData) return;
  itemData = await loadItems();
  itemMap = buildItemMap(itemData);
}

async function loadBossData() {
  if (bossData) return;
  try {
    const r = await fetch('data/bosses.json');
    if (r.ok) bossData = await r.json();
  } catch (e) {}
  if (!bossData) bossData = [];
}

function classNameKeys(name) {
  const base = name.toLowerCase().replace(/[^a-z]/g, '');
  const words = name.toLowerCase().match(/[a-z]+/g) || [];
  return [base, [...words].sort().join('')];
}

async function loadHeroData() {
  if (heroData) return;
  try {
    const r = await fetch('data/heroes.json');
    if (r.ok) heroData = await r.json();
  } catch (e) {}
  if (!heroData) heroData = [];
  heroIconMap = new Map();
  for (const h of heroData) {
    if (h.heroClass && h.icon) {
      heroIconMap.set(h.heroClass, h.icon);
      for (const key of classNameKeys(h.heroClass)) heroIconMap.set(key, h.icon);
    }
  }
}

function getHeroIcon(heroClass) {
  if (!heroClass) return '';
  if (heroIconMap?.has(heroClass)) return iconSrc(heroIconMap.get(heroClass));
  for (const key of classNameKeys(heroClass)) {
    if (heroIconMap?.has(key)) return iconSrc(heroIconMap.get(key));
  }
  return iconSrc(heroClass.replace(/[^a-zA-Z]/g, '') + 'Icon');
}

function bossIconSrc(name) {
  return iconSrc(name + ' Icon');
}

function itemLink(name, extra = '') {
  return `<a href="#/items/${encodeURIComponent(name)}" class="trk-name ${rankInfo(getItem(name)).css}" data-name="${esc(name)}"${extra}>${esc(localizedNameOf(name))}</a>`;
}

function localizedNameOf(name) {
  const it = getItem(name);
  return it ? localizedItemName(it) : name;
}

function setFileStatus(msg) {
  fileStatusMessage = msg;
  const el = document.getElementById('fileStatusMsg');
  if (el) {
    el.textContent = msg;
    el.hidden = !msg;
  }
  clearTimeout(fileStatusTimer);
  if (msg) {
    fileStatusTimer = setTimeout(() => {
      fileStatusMessage = '';
      const el2 = document.getElementById('fileStatusMsg');
      if (el2) el2.hidden = true;
    }, 5000);
  }
}

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch (e) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.cssText = 'position:fixed;opacity:0;pointer-events:none';
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand('copy');
    ta.remove();
    return ok;
  }
}

// ── Profiles ──────────────────────────────────────────────────
function renderProfileBar() {
  if (!profilesData) return '';
  const active = activeProfileId();
  const tabs = profilesData.profiles.map(p => {
    const icon = getHeroIcon(p.heroClass);
    return `<button type="button" class="trk-profile" data-act="switch-profile" data-id="${esc(p.id)}" aria-pressed="${p.id === active}" title="${esc(p.name)}">
      ${icon ? `<img src="${esc(icon)}" alt="" onerror="this.remove()">` : ''}<span>${esc(p.name)}</span>
    </button>`;
  }).join('');
  return `
    <div class="trk-profilebar">
      <div class="trk-profiles">
        ${tabs}
        <button type="button" class="trk-profile trk-profile-add" data-act="add-profile" title="${esc(t('trk.newProfileHint'))}">+ <span>${t('trk.newProfile')}</span></button>
      </div>
      ${active ? `<div class="trk-profile-actions">
        <button type="button" class="btn" data-act="rename-profile">${t('trk.rename')}</button>
        <button type="button" class="btn danger-btn" data-act="delete-profile">${t('trk.deleteProfile')}</button>
      </div>` : ''}
    </div>`;
}

// ── Save file / character ─────────────────────────────────────
function renderUploadZone(compact) {
  return `
    <div class="trk-upload ${compact ? 'compact' : ''}" id="uploadZone" role="button" tabindex="0">
      <span class="trk-upload-icon">${SVG.upload}</span>
      <span class="trk-upload-text">
        <b>${t(compact ? 'trk.updateTitle' : 'trk.uploadTitle')}</b>
        <span>${t(compact ? 'trk.updateHint' : 'trk.uploadHint')}</span>
      </span>
      <input type="file" id="fileInput" accept=".txt" hidden>
    </div>
    <div class="trk-status" id="fileStatusMsg" ${fileStatusMessage ? '' : 'hidden'}>${esc(fileStatusMessage)}</div>`;
}

function invIcon(name, qty, small = false) {
  return `<a href="#/items/${encodeURIComponent(name)}" class="trk-inv ${rankInfo(getItem(name)).css}" data-name="${esc(name)}" aria-label="${esc(name)}${qty > 1 ? ' ×' + qty : ''}">
    ${iconHtml(name, small ? 'trk-inv-icon sm' : 'trk-inv-icon')}
    ${qty > 1 ? `<span class="trk-qty">${qty}</span>` : ''}
  </a>`;
}

function renderCharacter(save) {
  if (!save) return renderUploadZone(false);
  const profile = activeProfile();
  const linked = profile?.linkedFileName;
  const canLink = supportsFileHandles() && !linked;
  const sections = SECTION_ORDER.map(name => {
    const items = save.sections[name];
    if (!items?.length) return '';
    return `<div class="trk-invsec">
      <h3>${esc(tf('trk.sec.' + name, name))} <span>${items.length}</span></h3>
      <div class="trk-invgrid">${items.map(({ name: n, qty }) => invIcon(n, qty)).join('')}</div>
    </div>`;
  }).join('');

  return `
    <section class="trk-char">
      <header class="trk-char-head">
        <img src="${esc(getHeroIcon(save.class))}" alt="" class="trk-char-icon" onerror="this.remove()">
        <div class="trk-char-id">
          <h2>${esc(save.username)}</h2>
          <span>${esc(getClassName(save.class))} · ${t('items.lv')} ${esc(save.level)}${save.version ? ` · v${esc(save.version)}` : ''}</span>
        </div>
        <div class="trk-char-actions">
          ${linked ? `
            <span class="trk-linked" title="${esc(linked)}">${SVG.link}<span>${esc(linked)}</span></span>
            <button type="button" class="btn" data-act="refresh-file" title="${esc(t('trk.refreshHint'))}">${t('trk.refresh')}</button>
            <button type="button" class="btn" data-act="unlink-file" title="${esc(t('trk.unlinkHint'))}">${t('trk.unlink')}</button>
          ` : canLink ? `<button type="button" class="btn" data-act="link-file" title="${esc(t('trk.linkHint'))}">${SVG.link} ${t('trk.linkFile')}</button>` : ''}
          <button type="button" class="btn danger-btn" data-act="remove-save">${t('trk.removeSave')}</button>
        </div>
      </header>
      ${sections}
      ${renderUploadZone(true)}
    </section>`;
}

// ── Tracking ──────────────────────────────────────────────────
function renderTrackSearch() {
  return `
    <div class="trk-search">
      <label class="idb-search">
        ${SVG.search}
        <input type="search" id="trackerSearchInput" placeholder="${esc(t('trk.search'))}" autocomplete="off" spellcheck="false" aria-autocomplete="list" aria-controls="trackerSearchResults">
      </label>
      <div class="trk-results" id="trackerSearchResults" role="listbox" hidden></div>
      <button type="button" class="btn" data-act="browse-items">${t('trk.browse')}</button>
    </div>`;
}

function renderTrackedChips() {
  if (!trackerState.trackedItems.length) return `<p class="trk-empty-line">${t('trk.nothingTracked')}</p>`;
  return `<div class="trk-chips">${trackerState.trackedItems.map((name, idx) => `
    <span class="trk-chip ${rankInfo(getItem(name)).css}">
      ${iconHtml(name, 'idb-chip-icon')}
      ${itemLink(name)}
      <button type="button" class="trk-chip-x" data-act="untrack" data-idx="${idx}" aria-label="${esc(t('trk.stopTracking', { name }))}">×</button>
    </span>`).join('')}</div>`;
}

// ── Recipe trees ──────────────────────────────────────────────
function statusHtml(node) {
  if (node.status === 'have') return `<span class="trk-status-pill have">${SVG.check}${node.neededQty > 1 ? node.neededQty : ''}</span>`;
  return `<span class="trk-status-pill ${node.status}">${node.ownedQty}/${node.neededQty}</span>`;
}

function sourcesHtml(node) {
  if (node.drops.length) {
    return `<span class="trk-sources">${node.drops.map(({ boss, rate }) => `
      <span class="trk-src" title="${esc(boss)}${rate ? ' · ' + formatDropRate(rate) : ''}">
        <img src="${bossIconSrc(boss)}" alt="${esc(boss)}" onerror="this.remove()">${rate ? `<span>${formatDropRate(rate)}</span>` : ''}
      </span>`).join('')}</span>`;
  }
  if (!node.isLeaf) return `<span class="trk-craft">${t(node.status === 'have' ? 'trk.crafted' : 'trk.craft')}</span>`;
  return '';
}

function treeNodeHtml(node, depth) {
  const hasChildren = node.children.length > 0;
  const open = depth <= 1 && node.status !== 'have';
  const row = `
    <div class="trk-row ${node.status === 'have' ? 'is-have' : ''}">
      ${iconHtml(node.name, 'idb-chip-icon')}
      ${itemLink(node.name)}
      ${node.neededQty > 1 ? `<span class="trk-need">×${node.neededQty}</span>` : ''}
      <span class="trk-spacer"></span>
      ${sourcesHtml(node)}
      ${statusHtml(node)}
    </div>
    ${node.alternatives?.length ? `<div class="trk-alts"><span>${t('items.or')}</span>${node.alternatives.map(a => `${iconHtml(a, 'idb-chip-icon')}${itemLink(a)}`).join('')}</div>` : ''}`;
  if (!hasChildren) return `<li class="trk-leaf">${row}</li>`;
  return `<li><details ${open ? 'open' : ''}><summary>${row}</summary><ul>${node.children.map(c => treeNodeHtml(c, depth + 1)).join('')}</ul></details></li>`;
}

function renderTrees() {
  const ownedMap = buildOwnedMap(trackerState.lastSave?.inventory);
  return trackerState.trackedItems.map(name => {
    const tree = buildRecipeTree(name, 1, itemMap, ownedMap);
    const ri = rankInfo(getItem(name));
    // Base materials have no recipe: show the item itself so its count and sources are visible.
    const body = tree.children.length
      ? `<ul class="trk-tree">${tree.children.map(c => treeNodeHtml(c, 0)).join('')}</ul>`
      : `<ul class="trk-tree"><li class="trk-leaf"><div class="trk-row ${tree.status === 'have' ? 'is-have' : ''}">${iconHtml(name, 'idb-chip-icon')}${itemLink(name)}<span class="trk-spacer"></span>${sourcesHtml(tree)}${statusHtml(tree)}</div></li></ul>`;
    return `<section class="trk-card">
      <header class="trk-card-head ${ri.css}">
        ${iconHtml(name, 'idb-chip-icon lg')}
        ${itemLink(name)}
        ${tree.status === 'have' ? `<span class="trk-status-pill have">${SVG.check} ${t('trk.owned')}</span>` : ''}
      </header>
      ${body}
    </section>`;
  }).join('');
}

// ── Materials by monster ──────────────────────────────────────
function renderMaterials() {
  const ownedMap = buildOwnedMap(trackerState.lastSave?.inventory);

  // Totals across every tracked item (shared inventory consumed once).
  const totals = new Map();
  const sharedRemaining = new Map(ownedMap);
  for (const itemName of trackerState.trackedItems) {
    const leaves = flattenToLeaves(itemName, 1, itemMap, ownedMap, new Map(), new Set(), sharedRemaining);
    for (const [matName, needed] of leaves) {
      if (isExcluded(matName) || needed <= 0) continue;
      totals.set(matName, (totals.get(matName) || 0) + needed);
    }
  }
  if (!totals.size) return `<div class="trk-done">${t('trk.allAcquired')}</div>`;

  const totalsHtml = `<section class="trk-card">
    <header class="trk-card-head"><h3>${t('trk.stillNeeded')}</h3><span class="idb-count">${t('trk.nMaterials', { n: totals.size })}</span></header>
    <div class="trk-totals">${[...totals.entries()]
      .sort((a, b) => tierIndex(getItem(a[0])) - tierIndex(getItem(b[0])) || a[0].localeCompare(b[0]))
      .map(([n, q]) => `<span class="trk-total ${rankInfo(getItem(n)).css}">${iconHtml(n, 'idb-chip-icon')}${itemLink(n)}<span class="trk-need">×${q}</span></span>`).join('')}</div>
  </section>`;

  const groups = buildComprehensiveData(trackerState.trackedItems, itemMap, ownedMap, bossData);
  const groupsHtml = Object.entries(groups).map(([bossName, { boss, materials }]) => {
    const head = boss
      ? `<a href="#/bosses/${encodeURIComponent(boss.id)}" class="trk-boss"><img src="${bossIconSrc(bossName)}" alt="" onerror="this.remove()"><span>${esc(bossName)}</span></a>`
      : `<span class="trk-boss"><span>${bossName === 'Craftable' ? t('trk.otherSources') : esc(bossName)}</span></span>`;
    return `<div class="trk-mgroup">
      <div class="trk-mgroup-head">${head}<span class="idb-count">${materials.length}</span></div>
      ${materials.map(m => {
        const rate = dropRateFor(m.item, bossName);
        return `<div class="trk-mrow">
          ${iconHtml(m.name, 'idb-chip-icon')}
          ${itemLink(m.name)}
          <span class="trk-usedfor">${m.usedFor.map(n => `<a href="#/items/${encodeURIComponent(n)}" class="trk-usedfor-item ${rankInfo(getItem(n)).css}" data-name="${esc(n)}" aria-label="${esc(t('trk.usedFor', { name: localizedNameOf(n) }))}">${iconHtml(n, 'idb-chip-icon')}</a>`).join('')}</span>
          <span class="trk-need">×${m.needed}</span>
          <span class="trk-rate">${rate ? formatDropRate(rate) : ''}</span>
        </div>`;
      }).join('')}
    </div>`;
  }).join('');

  return totalsHtml + `<section class="trk-card trk-mgroups">${groupsHtml}</section>`;
}

function renderContent() {
  if (!trackerState.trackedItems.length) return '';
  return currentView === 'split' ? renderTrees() : renderMaterials();
}

function renderViewBar() {
  if (!trackerState.trackedItems.length) return '';
  return `
    <div class="trk-viewbar">
      <div class="idb-tabs">
        <button type="button" class="idb-tab" data-act="view" data-view="split" aria-pressed="${currentView === 'split'}">${t('trk.viewTrees')}</button>
        <button type="button" class="idb-tab" data-act="view" data-view="comprehensive" aria-pressed="${currentView === 'comprehensive'}">${t('trk.viewMaterials')}</button>
      </div>
      ${currentView === 'split' ? `<div class="trk-viewbar-actions">
        <button type="button" class="btn" data-act="expand-all">${t('trk.expandAll')}</button>
        <button type="button" class="btn" data-act="collapse-all">${t('trk.collapseAll')}</button>
      </div>` : ''}
    </div>`;
}

// ── Load code history ─────────────────────────────────────────
function renderHistory() {
  const history = trackerState.loadCodeHistory || [];
  if (!history.length) return '';
  return `
    <section class="trk-history">
      <h2 class="trk-h2">${t('trk.history')} <span class="idb-count">${history.length}</span></h2>
      ${history.map((entry, i) => {
        const all = SECTION_ORDER.flatMap(n => entry.sections?.[n] || []);
        return `<details class="trk-hist">
          <summary>
            <span class="trk-hist-who">${esc(entry.username)} <span>${esc(getClassName(entry.class))} · ${t('items.lv')} ${esc(entry.level)}</span></span>
            <span class="trk-hist-date">${new Date(entry.uploadedAt).toLocaleString()}</span>
          </summary>
          ${all.length ? `<div class="trk-invgrid sm">${all.map(({ name, qty }) => invIcon(name, qty, true)).join('')}</div>` : ''}
          <pre class="trk-codes">${entry.codes.map(c => esc(c)).join('\n')}</pre>
          <button type="button" class="btn" data-act="copy-codes" data-idx="${i}">${t('trk.copyCodes')}</button>
        </details>`;
      }).join('')}
    </section>`;
}

function renderPage() {
  const hasProfile = !!activeProfileId();
  return `
    <div class="tracker-page">
      <div class="page-header">
        <h1>${t('tracker.title')}</h1>
        <p class="page-subtitle">${t('tracker.subtitle')}</p>
      </div>
      ${renderProfileBar()}
      ${hasProfile ? `
        ${renderCharacter(trackerState.lastSave)}
        <section class="trk-tracking">
          <h2 class="trk-h2">${t('trk.tracked')} <span class="idb-count">${trackerState.trackedItems.length}</span></h2>
          ${renderTrackSearch()}
          <div id="trackedItemsArea">${renderTrackedChips()}</div>
        </section>
        <div id="trackerViewBar">${renderViewBar()}</div>
        <div id="trackerContent" class="trk-content">${renderContent()}</div>
        ${renderHistory()}
      ` : `
        <div class="trk-welcome">
          <p>${t('trk.welcome')}</p>
          ${renderUploadZone(false)}
        </div>
      `}
    </div>`;
}

function refreshTracking() {
  const chips = document.getElementById('trackedItemsArea');
  if (chips) chips.innerHTML = renderTrackedChips();
  const count = document.querySelector('.trk-tracking .trk-h2 .idb-count');
  if (count) count.textContent = trackerState.trackedItems.length;
  const bar = document.getElementById('trackerViewBar');
  if (bar) bar.innerHTML = renderViewBar();
  const content = document.getElementById('trackerContent');
  if (content) content.innerHTML = renderContent();
  hideItemTooltip();
}

function fullRerender() {
  document.getElementById('app').innerHTML = renderPage();
  wireDomEvents();
}

// ── Save handling ─────────────────────────────────────────────
function createProfileFromSave(parsed) {
  const id = Date.now().toString(36);
  profilesData.profiles.push({ id, name: parsed.class, heroClass: parsed.class, createdAt: Date.now() });
  profilesData.activeProfileId = id;
  saveProfiles(profilesData);
  trackerState = EMPTY_STATE();
  applyParsedSave(parsed);
}

function applyParsedSave(parsed) {
  trackerState.lastSave = parsed;
  if (parsed.loadCodes.length) {
    addCodeToProfileState(trackerState, {
      id: parsed.uploadedAt,
      username: parsed.username,
      class: parsed.class,
      level: parsed.level,
      version: parsed.version,
      codes: parsed.loadCodes,
      sections: parsed.sections,
      uploadedAt: parsed.uploadedAt,
    });
  }
  saveProfileState(activeProfileId(), trackerState);

  const profile = activeProfile();
  if (profile) {
    // Keep a custom name; only follow the class when the name was still the default.
    if (!profile.name || profile.name === profile.heroClass) profile.name = parsed.class;
    profile.heroClass = parsed.class;
    saveProfiles(profilesData);
  }
}

function describe(parsed) {
  return `${parsed.username} (${getClassName(parsed.class)} ${t('items.lv')} ${parsed.level})`;
}

async function ingest(text, { fileName = '', handle = null, newProfile = false } = {}) {
  const parsed = parseSaveFile(text);
  if (!parsed) {
    setFileStatus(t('trk.st.badFile'));
    return;
  }
  if (newProfile || !activeProfileId()) createProfileFromSave(parsed);
  else applyParsedSave(parsed);

  let linked = false;
  if (handle && supportsFileHandles()) {
    try {
      await storeFileHandle(activeProfileId(), handle);
      const profile = activeProfile();
      if (profile) { profile.linkedFileName = fileName; saveProfiles(profilesData); }
      linked = true;
    } catch (e) {}
  }
  setFileStatus(t(linked ? 'trk.st.loadedLinked' : 'trk.st.loaded', { who: describe(parsed) }));
  fullRerender();
}

async function chooseFile(opts = {}) {
  if (supportsFileHandles()) {
    try {
      const [handle] = await window.showOpenFilePicker({
        types: [{ description: 'WC3 Save File', accept: { 'text/plain': ['.txt'] } }],
      });
      const file = await handle.getFile();
      await ingest(await file.text(), { ...opts, fileName: file.name, handle });
    } catch (err) {
      if (err.name !== 'AbortError') setFileStatus(t('trk.st.openFailed'));
    }
    return;
  }
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = '.txt';
  input.onchange = async () => {
    if (input.files.length) await ingest(await input.files[0].text(), { ...opts, fileName: input.files[0].name });
  };
  input.click();
}

async function handleLinkFile() {
  try {
    const { handle, text, fileName } = await pickFile();
    await ingest(text, { fileName, handle });
    setFileStatus(t('trk.st.linked', { name: fileName }));
  } catch (e) {
    if (e.name !== 'AbortError') setFileStatus(t('trk.st.linkFailed'));
  }
}

async function handleRefreshFile() {
  const pid = activeProfileId();
  if (!pid) return;
  try {
    const handle = await getFileHandle(pid);
    if (!handle) { setFileStatus(t('trk.st.noLinked')); return; }
    setFileStatus(t('trk.st.reading'));
    const text = await readFileFromHandle(handle);
    if (text === null) { setFileStatus(t('trk.st.denied')); return; }
    const parsed = parseSaveFile(text);
    if (!parsed) { setFileStatus(t('trk.st.parseFailed')); return; }
    applyParsedSave(parsed);
    setFileStatus(t('trk.st.updated', { who: describe(parsed) }));
    fullRerender();
  } catch (e) {
    setFileStatus(t('trk.st.readFailed'));
  }
}

async function handleUnlinkFile() {
  const pid = activeProfileId();
  if (!pid) return;
  await removeFileHandle(pid);
  const profile = activeProfile();
  if (profile) { delete profile.linkedFileName; saveProfiles(profilesData); }
  setFileStatus(t('trk.st.unlinked'));
  fullRerender();
}

async function tryAutoRefresh() {
  const profile = activeProfile();
  if (!profile?.linkedFileName || !supportsFileHandles()) return;
  try {
    const handle = await getFileHandle(profile.id);
    if (!handle) return;
    if (await handle.queryPermission({ mode: 'read' }) !== 'granted') return;
    const parsed = parseSaveFile(await (await handle.getFile()).text());
    if (!parsed) return;
    const prev = trackerState.lastSave;
    if (prev?.uploadedAt && parsed.level === prev.level && JSON.stringify(parsed.inventory) === JSON.stringify(prev.inventory)) return;
    applyParsedSave(parsed);
    setFileStatus(t('trk.st.autoRefreshed', { who: describe(parsed) }));
    fullRerender();
  } catch (e) {}
}

// ── Search ────────────────────────────────────────────────────
let searchTimeout = null;
let results = [];
let cursor = 0;

function itemHay(item) {
  const loc = getLocale();
  const parts = [item.name, item.koreanname || ''];
  if (loc === 'zh') parts.push(translateItemName(item.name, 'zh'));
  return parts.join(' ').toLowerCase();
}

function renderResults() {
  const el = document.getElementById('trackerSearchResults');
  if (!el) return;
  el.hidden = !results.length;
  const tracked = new Set(trackerState.trackedItems);
  el.innerHTML = results.map((item, i) => `
    <div class="trk-result ${i === cursor ? 'cursor' : ''} ${rankInfo(item).css}" role="option" data-act="track" data-name="${esc(item.name)}" aria-selected="${i === cursor}">
      ${iconHtml(item.name, 'idb-chip-icon')}
      <span class="trk-result-name">${esc(localizedItemName(item))}</span>
      <span class="trk-result-meta">${tracked.has(item.name) ? t('trk.isTracked') : esc(rankInfo(item).label)}</span>
    </div>`).join('');
}

function runSearch(val) {
  const terms = val.toLowerCase().trim().split(/\s+/).filter(Boolean);
  results = terms.length
    ? itemData.filter(i => terms.every(x => itemHay(i).includes(x)))
        .sort((a, b) => tierIndex(a) - tierIndex(b) || a.name.localeCompare(b.name))
        .slice(0, 12)
    : [];
  cursor = 0;
  renderResults();
}

function openTrackPicker() {
  openItemPicker({
    title: t('trk.browseTitle'),
    tabs: [...EQUIP_TABS, MATERIAL_TAB, ALL_TAB],
    tab: 'all',
    allItems: true,
    current: () => new Set(trackerState.trackedItems),
    currentLabel: t('trk.isTracked'),
    // Stay open so several items can be tracked in one go.
    onPick: item => { trackItem(item.name); return true; },
  });
}

function trackItem(name) {
  if (trackerState.trackedItems.includes(name)) {
    showToast(t('trk.alreadyTracked', { name: localizedNameOf(name) }));
  } else {
    trackerState.trackedItems.push(name);
    saveProfileState(activeProfileId(), trackerState);
    refreshTracking();
  }
  const input = document.getElementById('trackerSearchInput');
  if (input) input.value = '';
  results = [];
  renderResults();
}

// ── Events ────────────────────────────────────────────────────
function wireDomEvents() {
  const zone = document.getElementById('uploadZone');
  if (zone) {
    zone.addEventListener('click', () => chooseFile());
    zone.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); chooseFile(); } });
    zone.addEventListener('dragover', e => { e.preventDefault(); zone.classList.add('drag-over'); });
    zone.addEventListener('dragleave', () => zone.classList.remove('drag-over'));
    zone.addEventListener('drop', async e => {
      e.preventDefault();
      zone.classList.remove('drag-over');
      const it = e.dataTransfer.items?.[0];
      if (it?.getAsFileSystemHandle) {
        try {
          const handle = await it.getAsFileSystemHandle();
          if (handle?.kind === 'file') {
            const file = await handle.getFile();
            await ingest(await file.text(), { fileName: file.name, handle });
            return;
          }
        } catch (err) {}
      }
      const file = e.dataTransfer.files?.[0];
      if (file) await ingest(await file.text(), { fileName: file.name });
    });
  }

  const input = document.getElementById('trackerSearchInput');
  if (input) {
    input.addEventListener('input', () => {
      clearTimeout(searchTimeout);
      searchTimeout = setTimeout(() => runSearch(input.value), 80);
    });
    input.addEventListener('keydown', e => {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        if (!results.length) return;
        e.preventDefault();
        cursor = (cursor + (e.key === 'ArrowDown' ? 1 : -1) + results.length) % results.length;
        renderResults();
      } else if (e.key === 'Enter' && results[cursor]) {
        e.preventDefault();
        trackItem(results[cursor].name);
      } else if (e.key === 'Escape') {
        input.value = '';
        results = [];
        renderResults();
      }
    });
    input.addEventListener('blur', () => setTimeout(() => { results = []; renderResults(); }, 150));
  }
}

async function onAppClick(e) {
  const el = e.target.closest('[data-act]');
  if (!el) return;
  const act = el.dataset.act;
  if (act === 'track') { e.preventDefault(); return trackItem(el.dataset.name); }
  if (act === 'browse-items') return openTrackPicker();
  if (act === 'untrack') {
    trackerState.trackedItems.splice(+el.dataset.idx, 1);
    saveProfileState(activeProfileId(), trackerState);
    return refreshTracking();
  }
  if (act === 'view') { currentView = el.dataset.view; return refreshTracking(); }
  if (act === 'expand-all' || act === 'collapse-all') {
    document.querySelectorAll('.trk-tree details').forEach(d => { d.open = act === 'expand-all'; });
    return;
  }
  if (act === 'switch-profile') {
    profilesData.activeProfileId = el.dataset.id;
    saveProfiles(profilesData);
    trackerState = loadProfileState(el.dataset.id);
    fullRerender();
    return tryAutoRefresh();
  }
  if (act === 'add-profile') return chooseFile({ newProfile: true });
  if (act === 'rename-profile') {
    const profile = activeProfile();
    const name = profile && prompt(t('trk.renamePrompt'), profile.name);
    if (!name?.trim()) return;
    profile.name = name.trim();
    saveProfiles(profilesData);
    return fullRerender();
  }
  if (act === 'delete-profile') {
    const profile = activeProfile();
    if (!profile || !confirm(t('trk.deleteConfirm', { name: profile.name }))) return;
    profilesData.profiles = profilesData.profiles.filter(p => p.id !== profile.id);
    deleteProfileState(profile.id);
    removeFileHandle(profile.id);
    profilesData.activeProfileId = profilesData.profiles[0]?.id || null;
    saveProfiles(profilesData);
    trackerState = profilesData.activeProfileId ? loadProfileState(profilesData.activeProfileId) : EMPTY_STATE();
    return fullRerender();
  }
  if (act === 'remove-save') {
    if (!confirm(t('trk.removeConfirm'))) return;
    trackerState.lastSave = null;
    saveProfileState(activeProfileId(), trackerState);
    return fullRerender();
  }
  if (act === 'link-file') return handleLinkFile();
  if (act === 'refresh-file') return handleRefreshFile();
  if (act === 'unlink-file') return handleUnlinkFile();
  if (act === 'copy-codes') {
    const entry = trackerState.loadCodeHistory?.[+el.dataset.idx];
    if (!entry) return;
    showToast(t(await copyText(entry.codes.join('\n')) ? 'trk.codesCopied' : 'trk.copyFailed'));
  }
}

export async function initTracker() {
  await Promise.all([loadItemData(), loadBossData(), loadHeroData()]);
  profilesData = migrateToProfiles();
  const pid = activeProfileId();
  trackerState = pid ? loadProfileState(pid) : EMPTY_STATE();

  const app = document.getElementById('app');
  app.innerHTML = renderPage();
  wireDomEvents();
  app.addEventListener('click', onAppClick);
  const unbindHover = bindItemHover(app);
  tryAutoRefresh();

  return () => {
    app.removeEventListener('click', onAppClick);
    unbindHover();
    clearTimeout(searchTimeout);
    closePicker();
    hideItemTooltip();
  };
}
