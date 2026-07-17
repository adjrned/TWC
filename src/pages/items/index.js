import { esc } from '../../ui/escape.js';
import { t } from '../../i18n.js';

let itemData = null;

// ── Tier helpers ─────────────────────────────────────────────────────────────
// Tier is determined by rank + grade together.
// Grade 0: none/Normal/Magic/Rare. Grade 1-5 (all [Epic]): Deltirama→Arcana.
const TIER_INFO = {
  none:      { key: 'none',      label: 'None',      css: '' },
  normal:    { key: 'normal',    label: 'Normal',    css: '' },
  magic:     { key: 'magic',     label: 'Magic',     css: 'rarity-magic' },
  rare:      { key: 'rare',      label: 'Rare',      css: 'rarity-rare' },
  deltirama: { key: 'deltirama', label: 'Deltirama', css: 'rarity-deltirama' },
  neptinos:  { key: 'neptinos',  label: 'Neptinos',  css: 'rarity-neptinos' },
  gnosis:    { key: 'gnosis',    label: 'Gnosis',    css: 'rarity-gnosis' },
  alteia:    { key: 'alteia',    label: 'Alteia',    css: 'rarity-alteia' },
  arcana:    { key: 'arcana',    label: 'Arcana',    css: 'rarity-arcana' },
};

const GRADE_TO_TIER = { 1: 'deltirama', 2: 'neptinos', 3: 'gnosis', 4: 'alteia', 5: 'arcana' };
const RANK_TO_TIER = { 'none': 'none', '[Normal]': 'normal', '[Magic]': 'magic', '[Rare]': 'rare' };

function rankInfo(item) {
  if (item.rank === '[Epic]' && item.grade >= 1) {
    return TIER_INFO[GRADE_TO_TIER[item.grade]] || TIER_INFO.deltirama;
  }
  return TIER_INFO[RANK_TO_TIER[item.rank]] || TIER_INFO.none;
}

// ── Type grouping ─────────────────────────────────────────────────────────────
// Collapse weapon subtypes; normalise headwear casing.
function typeGroup(type) {
  if (!type) return 'other';
  const l = type.toLowerCase();
  if (l.startsWith('weapon')) return 'weapon';
  if (l === 'armor')          return 'armor';
  if (l === 'headwear')       return 'headwear';
  if (l === 'wings')          return 'wings';
  if (l === 'accessory')      return 'accessory';
  if (l === 'material')       return 'material';
  return 'other';
}

const TYPE_FILTERS = [
  { key: '',           label: 'All'       },
  { key: 'material',   label: 'Material'  },
  { key: 'weapon',     label: 'Weapon'    },
  { key: 'headwear',   label: 'Headwear'  },
  { key: 'armor',      label: 'Armor'     },
  { key: 'wings',      label: 'Wings'     },
  { key: 'accessory',  label: 'Accessory' },
];

const RANK_FILTERS = [
  { key: '',          label: 'All',       css: '' },
  { key: 'magic',     label: 'Magic',     css: 'rarity-magic' },
  { key: 'rare',      label: 'Rare',      css: 'rarity-rare' },
  { key: 'deltirama', label: 'Deltirama', css: 'rarity-deltirama' },
  { key: 'neptinos',  label: 'Neptinos',  css: 'rarity-neptinos' },
  { key: 'gnosis',    label: 'Gnosis',    css: 'rarity-gnosis' },
  { key: 'alteia',    label: 'Alteia',    css: 'rarity-alteia' },
  { key: 'arcana',    label: 'Arcana',    css: 'rarity-arcana' },
];

// ── Data loading ──────────────────────────────────────────────────────────────
async function loadItemData() {
  if (itemData) return itemData;
  try {
    const r = await fetch('data/items.json');
    if (r.ok) itemData = await r.json();
  } catch (e) {}
  if (!itemData) itemData = [];
  return itemData;
}

function iconSrc(name) {
  return `twicons/${encodeURIComponent(name)}.jpg`;
}

// ── List view ─────────────────────────────────────────────────────────────────
function renderItemList(items, query) {
  const filterType = query.type || '';
  const filterRank = query.rank || '';
  const search     = (query.search || '').toLowerCase().trim();

  let filtered = items;
  if (filterType) filtered = filtered.filter(i => typeGroup(i.type) === filterType);
  if (filterRank) filtered = filtered.filter(i => rankInfo(i).key === filterRank);

  return `
    <div class="page-header">
      <h1>${t('items.title')}</h1>
      <p class="page-subtitle">${t('items.subtitle')}</p>
    </div>

    <div class="item-filters">
      <div class="filter-search">
        <input
          type="text"
          id="itemSearchInput"
          placeholder="${t('items.search')}"
          value="${esc(query.search || '')}"
          oninput="window._itemSearch(this.value)">
      </div>
      <div class="filter-pills">
        ${TYPE_FILTERS.map(f => `
          <button
            class="filter-pill ${filterType === f.key ? 'active' : ''}"
            onclick="window._itemFilterType('${f.key}')">
            ${f.label}
          </button>
        `).join('')}
      </div>
      <div class="filter-pills">
        ${RANK_FILTERS.map(f => `
          <button
            class="filter-pill ${f.css} ${filterRank === f.key ? 'active' : ''}"
            onclick="window._itemFilterRank('${f.key}')">
            ${f.label}
          </button>
        `).join('')}
      </div>
    </div>

    <div class="item-grid" id="itemGrid">
      ${filtered.length === 0 ? `<div class="item-empty">No items match your filters.</div>` : ''}
      ${filtered.map(item => {
        const ri      = rankInfo(item);
        const nameLow = item.name.toLowerCase();
        const koLow   = (item.koreanname || '').toLowerCase();
        const hidden  = search && !nameLow.includes(search) && !koLow.includes(search);
        return `
          <a
            href="#/items/${encodeURIComponent(item.name)}"
            class="item-card ${ri.css}"
            data-name="${esc(nameLow)}"
            data-korean="${esc(koLow)}"
            ${hidden ? 'style="display:none"' : ''}>
            <div class="item-card-icon" style="background:#${esc(item.color || '333333')}22">
              <img src="${iconSrc(item.name)}" alt="${esc(item.name)}" onerror="this.style.display='none'">
            </div>
            <div class="item-card-info">
              <span class="item-card-name">${esc(item.name)}</span>
              <span class="item-card-category">${esc(item.type)}</span>
            </div>
            ${ri.key !== 'none' ? `<span class="item-rarity-badge ${ri.css}">${ri.label}</span>` : ''}
          </a>
        `;
      }).join('')}
    </div>
  `;
}

// ── Detail view ───────────────────────────────────────────────────────────────
function renderItemDetail(item) {
  const ri = rankInfo(item);

  const requiredByHtml = (item.required_by || []).length ? `
    <div class="item-section">
      <h2>Required By</h2>
      <div class="item-recipe-list">
        ${item.required_by.map(name => {
          const target = itemData.find(i => i.name === name);
          const tri    = target ? rankInfo(target || {}) : { css: '' };
          return `
            <a href="#/items/${encodeURIComponent(name)}" class="recipe-item ${tri.css}">
              <img src="${iconSrc(name)}" alt="${esc(name)}" onerror="this.style.display='none'">
              <span>${esc(name)}</span>
            </a>
          `;
        }).join('')}
      </div>
    </div>
  ` : '';

  return `
    <button class="back-btn" onclick="history.back()">← Back</button>
    <div class="item-detail">
      <div class="item-detail-header ${ri.css}">
        <div class="item-detail-icon ${ri.css}" style="background:#${esc(item.color || '333333')}22">
          <img src="${iconSrc(item.name)}" alt="${esc(item.name)}" onerror="this.style.display='none'">
        </div>
        <div class="item-detail-title">
          <h1 class="${ri.css}">${esc(item.name)}</h1>
          ${item.koreanname ? `<p class="item-name-ko">${esc(item.koreanname)}</p>` : ''}
          <div class="item-detail-meta">
            ${ri.key !== 'none' ? `<span class="item-rarity-badge ${ri.css}">${ri.label}</span>` : ''}
            <span class="item-meta-cat">${esc(item.type)}</span>
            ${item.color ? `
              <span
                class="item-color-swatch"
                title="#${esc(item.color)}"
                style="display:inline-block;width:16px;height:16px;border-radius:4px;
                       background:#${esc(item.color)};border:1px solid rgba(255,255,255,0.18);
                       vertical-align:middle;flex-shrink:0;">
              </span>
            ` : ''}
          </div>
          ${item.description ? `<p class="item-detail-desc">${esc(item.description)}</p>` : ''}
        </div>
      </div>

      ${requiredByHtml}
    </div>
  `;
}

// ── Page entry point ──────────────────────────────────────────────────────────
export async function initItems({ params, query }) {
  const app   = document.getElementById('app');
  const items = await loadItemData();

  // Support highlight query param — treat as initial search
  if (query.highlight && !params.name) {
    query.search = query.highlight;
  }

  if (params.name) {
    const itemName = decodeURIComponent(params.name);
    const item     = items.find(i => i.name === itemName);
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

    // In-place search — no hash navigation
    window._itemSearch = (val) => {
      const q     = val.toLowerCase().trim();
      const grid  = document.getElementById('itemGrid');
      const cards = grid ? grid.querySelectorAll('.item-card') : [];
      let visible = 0;

      cards.forEach(card => {
        const name   = card.dataset.name   || '';
        const korean = card.dataset.korean || '';
        const show   = !q || name.includes(q) || korean.includes(q);
        card.style.display = show ? '' : 'none';
        if (show) visible++;
      });

      if (!grid) return;
      let empty = grid.querySelector('.item-empty');
      if (visible === 0) {
        if (!empty) {
          empty = document.createElement('div');
          empty.className = 'item-empty';
          grid.appendChild(empty);
        }
        empty.textContent = 'No items match your filters.';
        empty.style.display = '';
      } else if (empty) {
        empty.style.display = 'none';
      }
    };

    // Type / rank filters use hash navigation
    window._itemFilterType = (type) => {
      const p = new URLSearchParams();
      if (type)        p.set('type', type);
      if (query.rank)  p.set('rank', query.rank);
      const qs = p.toString();
      location.hash = '#/items' + (qs ? '?' + qs : '');
    };

    window._itemFilterRank = (rank) => {
      const p = new URLSearchParams();
      if (query.type)  p.set('type', query.type);
      if (rank)        p.set('rank', rank);
      const qs = p.toString();
      location.hash = '#/items' + (qs ? '?' + qs : '');
    };

    return function cleanup() {
      delete window._itemSearch;
      delete window._itemFilterType;
      delete window._itemFilterRank;
    };
  }
}
