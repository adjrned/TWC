import { esc } from '../../ui/escape.js';
import { parseSaveFile } from './parser.js';
import {
  loadProfiles, saveProfiles, loadProfileState, saveProfileState,
  deleteProfileState, migrateToProfiles, addCodeToProfileState,
} from './storage.js';
import { buildItemMap, buildOwnedMap, buildRecipeTree, buildComprehensiveData, flattenToLeaves } from './tree.js';
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

function activeProfileId() {
  return profilesData?.activeProfileId || null;
}

function activeProfile() {
  if (!profilesData) return null;
  return profilesData.profiles.find(p => p.id === profilesData.activeProfileId) || null;
}

async function loadItemData() {
  if (itemData) return;
  try {
    const r = await fetch('data/items.json');
    if (r.ok) itemData = await r.json();
  } catch (e) {}
  if (!itemData) itemData = [];
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
      for (const key of classNameKeys(h.heroClass)) {
        heroIconMap.set(key, h.icon);
      }
    }
  }
}

function getHeroIcon(heroClass) {
  if (!heroClass) return '';
  if (heroIconMap?.has(heroClass)) return `twicons/${heroIconMap.get(heroClass)}.jpg`;
  for (const key of classNameKeys(heroClass)) {
    if (heroIconMap?.has(key)) return `twicons/${heroIconMap.get(key)}.jpg`;
  }
  return `twicons/${heroClass.replace(/[^a-zA-Z]/g, '')}Icon.jpg`;
}

function setFileStatus(msg) {
  fileStatusMessage = msg;
  const el = document.getElementById('fileStatusMsg');
  if (el) {
    el.textContent = msg;
    el.style.display = msg ? '' : 'none';
  }
  if (msg) {
    setTimeout(() => {
      fileStatusMessage = '';
      const el2 = document.getElementById('fileStatusMsg');
      if (el2) el2.style.display = 'none';
    }, 5000);
  }
}

function renderProfileSelector() {
  if (!profilesData) return '';
  const profiles = profilesData.profiles;
  const active = activeProfileId();

  const tabs = profiles.map(p => {
    const isActive = p.id === active;
    const label = p.name.length > 20 ? p.name.slice(0, 18) + '...' : p.name;
    const iconSrc = getHeroIcon(p.heroClass);
    const iconHtml = iconSrc ? `<img src="${esc(iconSrc)}" alt="" class="profile-tab-icon" onerror="this.style.display='none'">` : '';
    return `<button class="profile-tab ${isActive ? 'active' : ''}" onclick="window._trackerSwitchProfile('${p.id}')" title="${esc(p.name)}">${iconHtml}${esc(label)}</button>`;
  }).join('');

  return `
    <div class="profile-bar">
      <div class="profile-tabs">
        ${tabs}
        <button class="profile-tab profile-add" onclick="window._trackerAddProfile()" title="Add new character profile">+</button>
      </div>
      ${active ? `<div class="profile-actions">
        <button class="btn-small" onclick="window._trackerRenameProfile()">Rename</button>
        <button class="btn-small btn-danger" onclick="window._trackerDeleteProfile()">Delete</button>
      </div>` : ''}
    </div>
  `;
}

function renderUploadArea(hasSave) {
  const hasFileAPI = supportsFileHandles();

  if (hasSave) {
    return `
      <div class="tracker-upload-compact" id="trackerUpload">
        <div class="upload-compact-zone" id="uploadZone">
          <span class="upload-compact-icon">📂</span>
          <span class="upload-compact-text">Drop or click to update save</span>
          <input type="file" id="fileInput" accept=".txt" hidden>
          ${hasFileAPI ? `<button class="btn-small btn-link-file" id="btnLinkFile" onclick="event.stopPropagation(); window._trackerLinkFile()">Link File</button>` : ''}
        </div>
        <div class="file-status" id="fileStatusMsg" style="display:${fileStatusMessage ? '' : 'none'}">${esc(fileStatusMessage)}</div>
      </div>
    `;
  }

  return `
    <div class="tracker-upload" id="trackerUpload">
      <div class="upload-zone" id="uploadZone">
        <div class="upload-icon">📂</div>
        <p>Drop your save file here or click to browse</p>
        <span class="upload-hint">WC3 save file (.txt)</span>
        ${hasFileAPI ? '<span class="upload-hint-linked">You can link a file for quick refresh (Chrome/Edge)</span>' : ''}
        <input type="file" id="fileInput" accept=".txt" hidden>
        ${hasFileAPI ? `<button class="btn-small btn-link-file" id="btnLinkFile" onclick="event.stopPropagation(); window._trackerLinkFile()">Link File for Auto-Refresh</button>` : ''}
      </div>
      <div class="file-status" id="fileStatusMsg" style="display:${fileStatusMessage ? '' : 'none'}">${esc(fileStatusMessage)}</div>
    </div>
  `;
}

function renderLinkedFileInfo() {
  const profile = activeProfile();
  if (!profile || !profile.linkedFileName) return '';
  return `
    <div class="linked-file-info">
      <span class="linked-file-icon">🔗</span>
      <span class="linked-file-name">${esc(profile.linkedFileName)}</span>
      <button class="btn-small" onclick="window._trackerRefreshFile()" title="Re-read the linked file to update inventory">Refresh</button>
      <button class="btn-small btn-danger" onclick="window._trackerUnlinkFile()" title="Stop auto-reading this file">Unlink</button>
    </div>
  `;
}

function renderCharacterOverview(save) {
  if (!save) return '';
  const classIcon = getHeroIcon(save.class);
  const sectionOrder = ['Hero Inventory', 'Bag', 'Storage'];

  const sectionsHtml = sectionOrder.map(name => {
    const items = save.sections[name];
    if (!items || !items.length) return '';
    const itemsHtml = items.map(({ name: itemName, qty }) => {
      const title = qty > 1 ? `${itemName} x${qty}` : itemName;
      return `<a href="#/items/${encodeURIComponent(itemName)}" class="inv-icon-link" title="${esc(title)}">
        <img src="twicons/${encodeURIComponent(itemName)}.jpg" alt="${esc(itemName)}" class="inv-icon" onerror="this.style.display='none'">
        ${qty > 1 ? `<span class="inv-icon-qty">x${qty}</span>` : ''}
      </a>`;
    }).join('');
    return `
      <div class="inv-section">
        <h3 class="inv-section-title">${esc(name)}</h3>
        <div class="inv-icons">${itemsHtml}</div>
      </div>
    `;
  }).join('');

  return `
    <div class="tracker-overview">
      <div class="overview-header">
        <img src="${esc(classIcon)}" alt="${esc(save.class)}" class="overview-class-icon" onerror="this.style.display='none'">
        <div class="overview-identity">
          <h2>${esc(save.username)}</h2>
          <span class="overview-class">${esc(save.class)} &middot; Lv.${save.level}</span>
        </div>
        <div class="overview-actions">
          <span class="overview-version">v${esc(save.version)}</span>
          <button class="btn-small btn-danger" onclick="window._trackerDeleteSave()">Remove</button>
        </div>
      </div>
      ${sectionsHtml}
    </div>
  `;
}

function renderSearchArea() {
  return `
    <div class="tracker-search-section">
      <div class="tracker-search-bar">
        <input type="text" id="trackerSearchInput" placeholder="Search items to track..." oninput="window._trackerSearchInput(this.value)">
      </div>
      <div class="tracker-search-results" id="trackerSearchResults"></div>
    </div>
  `;
}

function renderTrackedList() {
  if (!trackerState.trackedItems.length) return '<div class="tracked-empty">No items tracked yet. Search above to add items.</div>';
  return `
    <div class="tracked-items-list">
      ${trackerState.trackedItems.map((name, idx) => `
        <div class="tracked-chip">
          <img src="twicons/${encodeURIComponent(name)}.jpg" alt="" class="tracked-chip-icon" onerror="this.style.display='none'">
          <span>${esc(name)}</span>
          <button class="tracked-remove" onclick="window._trackerUntrackItem(${idx})">×</button>
        </div>
      `).join('')}
    </div>
  `;
}

function renderViewToggle() {
  return `
    <div class="tracker-view-bar">
      <div class="tracker-view-toggle">
        <button class="view-tab ${currentView === 'split' ? 'active' : ''}" onclick="window._trackerSetView('split')">Split View</button>
        <button class="view-tab ${currentView === 'comprehensive' ? 'active' : ''}" onclick="window._trackerSetView('comprehensive')">Comprehensive</button>
      </div>
      ${currentView === 'split' ? `
        <div class="tree-expand-controls">
          <button class="btn-small" onclick="window._trackerExpandAll()">Expand All</button>
          <button class="btn-small" onclick="window._trackerCollapseAll()">Collapse All</button>
        </div>
      ` : ''}
    </div>
  `;
}

function renderTreeNode(node, depth, counter) {
  const id = `tn-${counter.value++}`;
  const collapsed = (depth > 1 || node.status === 'have') ? 'collapsed' : '';
  const statusClass = `status-${node.status}`;
  const hasChildren = node.children.length > 0;
  const toggle = hasChildren ? `<button type="button" class="tree-toggle" onclick="event.stopPropagation();window._toggleTreeNode('${id}',this)">${collapsed ? '▶' : '▼'}</button>` : '<span class="tree-toggle-spacer"></span>';
  const qtyLabel = node.neededQty > 1 ? `<span class="tree-qty">x${node.neededQty}</span>` : '';
  const ownedLabel = `<span class="tree-owned ${statusClass}">${node.ownedQty}/${node.neededQty}</span>`;
  const rateLabel = node.droppedBy.length && node.droprate ? `<span class="tree-drop-rate">${(node.droprate * 100).toFixed(2)}%</span>` : '';
  let bossHint = '';
  if (node.droppedBy.length) {
    const icons = node.droppedBy.map(b =>
      `<img src="twicons/${encodeURIComponent(b + ' Icon')}.jpg" alt="${esc(b)}" title="${esc(b)}" class="tree-boss-icon" onerror="this.style.display='none'">`
    ).join('');
    bossHint = `<span class="tree-boss-hint">${icons}</span>`;
  } else if (!node.isLeaf) {
    bossHint = node.status === 'have'
      ? `<span class="tree-boss-hint tree-craftable">Crafted</span>`
      : `<span class="tree-boss-hint tree-craftable">Craftable</span>`;
  }

  let childrenHtml = '';
  if (hasChildren) {
    childrenHtml = `<div class="tree-children ${collapsed}" data-node-id="${id}">
      ${node.children.map(c => renderTreeNode(c, depth + 1, counter)).join('')}
    </div>`;
  }

  const altRow = node.alternatives && node.alternatives.length
    ? `<div class="tree-alt-row">
        <span class="tree-alt-label">or</span>
        ${node.alternatives.map(a =>
          `<a href="#/items/${encodeURIComponent(a)}" class="tree-alt-item">
            <img src="twicons/${encodeURIComponent(a)}.jpg" alt="${esc(a)}" class="tree-alt-icon" onerror="this.style.display='none'">
            <span class="tree-alt-name">${esc(a)}</span>
          </a>`
        ).join('')}
      </div>`
    : '';

  return `
    <div class="tree-node depth-${Math.min(depth, 5)}">
      <div class="tree-node-row">
        ${toggle}
        <img src="twicons/${encodeURIComponent(node.name)}.jpg" alt="" class="tree-node-icon" onerror="this.style.display='none'">
        <a href="#/items/${encodeURIComponent(node.name)}" class="tree-node-name">${esc(node.name)}</a>
        ${qtyLabel}
        ${ownedLabel}
        ${rateLabel}
        ${bossHint}
      </div>
      ${altRow}
      ${childrenHtml}
    </div>
  `;
}

function renderSplitView() {
  if (!trackerState.trackedItems.length) {
    return '<div class="tracker-content-empty">Track items above to see their recipe breakdown.</div>';
  }

  const ownedMap = buildOwnedMap(trackerState.lastSave?.inventory);
  const trees = trackerState.trackedItems.map(name => {
    const tree = buildRecipeTree(name, 1, itemMap, ownedMap);
    const counter = { value: 0 };
    return `
      <div class="tree-root">
        <div class="tree-root-header">
          <img src="twicons/${encodeURIComponent(name)}.jpg" alt="" class="tree-root-icon" onerror="this.style.display='none'">
          <h3><a href="#/items/${encodeURIComponent(name)}">${esc(name)}</a></h3>
        </div>
        <div class="tree-body">
          ${tree.children.map(c => renderTreeNode(c, 0, counter)).join('')}
        </div>
      </div>
    `;
  });

  return trees.join('');
}

function renderComprehensiveView() {
  if (!trackerState.trackedItems.length) {
    return '<div class="tracker-content-empty">Track items above to see materials needed.</div>';
  }

  const ownedMap = buildOwnedMap(trackerState.lastSave?.inventory);
  const groups = buildComprehensiveData(trackerState.trackedItems, itemMap, ownedMap, bossData);
  const entries = Object.entries(groups);

  if (!entries.length) {
    return '<div class="tracker-content-empty">All materials acquired!</div>';
  }

  return entries.map(([bossName, { boss, materials }]) => {
    const matsHtml = materials.map(m => {
      const droprate = m.item ? (m.item.droprate || 0) : 0;
      const rateStr = droprate ? `${(droprate * 100).toFixed(2)}%` : '';
      return `
        <div class="comp-material">
          <img src="twicons/${encodeURIComponent(m.name)}.jpg" alt="" class="comp-mat-icon" onerror="this.style.display='none'">
          <a href="#/items/${encodeURIComponent(m.name)}" class="comp-mat-name">${esc(m.name)}</a>
          <span class="comp-mat-count status-none">Need ${m.needed}</span>
          ${rateStr ? `<span class="comp-drop-rate">${rateStr}</span>` : ''}
        </div>
      `;
    }).join('');

    const headerHtml = boss
      ? `<a href="#/bosses/${encodeURIComponent(boss.id)}" class="comp-boss-link">
          <img src="twicons/${encodeURIComponent(bossName + ' Icon')}.jpg" alt="${esc(bossName)}" class="comp-boss-header-icon" onerror="this.style.display='none'">
          <span>${esc(bossName)}</span>
        </a>`
      : `<span class="comp-boss-link comp-craftable-header">${esc(bossName)}</span>`;

    return `
      <div class="comp-boss-section">
        <div class="comp-boss-header">${headerHtml}</div>
        <div class="comp-materials-list">${matsHtml}</div>
      </div>
    `;
  }).join('');
}

function renderCumulativeSummary() {
  if (!trackerState.trackedItems.length) return '';

  const ownedMap = buildOwnedMap(trackerState.lastSave?.inventory);
  const totals = new Map();
  const sharedRemaining = new Map();
  for (const [k, v] of ownedMap) sharedRemaining.set(k, v);

  for (const itemName of trackerState.trackedItems) {
    const leaves = flattenToLeaves(itemName, 1, itemMap, ownedMap, new Map(), new Set(), sharedRemaining);
    for (const [matName, needed] of leaves) {
      if (matName.includes('Soulstone') || matName.includes('Token') || matName === 'Prius Silver Coin' || matName === 'Prius Gold Coin') continue;
      totals.set(matName, (totals.get(matName) || 0) + needed);
    }
  }

  const items = [...totals.entries()]
    .map(([name, needed]) => ({ name, needed }))
    .filter(m => m.needed > 0);

  if (!items.length) return '<div class="cumulative-summary"><p class="cumulative-complete">All materials acquired!</p></div>';

  const iconsHtml = items.map(m => {
    return `<a href="#/items/${encodeURIComponent(m.name)}" class="inv-icon-link" title="${esc(m.name)} — need ${m.needed}">
      <img src="twicons/${encodeURIComponent(m.name)}.jpg" alt="${esc(m.name)}" class="inv-icon" onerror="this.style.display='none'">
      <span class="inv-icon-qty">x${m.needed}</span>
    </a>`;
  }).join('');

  return `
    <div class="cumulative-summary">
      <h3 class="cumulative-title">Total Materials Needed</h3>
      <div class="inv-icons">${iconsHtml}</div>
    </div>
  `;
}

function renderContent() {
  return currentView === 'split' ? renderSplitView() : renderComprehensiveView();
}

function renderLoadCodeHistory() {
  const history = trackerState.loadCodeHistory || [];
  if (!history.length) return '';

  const entries = history.map((entry, i) => {
    const date = new Date(entry.uploadedAt).toLocaleDateString();
    return `
      <div class="history-entry">
        <div class="history-entry-header" onclick="window._toggleHistoryEntry(${i})">
          <span class="history-char">${esc(entry.username)} (${esc(entry.class)} Lv.${entry.level})</span>
          <span class="history-date">${date}</span>
          <span class="history-chevron" id="histChev${i}">▶</span>
        </div>
        <div class="history-entry-body collapsed" id="histBody${i}">
          <pre class="history-codes">${entry.codes.map(c => esc(c)).join('\n')}</pre>
          <button class="btn-small" onclick="window._trackerCopyCodes(${i})">Copy Codes</button>
        </div>
      </div>
    `;
  }).join('');

  return `
    <div class="tracker-history">
      <h2 class="tracker-section-title">Load Code History</h2>
      ${entries}
    </div>
  `;
}

function renderPage() {
  const hasSave = !!trackerState.lastSave;
  return `
    <div class="tracker-page">
      <h1 class="tracker-title">Item Tracker</h1>
      ${renderProfileSelector()}
      ${activeProfileId() ? `
        ${renderUploadArea(hasSave)}
        ${renderLinkedFileInfo()}
        ${renderCharacterOverview(trackerState.lastSave)}
        ${renderSearchArea()}
        <div id="trackedItemsArea">${renderTrackedList()}</div>
        ${hasSave || trackerState.trackedItems.length ? `
          ${renderViewToggle()}
          ${currentView === 'comprehensive' ? `<div id="cumulativeSummary">${renderCumulativeSummary()}</div>` : ''}
          <div id="trackerContent" class="tracker-content">${renderContent()}</div>
        ` : ''}
        ${renderLoadCodeHistory()}
      ` : `
        <div class="tracker-no-profile">
          <p>Upload a save file to create your first character profile.</p>
          ${renderUploadArea(false)}
        </div>
      `}
    </div>
  `;
}

function refreshTrackedList() {
  const el = document.getElementById('trackedItemsArea');
  if (el) el.innerHTML = renderTrackedList();
}

function refreshContent() {
  const el = document.getElementById('trackerContent');
  if (el) el.innerHTML = renderContent();
}

function fullRerender() {
  const app = document.getElementById('app');
  app.innerHTML = renderPage();
}

function createProfileFromSave(parsed) {
  const id = Date.now().toString(36);
  profilesData.profiles.push({ id, name: parsed.class, heroClass: parsed.class, createdAt: Date.now() });
  profilesData.activeProfileId = id;
  saveProfiles(profilesData);

  trackerState = { version: 1, trackedItems: [], lastSave: null, loadCodeHistory: [] };
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
      uploadedAt: parsed.uploadedAt,
    });
  }

  saveProfileState(activeProfileId(), trackerState);

  const profile = activeProfile();
  if (profile) {
    profile.name = parsed.class;
    profile.heroClass = parsed.class;
    saveProfiles(profilesData);
  }
}

function handleFileUpload(file) {
  const reader = new FileReader();
  reader.onload = (e) => {
    const parsed = parseSaveFile(e.target.result);
    if (!parsed) {
      alert('Could not parse save file. Please upload a valid WC3 save file.');
      return;
    }
    if (!activeProfileId()) {
      createProfileFromSave(parsed);
    } else {
      applyParsedSave(parsed);
    }
    setFileStatus(`Save loaded: ${parsed.username} (${parsed.class} Lv.${parsed.level})`);
    fullRerender();
    wireEvents();
  };
  reader.readAsText(file);
}

async function handleLinkFile() {
  try {
    const { handle, text, fileName } = await pickFile();
    const parsed = parseSaveFile(text);
    if (!parsed) {
      alert('Could not parse save file. Please select a valid WC3 save file.');
      return;
    }

    if (!activeProfileId()) {
      createProfileFromSave(parsed);
    } else {
      applyParsedSave(parsed);
    }

    await storeFileHandle(activeProfileId(), handle);

    const profile = activeProfile();
    if (profile) {
      profile.linkedFileName = fileName;
      saveProfiles(profilesData);
    }

    setFileStatus(`File linked: ${fileName} — use Refresh to re-read anytime`);
    fullRerender();
    wireEvents();
  } catch (e) {
    if (e.name !== 'AbortError') {
      setFileStatus('Could not link file. Try again or use drag-and-drop.');
    }
  }
}

async function handleRefreshFile() {
  const pid = activeProfileId();
  if (!pid) return;
  try {
    const handle = await getFileHandle(pid);
    if (!handle) {
      setFileStatus('No linked file found. Please link a file first.');
      return;
    }
    setFileStatus('Reading file...');
    const text = await readFileFromHandle(handle);
    if (text === null) {
      setFileStatus('Permission denied. Click Refresh again to grant access.');
      return;
    }
    const parsed = parseSaveFile(text);
    if (!parsed) {
      setFileStatus('File could not be parsed. It may have been modified or is not a valid save.');
      return;
    }
    applyParsedSave(parsed);
    setFileStatus(`Updated: ${parsed.username} (${parsed.class} Lv.${parsed.level})`);
    fullRerender();
    wireEvents();
  } catch (e) {
    setFileStatus('Could not read file. The file may have been moved or deleted.');
  }
}

async function handleUnlinkFile() {
  const pid = activeProfileId();
  if (!pid) return;
  await removeFileHandle(pid);
  const profile = activeProfile();
  if (profile) {
    delete profile.linkedFileName;
    saveProfiles(profilesData);
  }
  setFileStatus('File unlinked.');
  fullRerender();
  wireEvents();
}

async function tryAutoRefresh() {
  const pid = activeProfileId();
  if (!pid) return;
  const profile = activeProfile();
  if (!profile || !profile.linkedFileName) return;
  if (!supportsFileHandles()) return;

  try {
    const handle = await getFileHandle(pid);
    if (!handle) return;
    const permission = await handle.queryPermission({ mode: 'read' });
    if (permission !== 'granted') return;
    const file = await handle.getFile();
    const text = await file.text();
    const parsed = parseSaveFile(text);
    if (!parsed) return;

    const prev = trackerState.lastSave;
    if (prev && prev.uploadedAt && parsed.level === prev.level &&
        JSON.stringify(parsed.inventory) === JSON.stringify(prev.inventory)) {
      return;
    }

    applyParsedSave(parsed);
    setFileStatus(`Auto-refreshed: ${parsed.username} (${parsed.class} Lv.${parsed.level})`);
    fullRerender();
    wireEvents();
  } catch (e) {}
}

let searchTimeout = null;

function handleSearch(val) {
  clearTimeout(searchTimeout);
  const resultsEl = document.getElementById('trackerSearchResults');
  if (!resultsEl) return;

  const q = val.toLowerCase().trim();
  if (!q) { resultsEl.innerHTML = ''; return; }

  searchTimeout = setTimeout(() => {
    const matches = itemData
      .filter(item => item.name.toLowerCase().includes(q))
      .slice(0, 10);

    resultsEl.innerHTML = matches.map(item => `
      <div class="search-result" onclick="window._trackerTrackItem('${esc(item.name.replace(/'/g, "\\'"))}')">
        <img src="twicons/${encodeURIComponent(item.name)}.jpg" alt="" class="search-result-icon" onerror="this.style.display='none'">
        <span>${esc(item.name)}</span>
      </div>
    `).join('');
  }, 150);
}

function wireEvents() {
  const uploadZone = document.getElementById('uploadZone');
  const fileInput = document.getElementById('fileInput');

  if (uploadZone) {
    uploadZone.addEventListener('click', (e) => {
      if (e.target.closest('#btnLinkFile')) return;
      fileInput?.click();
    });
    uploadZone.addEventListener('dragover', (e) => { e.preventDefault(); uploadZone.classList.add('drag-over'); });
    uploadZone.addEventListener('dragleave', () => uploadZone.classList.remove('drag-over'));
    uploadZone.addEventListener('drop', (e) => {
      e.preventDefault();
      uploadZone.classList.remove('drag-over');
      if (e.dataTransfer.files.length) handleFileUpload(e.dataTransfer.files[0]);
    });
  }

  if (fileInput) {
    fileInput.addEventListener('change', () => {
      if (fileInput.files.length) handleFileUpload(fileInput.files[0]);
    });
  }
}

function switchProfile(id) {
  profilesData.activeProfileId = id;
  saveProfiles(profilesData);
  trackerState = loadProfileState(id);
  fullRerender();
  wireEvents();
  tryAutoRefresh();
}

export async function initTracker({ params, query }) {
  await loadItemData();
  await loadBossData();
  await loadHeroData();

  profilesData = migrateToProfiles();
  const pid = activeProfileId();
  trackerState = pid ? loadProfileState(pid) : { version: 1, trackedItems: [], lastSave: null, loadCodeHistory: [] };

  const app = document.getElementById('app');
  app.innerHTML = renderPage();
  wireEvents();

  tryAutoRefresh();

  window._trackerSearchInput = handleSearch;

  window._trackerSwitchProfile = switchProfile;

  window._trackerAddProfile = () => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.txt';
    input.onchange = () => {
      if (!input.files.length) return;
      const reader = new FileReader();
      reader.onload = (e) => {
        const parsed = parseSaveFile(e.target.result);
        if (!parsed) {
          alert('Could not parse save file. Please upload a valid WC3 save file.');
          return;
        }
        createProfileFromSave(parsed);
        setFileStatus(`Profile created: ${parsed.username} (${parsed.class} Lv.${parsed.level})`);
        fullRerender();
        wireEvents();
      };
      reader.readAsText(input.files[0]);
    };
    input.click();
  };

  window._trackerRenameProfile = () => {
    const profile = activeProfile();
    if (!profile) return;
    const name = prompt('Rename profile:', profile.name);
    if (!name || !name.trim()) return;
    profile.name = name.trim();
    saveProfiles(profilesData);
    fullRerender();
    wireEvents();
  };

  window._trackerDeleteProfile = () => {
    const profile = activeProfile();
    if (!profile) return;
    if (!confirm(`Delete profile "${profile.name}"? This will remove all tracked items and save data for this character.`)) return;
    const id = profile.id;
    profilesData.profiles = profilesData.profiles.filter(p => p.id !== id);
    deleteProfileState(id);
    removeFileHandle(id);
    profilesData.activeProfileId = profilesData.profiles.length ? profilesData.profiles[0].id : null;
    saveProfiles(profilesData);
    trackerState = profilesData.activeProfileId
      ? loadProfileState(profilesData.activeProfileId)
      : { version: 1, trackedItems: [], lastSave: null, loadCodeHistory: [] };
    fullRerender();
    wireEvents();
  };

  window._trackerLinkFile = handleLinkFile;
  window._trackerRefreshFile = handleRefreshFile;
  window._trackerUnlinkFile = handleUnlinkFile;

  window._trackerTrackItem = (name) => {
    trackerState.trackedItems.push(name);
    saveProfileState(activeProfileId(), trackerState);
    refreshTrackedList();
    refreshContent();
    const resultsEl = document.getElementById('trackerSearchResults');
    if (resultsEl) resultsEl.innerHTML = '';
    const input = document.getElementById('trackerSearchInput');
    if (input) input.value = '';
  };

  window._trackerUntrackItem = (idx) => {
    trackerState.trackedItems.splice(idx, 1);
    saveProfileState(activeProfileId(), trackerState);
    refreshTrackedList();
    refreshContent();
  };

  window._trackerSetView = (view) => {
    currentView = view;
    fullRerender();
    wireEvents();
  };

  window._toggleTreeNode = (id, btn) => {
    const treeNode = btn.closest('.tree-node');
    const children = treeNode?.querySelector(`:scope > [data-node-id="${id}"]`);
    if (children) {
      children.classList.toggle('collapsed');
      btn.textContent = children.classList.contains('collapsed') ? '▶' : '▼';
    }
  };

  window._trackerExpandAll = () => {
    document.querySelectorAll('.tree-children.collapsed').forEach(el => {
      el.classList.remove('collapsed');
    });
    document.querySelectorAll('.tree-toggle').forEach(btn => { btn.textContent = '▼'; });
  };

  window._trackerCollapseAll = () => {
    document.querySelectorAll('.tree-children').forEach(el => {
      el.classList.add('collapsed');
    });
    document.querySelectorAll('.tree-toggle').forEach(btn => { btn.textContent = '▶'; });
  };

  window._toggleHistoryEntry = (idx) => {
    const body = document.getElementById(`histBody${idx}`);
    const chev = document.getElementById(`histChev${idx}`);
    if (body) {
      body.classList.toggle('collapsed');
      if (chev) chev.textContent = body.classList.contains('collapsed') ? '▶' : '▼';
    }
  };

  window._trackerCopyCodes = (idx) => {
    const history = trackerState.loadCodeHistory || [];
    if (history[idx]) {
      navigator.clipboard.writeText(history[idx].codes.join('\n'));
    }
  };

  window._trackerDeleteSave = () => {
    trackerState.lastSave = null;
    saveProfileState(activeProfileId(), trackerState);
    fullRerender();
    wireEvents();
  };

  return () => {
    delete window._trackerSearchInput;
    delete window._trackerTrackItem;
    delete window._trackerUntrackItem;
    delete window._trackerSetView;
    delete window._toggleTreeNode;
    delete window._trackerExpandAll;
    delete window._trackerCollapseAll;
    delete window._toggleHistoryEntry;
    delete window._trackerCopyCodes;
    delete window._trackerDeleteSave;
    delete window._trackerSwitchProfile;
    delete window._trackerAddProfile;
    delete window._trackerRenameProfile;
    delete window._trackerDeleteProfile;
    delete window._trackerLinkFile;
    delete window._trackerRefreshFile;
    delete window._trackerUnlinkFile;
    clearTimeout(searchTimeout);
  };
}
