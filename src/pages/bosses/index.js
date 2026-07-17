import { esc } from '../../ui/escape.js';
import { t } from '../../i18n.js';

let bossData = null;

async function loadBossData() {
  if (bossData) return bossData;
  try {
    const r = await fetch('data/bosses.json');
    if (r.ok) bossData = await r.json();
  } catch (e) {}
  if (!bossData) bossData = [];
  return bossData;
}

// Categories as they appear in the data
const BOSS_CATEGORIES = ['Creep', 'Field', 'Minor', 'Mid', 'High', 'Late', 'Endgame'];

// Map data category → CSS tier class suffix
const CATEGORY_CSS = {
  'Creep':   'creep',
  'Field':   'field',
  'Minor':   'minor',
  'Mid':     'mids',
  'High':    'late',
  'Late':    'tower',
  'Endgame': 'endgame',
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
  const activeCat = query.cat || '';

  const filtered = activeCat
    ? bosses.filter(b => b.category === activeCat)
    : bosses;

  return `
    <div class="page-header">
      <h1>${t('bosses.title')}</h1>
      <p class="page-subtitle">${t('bosses.subtitle')}</p>
    </div>

    <div class="boss-filters">
      <div class="filter-pills">
        <button class="filter-pill ${!activeCat ? 'active' : ''}" onclick="window._bossFilterCat('')">All</button>
        ${BOSS_CATEGORIES.map(cat => `
          <button class="filter-pill boss-tier-${categoryClass(cat)} ${activeCat === cat ? 'active' : ''}" onclick="window._bossFilterCat('${esc(cat)}')">${esc(cat)}</button>
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
                ${boss.level ? `<span class="boss-level-badge">Lv ${esc(boss.level)}</span>` : ''}
              </div>
              <div class="boss-card-badges">
                <span class="boss-tier-badge tier-${categoryClass(boss.category)}">${esc(boss.category || '')}</span>
                ${typeBadge(boss.type)}
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
  return `
    <button class="back-btn" onclick="location.hash='#/bosses'">Back to Bosses</button>
    <div class="boss-detail">
      <div class="boss-detail-header">
        <div class="boss-detail-icon">
          <img src="${esc(iconSrc(boss.name))}" alt="${esc(boss.name)}" onerror="this.style.display='none'">
        </div>
        <div class="boss-detail-title">
          <h1>${esc(boss.name)}</h1>
          <div class="boss-detail-meta">
            <span class="boss-tier-badge tier-${categoryClass(boss.category)}">${esc(boss.category || '')}</span>
            ${typeBadge(boss.type)}
            ${boss.level ? `<span class="boss-meta-item">Level ${esc(boss.level)}</span>` : ''}
            ${boss.location ? `<span class="boss-meta-item">${esc(boss.location)}</span>` : ''}
          </div>
        </div>
      </div>

      <div class="boss-section">
        <h2>Stats</h2>
        ${renderStatTable(boss.stats)}
      </div>
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
        <button class="back-btn" onclick="location.hash='#/bosses'">Back to Bosses</button>
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

    return function cleanup() {
      delete window._bossFilterCat;
    };
  }
}
