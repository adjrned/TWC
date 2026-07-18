import { esc } from '../../ui/escape.js';
import { t } from '../../i18n.js';

let bossData = null;
let itemData = null;

async function loadBossData() {
  if (bossData) return bossData;
  try {
    const [br, ir] = await Promise.all([
      fetch('data/bosses.json'),
      fetch('data/items.json'),
    ]);
    if (br.ok) bossData = await br.json();
    if (ir.ok) itemData = await ir.json();
  } catch (e) {}
  if (!bossData) bossData = [];
  if (!itemData) itemData = [];
  return bossData;
}

function getDropsForBoss(bossName) {
  if (!itemData) return [];
  return itemData.filter(i => (i.dropped_by || []).includes(bossName));
}

// Categories as they appear in the data
const BOSS_CATEGORIES = ['Creep', 'Field', 'Minor', 'Coins', 'High', 'Late', 'Endgame'];

// Display labels using rarity tier names
const CATEGORY_LABELS = {
  'Creep':   'Creep',
  'Field':   'Field',
  'Minor':   'Deltirama',
  'Coins':   'Neptinos',
  'High':    'Gnosis',
  'Late':    'Alteia',
  'Endgame': 'Arcana',
};

// Map data category → CSS rarity class
const CATEGORY_CSS = {
  'Creep':   'creep',
  'Field':   'field',
  'Minor':   'deltirama',
  'Coins':   'neptinos',
  'High':    'gnosis',
  'Late':    'alteia',
  'Endgame': 'arcana',
};

function categoryClass(cat) {
  return CATEGORY_CSS[cat] || 'minor';
}

function iconSrc(name) {
  return `twicons/${encodeURIComponent(name + ' Icon')}.jpg`;
}

// ── Stat label mapping ────────────────────────────────────────────────────────
const STAT_LABELS = {
  health:       'Health',
  healthRegen:  'HP Regen',
  mana:         'Mana',
  manaRegen:    'Mana Regen',
  armor:        'Armor',
  armorType:    'Armor Type',
  magicResist:  'Magic Resist',
  damageResist: 'Damage Resist',
  attackDamage: 'Attack Damage',
  attackSpread: 'Attack Spread',
  attackRange:  'Attack Range',
  attackSpeed:  'Attack Speed',
  moveSpeed:    'Move Speed',
};

function renderStatTable(stats) {
  if (!stats) return '';
  const rows = Object.entries(stats)
    .filter(([, v]) => v !== '' && v !== null && v !== undefined)
    .map(([k, v]) => {
      const label = STAT_LABELS[k] || k;
      return `
        <tr class="stat-row">
          <td class="stat-label">${esc(label)}</td>
          <td class="stat-value">${esc(String(v))}</td>
        </tr>`;
    }).join('');
  return `
    <table class="boss-stats-table">
      <tbody>${rows}</tbody>
    </table>`;
}

// ── Type badge ────────────────────────────────────────────────────────────────
function typeBadge(type) {
  const cls = type ? 'boss-type-badge type-' + type.toLowerCase() : 'boss-type-badge';
  return `<span class="${esc(cls)}">${esc(type || '')}</span>`;
}

// ── List view ─────────────────────────────────────────────────────────────────
function renderBossList(bosses, query) {
  const activeCat = query.cat !== undefined ? query.cat : 'Endgame';

  const filtered = activeCat
    ? bosses.filter(b => b.category === activeCat)
    : bosses;

  return `
    <div class="page-header">
      <h1>${t('bosses.title')}</h1>
      <p class="page-subtitle">${t('bosses.subtitle')}</p>
    </div>

    <div class="boss-filters">
      <div class="filter-search">
        <input type="text" id="bossSearchInput" placeholder="Search bosses..." oninput="window._bossSearch(this.value)">
      </div>
      <div class="filter-pills">
        <button class="filter-pill ${!activeCat ? 'active' : ''}" onclick="window._bossFilterCat('')">All</button>
        ${BOSS_CATEGORIES.map(cat => `
          <button class="filter-pill rarity-${categoryClass(cat)} ${activeCat === cat ? 'active' : ''}" onclick="window._bossFilterCat('${esc(cat)}')">${esc(CATEGORY_LABELS[cat] || cat)}</button>
        `).join('')}
      </div>
    </div>

    <div class="boss-grid">
      ${filtered.length === 0
        ? `<div class="boss-empty">No entities in this category.</div>`
        : filtered.map(boss => `
          <a href="#/bosses/${esc(boss.id)}" class="boss-card" data-category="${esc(boss.category || '')}">
            <div class="boss-card-icon">
              <img src="${esc(iconSrc(boss.name))}" alt="${esc(boss.name)}" onerror="this.style.display='none'">
            </div>
            <div class="boss-card-info">
              <div class="boss-card-name-row">
                <h3>${esc(boss.name)}</h3>
              </div>
              <div class="boss-card-badges">
                <span class="boss-tier-badge tier-${categoryClass(boss.category)}">${esc(CATEGORY_LABELS[boss.category] || boss.category || '')}</span>
                ${typeBadge(boss.type)}
                ${boss.level ? `<span class="boss-level-badge">Lv ${esc(boss.level)}</span>` : ''}
              </div>
              ${boss.location ? `<div class="boss-card-location">${esc(boss.location)}</div>` : ''}
            </div>
          </a>
        `).join('')}
    </div>
  `;
}

// ── Detail view ───────────────────────────────────────────────────────────────
function renderBossDetail(boss) {
  const drops = getDropsForBoss(boss.name);

  let dropsHtml = '';
  if (drops.length) {
    dropsHtml = `
      <div class="boss-section">
        <h2>Drops</h2>
        <div class="boss-drops-list">
          ${drops.map(item => {
            const rate = item.droprate ? (item.droprate * 100) + '%' : '';
            return `
              <a href="#/items/${encodeURIComponent(item.name)}" class="boss-drop-item">
                <div class="boss-drop-icon">
                  <img src="twicons/${encodeURIComponent(item.name)}.jpg" alt="${esc(item.name)}" onerror="this.style.display='none'">
                </div>
                <span class="boss-drop-name">${esc(item.name)}</span>
                <span class="boss-drop-type">${esc(item.type || '')}</span>
                ${rate ? `<span class="boss-drop-rate">${rate}</span>` : ''}
              </a>
            `;
          }).join('')}
        </div>
      </div>
    `;
  }

  return `
    <button class="back-btn" onclick="history.back()">Back</button>
    <div class="boss-detail">
      <div class="boss-detail-header">
        <div class="boss-detail-icon">
          <img src="${esc(iconSrc(boss.name))}" alt="${esc(boss.name)}" onerror="this.style.display='none'">
        </div>
        <div class="boss-detail-title">
          <h1>${esc(boss.name)}</h1>
          <div class="boss-detail-meta">
            <span class="boss-tier-badge tier-${categoryClass(boss.category)}">${esc(CATEGORY_LABELS[boss.category] || boss.category || '')}</span>
            ${typeBadge(boss.type)}
            ${boss.level ? `<span class="boss-meta-item">Level ${esc(boss.level)}</span>` : ''}
            ${boss.location ? `<span class="boss-meta-item">${esc(boss.location)}</span>` : ''}
          </div>
        </div>
      </div>

      ${dropsHtml}

      ${boss.stats && Object.keys(boss.stats).length ? `
        <div class="boss-section">
          <h2>Stats</h2>
          ${renderStatTable(boss.stats)}
        </div>
      ` : ''}
    </div>
  `;
}

// ── Entry point ───────────────────────────────────────────────────────────────
export async function initBosses({ params, query }) {
  const app = document.getElementById('app');
  const bosses = await loadBossData();

  if (params.id) {
    const boss = bosses.find(b => b.id === params.id);
    if (boss) {
      app.innerHTML = renderBossDetail(boss);
    } else {
      app.innerHTML = `
        <button class="back-btn" onclick="history.back()">Back</button>
        <div class="coming-soon">
          <div class="coming-soon-icon">?</div>
          <h2>Not Found</h2>
          <p>No entry exists for this ID.</p>
        </div>
      `;
    }
  } else {
    app.innerHTML = renderBossList(bosses, query);

    window._bossFilterCat = (cat) => {
      const ps = new URLSearchParams();
      if (cat) ps.set('cat', cat);
      const qs = ps.toString();
      location.hash = '#/bosses' + (qs ? '?' + qs : '');
    };

    window._bossSearch = (val) => {
      const q = val.toLowerCase();
      const cards = document.querySelectorAll('.boss-grid .boss-card');
      cards.forEach(card => {
        const name = card.querySelector('.boss-card-name-row h3').textContent.toLowerCase();
        card.style.display = !q || name.includes(q) ? '' : 'none';
      });
    };

    return function cleanup() {
      delete window._bossFilterCat;
      delete window._bossSearch;
    };
  }
}
