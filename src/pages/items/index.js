import { esc } from '../../ui/escape.js';
import { t, getItemName } from '../../i18n.js';

let itemData = null;
let bossData = null;
let craftsInto = {};

async function loadItemData() {
  if (itemData) return itemData;
  try {
    const r = await fetch('data/items.json');
    if (r.ok) itemData = await r.json();
  } catch(e) {}
  if (!itemData) itemData = [];
  try {
    const r = await fetch('data/bosses.json');
    if (r.ok) bossData = await r.json();
  } catch(e) {}
  if (!bossData) bossData = [];
  buildCraftsIntoIndex();
  return itemData;
}

function getBossName(bossId) {
  const boss = bossData?.find(b => b.id === bossId);
  return boss ? boss.name : bossId;
}

function buildCraftsIntoIndex() {
  craftsInto = {};
  itemData.forEach(item => {
    (item.recipe || []).forEach(mat => {
      (craftsInto[mat.itemName] ??= []).push(item.name);
    });
  });
}

function rarityClass(rarity) {
  return 'rarity-' + (rarity || 'common').toLowerCase();
}

function renderItemList(items, query) {
  const filterSlot = query.slot || '';
  const filterRarity = query.rarity || '';
  const search = (query.search || '').toLowerCase();

  let filtered = items;
  if (filterSlot) filtered = filtered.filter(i => i.slot === filterSlot);
  if (filterRarity) filtered = filtered.filter(i => (i.rarity || '').toLowerCase() === filterRarity.toLowerCase());
  if (search) filtered = filtered.filter(i => i.name.toLowerCase().includes(search));

  return `
    <div class="page-header">
      <h1>${t('items.title')}</h1>
      <p class="page-subtitle">${t('items.subtitle')}</p>
    </div>

    <div class="item-filters">
      <div class="filter-search">
        <input type="text" id="itemSearchInput" placeholder="Search items..." value="${esc(query.search || '')}" oninput="window._itemSearch(this.value)">
      </div>
      <div class="filter-pills">
        <button class="filter-pill ${!filterSlot ? 'active' : ''}" onclick="window._itemFilterSlot('')">All</button>
        <button class="filter-pill ${filterSlot === 'weapon' ? 'active' : ''}" onclick="window._itemFilterSlot('weapon')">⚔️ Weapon</button>
        <button class="filter-pill ${filterSlot === 'helm' ? 'active' : ''}" onclick="window._itemFilterSlot('helm')">⛑️ Helm</button>
        <button class="filter-pill ${filterSlot === 'body' ? 'active' : ''}" onclick="window._itemFilterSlot('body')">🥋 Body</button>
        <button class="filter-pill ${filterSlot === 'wings' ? 'active' : ''}" onclick="window._itemFilterSlot('wings')">🪽 Wings</button>
        <button class="filter-pill ${filterSlot === 'accessory' ? 'active' : ''}" onclick="window._itemFilterSlot('accessory')">💍 Accessory</button>
      </div>
      <div class="filter-pills">
        <button class="filter-pill ${!filterRarity ? 'active' : ''}" onclick="window._itemFilterRarity('')">All</button>
        <button class="filter-pill rarity-legendary ${filterRarity === 'legendary' ? 'active' : ''}" onclick="window._itemFilterRarity('legendary')">Legendary</button>
        <button class="filter-pill rarity-epic ${filterRarity === 'epic' ? 'active' : ''}" onclick="window._itemFilterRarity('epic')">Epic</button>
        <button class="filter-pill rarity-rare ${filterRarity === 'rare' ? 'active' : ''}" onclick="window._itemFilterRarity('rare')">Rare</button>
        <button class="filter-pill rarity-uncommon ${filterRarity === 'uncommon' ? 'active' : ''}" onclick="window._itemFilterRarity('uncommon')">Uncommon</button>
      </div>
    </div>

    <div class="item-grid">
      ${filtered.length === 0 ? `<div class="item-empty">No items match your filters.</div>` : ''}
      ${filtered.map(item => `
        <a href="#/items/${encodeURIComponent(item.name)}" class="item-card ${rarityClass(item.rarity)}">
          <div class="item-card-icon">
            <img src="${item.iconSrc}" alt="${esc(item.name)}" onerror="this.style.display='none'">
          </div>
          <div class="item-card-info">
            <span class="item-card-name">${esc(item.name)}</span>
            <span class="item-card-category">${esc(item.category)}</span>
          </div>
          <span class="item-rarity-badge ${rarityClass(item.rarity)}">${esc(item.rarity || 'Common')}</span>
        </a>
      `).join('')}
    </div>
  `;
}

function renderItemDetail(item) {
  const craftsIntoList = craftsInto[item.name] || [];

  return `
    <button class="back-btn" onclick="history.back()">← Back</button>
    <div class="item-detail ${rarityClass(item.rarity)}">
      <div class="item-detail-header">
        <div class="item-detail-icon ${rarityClass(item.rarity)}">
          <img src="${item.iconSrc}" alt="${esc(item.name)}" onerror="this.style.display='none'">
        </div>
        <div class="item-detail-title">
          <h1 class="${rarityClass(item.rarity)}">${esc(item.name)}</h1>
          ${item.nameKo ? `<p class="item-name-ko">${esc(item.nameKo)}</p>` : ''}
          <div class="item-detail-meta">
            <span class="item-rarity-badge ${rarityClass(item.rarity)}">${esc(item.rarity || 'Common')}</span>
            <span class="item-meta-cat">${esc(item.category)}</span>
            <span class="item-meta-slot">${esc(item.slot)}</span>
          </div>
          ${item.description ? `<p class="item-detail-desc">${esc(item.description)}</p>` : ''}
        </div>
      </div>

      ${item.stats?.length ? `
        <div class="item-section">
          <h2>Stats</h2>
          <ul class="item-stats">
            ${item.stats.map(s => `<li>∴ ${esc(s)}</li>`).join('')}
          </ul>
        </div>
      ` : ''}

      ${item.passive?.length ? `
        <div class="item-section">
          <h2>Passive</h2>
          <ul class="item-effects">
            ${item.passive.map(p => `<li>⁘ ${esc(p)}</li>`).join('')}
          </ul>
        </div>
      ` : ''}

      ${item.active ? `
        <div class="item-section">
          <h2>Active — ${esc(item.active.name)}</h2>
          <ul class="item-effects item-active-effects">
            ${item.active.effects.map(e => `<li>❖ ${esc(e)}</li>`).join('')}
          </ul>
          <p class="item-cooldown">Cooldown: ${item.active.cooldown}s</p>
        </div>
      ` : ''}

      ${item.recipe?.length ? `
        <div class="item-section">
          <h2>Recipe</h2>
          <div class="item-recipe-list">
            ${item.recipe.map(mat => {
              const matItem = itemData.find(i => i.name === mat.itemName);
              return `
                <a href="#/items/${encodeURIComponent(mat.itemName)}" class="recipe-item ${matItem ? rarityClass(matItem.rarity) : ''}">
                  ${matItem?.iconSrc ? `<img src="${matItem.iconSrc}" alt="${esc(mat.itemName)}" onerror="this.style.display='none'">` : ''}
                  <span>${esc(mat.itemName)}</span>
                </a>
              `;
            }).join('')}
          </div>
        </div>
      ` : ''}

      ${craftsIntoList.length ? `
        <div class="item-section">
          <h2>Crafts Into</h2>
          <div class="item-recipe-list">
            ${craftsIntoList.map(name => {
              const target = itemData.find(i => i.name === name);
              return `
                <a href="#/items/${encodeURIComponent(name)}" class="recipe-item ${target ? rarityClass(target.rarity) : ''}">
                  ${target?.iconSrc ? `<img src="${target.iconSrc}" alt="${esc(name)}" onerror="this.style.display='none'">` : ''}
                  <span>${esc(name)}</span>
                </a>
              `;
            }).join('')}
          </div>
        </div>
      ` : ''}

      ${item.dropSources?.length ? `
        <div class="item-section">
          <h2>Drop Sources</h2>
          <div class="item-drop-sources">
            ${item.dropSources.map(ds => `
              <a href="#/bosses/${ds.bossId}" class="drop-source-row">
                <span class="drop-source-boss">${esc(getBossName(ds.bossId))}</span>
                <span class="drop-rate">${esc(ds.dropRate)}</span>
              </a>
            `).join('')}
          </div>
        </div>
      ` : ''}
    </div>
  `;
}

export async function initItems({ params, query }) {
  const app = document.getElementById('app');
  const items = await loadItemData();

  // Support highlight query param — treat as search
  if (query.highlight && !params.name) {
    query.search = query.highlight;
  }

  if (params.name) {
    const itemName = decodeURIComponent(params.name);
    const item = items.find(i => i.name === itemName);
    if (item) {
      app.innerHTML = renderItemDetail(item);
    } else {
      app.innerHTML = `
        <button class="back-btn" onclick="history.back()">← Back</button>
        <div class="coming-soon">
          <div class="coming-soon-icon">❓</div>
          <h2>Item Not Found</h2>
          <p>"${esc(itemName)}" is not in the database yet.</p>
        </div>
      `;
    }
  } else {
    app.innerHTML = renderItemList(items, query);

    // Wire up filter handlers
    window._itemSearch = (val) => {
      const params = new URLSearchParams();
      if (query.slot) params.set('slot', query.slot);
      if (query.rarity) params.set('rarity', query.rarity);
      if (val) params.set('search', val);
      const qs = params.toString();
      location.hash = '#/items' + (qs ? '?' + qs : '');
    };
    window._itemFilterSlot = (slot) => {
      const params = new URLSearchParams();
      if (slot) params.set('slot', slot);
      if (query.rarity) params.set('rarity', query.rarity);
      if (query.search) params.set('search', query.search);
      const qs = params.toString();
      location.hash = '#/items' + (qs ? '?' + qs : '');
    };
    window._itemFilterRarity = (rarity) => {
      const params = new URLSearchParams();
      if (query.slot) params.set('slot', query.slot);
      if (rarity) params.set('rarity', rarity);
      if (query.search) params.set('search', query.search);
      const qs = params.toString();
      location.hash = '#/items' + (qs ? '?' + qs : '');
    };

    return function cleanup() {
      delete window._itemSearch;
      delete window._itemFilterSlot;
      delete window._itemFilterRarity;
    };
  }
}
