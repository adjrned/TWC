import { esc } from '../../ui/escape.js';
import { navigate } from '../../router.js';
import { t } from '../../i18n.js';

let bossData = null;

async function loadBossData() {
  if (bossData) return bossData;
  try {
    const r = await fetch('data/bosses.json');
    if (r.ok) bossData = await r.json();
  } catch(e) {}
  if (!bossData) bossData = [];
  return bossData;
}

const BOSS_CATEGORIES = ['Minor', 'Coins', 'Mids', 'Late', 'Tower', 'End-game'];

function renderBossList(bosses, query) {
  const activeCat = query.tier || '';

  const filtered = activeCat
    ? bosses.filter(b => b.tier === activeCat)
    : bosses;

  return `
    <div class="page-header">
      <h1>${t('bosses.title')}</h1>
      <p class="page-subtitle">${t('bosses.subtitle')}</p>
    </div>

    <div class="boss-filters">
      <div class="filter-pills">
        <button class="filter-pill ${!activeCat ? 'active' : ''}" onclick="window._bossFilterTier('')">All</button>
        ${BOSS_CATEGORIES.map(cat => `
          <button class="filter-pill boss-tier-${cat.toLowerCase().replace('-', '')} ${activeCat === cat ? 'active' : ''}" onclick="window._bossFilterTier('${cat}')">${esc(cat)}</button>
        `).join('')}
      </div>
    </div>

    <div class="boss-grid">
      ${filtered.length === 0 ? `<div class="boss-empty">No bosses in this category yet.</div>` : ''}
      ${filtered.map(boss => `
        <a href="#/bosses/${boss.id}" class="boss-card" data-tier="${boss.tier}">
          <div class="boss-card-icon">
            <img src="${boss.iconSrc}" alt="${esc(boss.name)}" onerror="this.style.display='none'">
          </div>
          <div class="boss-card-info">
            <h3>${esc(boss.name)}</h3>
            <span class="boss-tier-badge tier-${boss.tier.toLowerCase().replace('-', '')}">${esc(boss.tier)}</span>
          </div>
        </a>
      `).join('')}
    </div>
  `;
}

function renderBossDetail(boss) {
  return `
    <button class="back-btn" onclick="location.hash='#/bosses'">← Back to Bosses</button>
    <div class="boss-detail">
      <div class="boss-detail-header">
        <div class="boss-detail-icon">
          <img src="${boss.iconSrc}" alt="${esc(boss.name)}" onerror="this.style.display='none'">
        </div>
        <div class="boss-detail-title">
          <h1>${esc(boss.name)}</h1>
          <div class="boss-detail-meta">
            <span class="boss-tier-badge">${esc(boss.tier)}</span>
            <span class="boss-meta-item">📍 ${esc(boss.location)}</span>
            <span class="boss-meta-item">❤️ ${esc(boss.hp)} HP</span>
          </div>
          <p class="boss-detail-desc">${esc(boss.description)}</p>
        </div>
      </div>

      <div class="boss-section">
        <h2>Strategy</h2>
        <p class="boss-strategy-text">${esc(boss.strategy)}</p>
      </div>

      <div class="boss-section">
        <h2>Phases</h2>
        <div class="boss-phases">
          ${boss.phases.map((phase, i) => `
            <div class="boss-phase">
              <div class="phase-indicator">
                <span class="phase-number">${i + 1}</span>
                <span class="phase-hp">${esc(phase.hp)}</span>
              </div>
              <div class="phase-content">
                <h3>${esc(phase.name)}</h3>
                <p>${esc(phase.notes)}</p>
              </div>
            </div>
          `).join('')}
        </div>
      </div>

      <div class="boss-section">
        <h2>Drop Table</h2>
        <div class="boss-drops-table">
          ${boss.drops.map(drop => `
            <a href="#/items/${encodeURIComponent(drop.itemName)}" class="drop-row">
              <span class="drop-item-name">${esc(drop.itemName)}</span>
              <span class="drop-slot-badge">${esc(drop.slot)}</span>
              <span class="drop-rate">${esc(drop.dropRate)}</span>
            </a>
          `).join('')}
        </div>
      </div>

      ${boss.recommendedClasses?.length ? `
        <div class="boss-section">
          <h2>Recommended Classes</h2>
          <div class="boss-classes">
            ${boss.recommendedClasses.map(cls => `
              <a href="#/?class=${encodeURIComponent(cls)}" class="class-badge">${esc(cls)}</a>
            `).join('')}
          </div>
        </div>
      ` : ''}
    </div>
  `;
}

export async function initBosses({ params, query }) {
  const app = document.getElementById('app');
  const bosses = await loadBossData();

  if (params.id) {
    const boss = bosses.find(b => b.id === params.id);
    if (boss) {
      app.innerHTML = renderBossDetail(boss);
    } else {
      app.innerHTML = `
        <button class="back-btn" onclick="location.hash='#/bosses'">← Back to Bosses</button>
        <div class="coming-soon">
          <div class="coming-soon-icon">❓</div>
          <h2>Boss Not Found</h2>
          <p>No guide exists for this boss yet.</p>
        </div>
      `;
    }
  } else {
    app.innerHTML = renderBossList(bosses, query);

    window._bossFilterTier = (tier) => {
      const params = new URLSearchParams();
      if (tier) params.set('tier', tier);
      const qs = params.toString();
      location.hash = '#/bosses' + (qs ? '?' + qs : '');
    };

    return function cleanup() {
      delete window._bossFilterTier;
    };
  }
}
