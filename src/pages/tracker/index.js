import { esc } from '../../ui/escape.js';
import { parseSaveFile } from './parser.js';
import { loadTrackerState, saveTrackerState, loadCodeHistory, addCodeHistoryEntry } from './storage.js';
import { buildItemMap, buildOwnedMap, buildRecipeTree, buildComprehensiveData, flattenToLeaves } from './tree.js';

let itemData = null;
let bossData = null;
let itemMap = null;
let trackerState = null;
let currentView = 'split';

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

function renderUploadArea(hasSave) {
  return `
    <div class="tracker-upload ${hasSave ? 'has-save' : ''}" id="trackerUpload">
      <div class="upload-zone" id="uploadZone" onclick="document.getElementById('fileInput').click()">
        <div class="upload-icon">📂</div>
        <p>Drop your save file here or click to browse</p>
        <span class="upload-hint">WC3 save file (.txt)</span>
        <input type="file" id="fileInput" accept=".txt" hidden>
      </div>
    </div>
  `;
}

function renderCharacterOverview(save) {
  if (!save) return '';
  const classIcon = `twicons/${save.class.replace(/\s+/g, '')}Icon.jpg`;
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
      ${trackerState.trackedItems.map(name => `
        <div class="tracked-chip">
          <img src="twicons/${encodeURIComponent(name)}.jpg" alt="" class="tracked-chip-icon" onerror="this.style.display='none'">
          <span>${esc(name)}</span>
          <button class="tracked-remove" onclick="window._trackerUntrackItem('${esc(name.replace(/'/g, "\\'"))}')">×</button>
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
  const toggle = hasChildren ? `<button class="tree-toggle" onclick="window._toggleTreeNode('${id}')">${collapsed ? '▶' : '▼'}</button>` : '<span class="tree-toggle-spacer"></span>';
  const qtyLabel = node.neededQty > 1 ? `<span class="tree-qty">x${node.neededQty}</span>` : '';
  const ownedLabel = `<span class="tree-owned ${statusClass}">${node.ownedQty}/${node.neededQty}</span>`;
  let bossHint = '';
  if (node.droppedBy.length) {
    bossHint = `<span class="tree-boss-hint">${node.droppedBy.map(b => esc(b)).join(', ')}</span>`;
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

  return `
    <div class="tree-node depth-${Math.min(depth, 5)}">
      <div class="tree-node-row">
        ${toggle}
        <img src="twicons/${encodeURIComponent(node.name)}.jpg" alt="" class="tree-node-icon" onerror="this.style.display='none'">
        <a href="#/items/${encodeURIComponent(node.name)}" class="tree-node-name">${esc(node.name)}</a>
        ${qtyLabel}
        ${ownedLabel}
        ${bossHint}
      </div>
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
  const data = buildComprehensiveData(trackerState.trackedItems, itemMap, ownedMap, bossData);

  return data.map(({ itemName, materials }) => {
    const matsHtml = materials.map(m => {
      const status = m.owned >= m.needed ? 'have' : m.owned > 0 ? 'partial' : 'none';
      const hasRecipe = m.item && m.item.recipe && m.item.recipe.length > 0;
      let sourceHtml = '';
      if (m.bosses.length) {
        sourceHtml = m.bosses.map(b => b.boss
            ? `<a href="#/bosses/${encodeURIComponent(b.boss.id)}" class="comp-boss-link">${esc(b.name)}</a>`
            : `<span class="comp-boss-link">${esc(b.name)}</span>`
          ).join(', ');
      } else if (hasRecipe) {
        sourceHtml = status === 'have'
          ? '<span class="comp-craftable">Crafted</span>'
          : '<span class="comp-craftable">Craftable</span>';
      }

      return `
        <div class="comp-material">
          <img src="twicons/${encodeURIComponent(m.name)}.jpg" alt="" class="comp-mat-icon" onerror="this.style.display='none'">
          <a href="#/items/${encodeURIComponent(m.name)}" class="comp-mat-name">${esc(m.name)}</a>
          <span class="comp-mat-count status-${status}">Need: ${m.needed} (have ${m.owned})</span>
          ${sourceHtml ? `<span class="comp-mat-bosses">${sourceHtml}</span>` : ''}
        </div>
      `;
    }).join('');

    return `
      <div class="comp-tracked-item">
        <div class="comp-item-header">
          <img src="twicons/${encodeURIComponent(itemName)}.jpg" alt="" class="comp-item-icon" onerror="this.style.display='none'">
          <h3><a href="#/items/${encodeURIComponent(itemName)}">${esc(itemName)}</a></h3>
        </div>
        <div class="comp-materials-list">${matsHtml}</div>
      </div>
    `;
  }).join('');
}

function renderCumulativeSummary() {
  if (!trackerState.trackedItems.length) return '';

  const ownedMap = buildOwnedMap(trackerState.lastSave?.inventory);
  const totals = new Map();

  for (const itemName of trackerState.trackedItems) {
    const leaves = flattenToLeaves(itemName, 1, itemMap, ownedMap);
    for (const [matName, needed] of leaves) {
      if (matName.includes('Soulstone') || matName.includes('Token') || matName === 'Prius Silver Coin' || matName === 'Prius Gold Coin') continue;
      totals.set(matName, (totals.get(matName) || 0) + needed);
    }
  }

  const items = [...totals.entries()]
    .map(([name, needed]) => ({ name, needed, owned: ownedMap.get(name) || 0 }))
    .filter(m => m.owned < m.needed);

  if (!items.length) return '<div class="cumulative-summary"><p class="cumulative-complete">All materials acquired!</p></div>';

  const iconsHtml = items.map(m => {
    const remaining = m.needed - m.owned;
    return `<a href="#/items/${encodeURIComponent(m.name)}" class="inv-icon-link" title="${esc(m.name)} — need ${remaining} more (${m.owned}/${m.needed})">
      <img src="twicons/${encodeURIComponent(m.name)}.jpg" alt="${esc(m.name)}" class="inv-icon" onerror="this.style.display='none'">
      <span class="inv-icon-qty">x${remaining}</span>
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
  const history = loadCodeHistory();
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
      ${renderUploadArea(hasSave)}
      ${renderCharacterOverview(trackerState.lastSave)}
      ${renderSearchArea()}
      <div id="trackedItemsArea">${renderTrackedList()}</div>
      ${hasSave || trackerState.trackedItems.length ? `
        ${renderViewToggle()}
        ${currentView === 'comprehensive' ? `<div id="cumulativeSummary">${renderCumulativeSummary()}</div>` : ''}
        <div id="trackerContent" class="tracker-content">${renderContent()}</div>
      ` : ''}
      ${renderLoadCodeHistory()}
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

function handleFileUpload(file) {
  const reader = new FileReader();
  reader.onload = (e) => {
    const parsed = parseSaveFile(e.target.result);
    if (!parsed) {
      alert('Could not parse save file. Please upload a valid WC3 save file.');
      return;
    }
    trackerState.lastSave = parsed;
    saveTrackerState(trackerState);

    if (parsed.loadCodes.length) {
      addCodeHistoryEntry({
        id: parsed.uploadedAt,
        username: parsed.username,
        class: parsed.class,
        level: parsed.level,
        version: parsed.version,
        codes: parsed.loadCodes,
        uploadedAt: parsed.uploadedAt,
      });
    }

    fullRerender();
    wireEvents();
  };
  reader.readAsText(file);
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
      .filter(item => !trackerState.trackedItems.includes(item.name))
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

export async function initTracker({ params, query }) {
  await loadItemData();
  await loadBossData();
  trackerState = loadTrackerState();

  const app = document.getElementById('app');
  app.innerHTML = renderPage();
  wireEvents();

  window._trackerSearchInput = handleSearch;

  window._trackerTrackItem = (name) => {
    if (!trackerState.trackedItems.includes(name)) {
      trackerState.trackedItems.push(name);
      saveTrackerState(trackerState);
      refreshTrackedList();
      refreshContent();
      const resultsEl = document.getElementById('trackerSearchResults');
      if (resultsEl) resultsEl.innerHTML = '';
      const input = document.getElementById('trackerSearchInput');
      if (input) input.value = '';
    }
  };

  window._trackerUntrackItem = (name) => {
    trackerState.trackedItems = trackerState.trackedItems.filter(n => n !== name);
    saveTrackerState(trackerState);
    refreshTrackedList();
    refreshContent();
  };

  window._trackerSetView = (view) => {
    currentView = view;
    fullRerender();
    wireEvents();
  };

  window._toggleTreeNode = (id) => {
    const children = document.querySelector(`[data-node-id="${id}"]`);
    if (children) {
      children.classList.toggle('collapsed');
      const btn = children.previousElementSibling?.querySelector('.tree-toggle');
      if (btn) btn.textContent = children.classList.contains('collapsed') ? '▶' : '▼';
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
    const history = loadCodeHistory();
    if (history[idx]) {
      navigator.clipboard.writeText(history[idx].codes.join('\n'));
    }
  };

  window._trackerDeleteSave = () => {
    trackerState.lastSave = null;
    saveTrackerState(trackerState);
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
    clearTimeout(searchTimeout);
  };
}
