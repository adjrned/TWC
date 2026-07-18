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
  const activeCat = 'cat' in query ? query.cat : 'Endgame';

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
          <a href="#/bosses/${boss.id}" class="boss-card" data-category="${esc(boss.category || '')}">
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

// ── Drop rate calculator ──────────────────────────────────────────────────────
let bossDropData = null;

async function loadBossDropData() {
  if (bossDropData) return;
  try {
    const r = await fetch('data/boss-drops.json');
    if (r.ok) bossDropData = await r.json();
  } catch(e) {}
  if (!bossDropData) bossDropData = {};
}

const NO_WISH_BOSSES = new Set(['Styrix, the Harvester of Souls', 'Lightbringer Kamael']);

const PLAYER_BONUS = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 47.5];

// Boss-specific player scaling rules
const BOSS_PLAYER_RULES = {
  'Styrix, the Harvester of Souls': { min: 5, max: 10, perPlayer: 5 },
  'Lightbringer Kamael': { min: 5, max: 10, perPlayer: 5 },
  'Arcane Construct': { min: 3, max: 6, perPlayer: 10 },
};
const DEFAULT_PLAYER_RULES = { min: 1, max: 10, perPlayer: 5, bonusStart: 3 };

function getPlayerBonus(playerCount, bossName) {
  const rules = BOSS_PLAYER_RULES[bossName];
  if (rules) {
    const effectivePlayers = Math.max(0, playerCount - rules.min);
    return effectivePlayers * rules.perPlayer;
  }
  // Default: bonus starts at 3 players, +5% per player from 3 onwards
  const effectivePlayers = Math.max(0, playerCount - 2);
  return effectivePlayers * 5;
}

function calcDropRate(item, { wishing, hasIcon, seasonal, playerCount }, bossName) {
  const playerPct = getPlayerBonus(playerCount, bossName);
  const seasonalMult = seasonal ? 2 : 1;
  const combined = (1 + playerPct / 100) * seasonalMult;

  let wishMult = 1;
  if (!NO_WISH_BOSSES.has(bossName)) {
    if (wishing && hasIcon) wishMult = item.wishIconMult;
    else if (wishing) wishMult = item.wishMult;
    else if (hasIcon) wishMult = item.iconMult;
  }

  return item.base * combined * wishMult;
}

function renderDropCalculator(boss) {
  const dropInfo = bossDropData?.[boss.name];
  if (!dropInfo) return '';

  const isNoWish = NO_WISH_BOSSES.has(boss.name);
  const iconLabel = dropInfo.iconType === 'Immortal' ? 'Immortal' : 'Legend';
  const rules = BOSS_PLAYER_RULES[boss.name] || DEFAULT_PLAYER_RULES;

  return `
    <div class="boss-section">
      <h2>Drop Rates</h2>
      <div class="drop-calc-layout">
        <div class="drop-calc-controls">
          ${!isNoWish ? `
            <label class="drop-calc-toggle"><input type="checkbox" id="calcWish"><span>${dropInfo.iconType === 'Immortal' ? 'Target Item' : 'Wishing'}</span></label>
            <label class="drop-calc-toggle"><input type="checkbox" id="calcIcon"><span>${iconLabel} Icon (+50%)</span></label>
          ` : ''}
          <label class="drop-calc-toggle"><input type="checkbox" id="calcSeasonal"><span>Seasonal (×2)</span></label>
          <div class="drop-calc-player">
            <span>Party Size</span>
            <div class="drop-calc-slider-row">
              <input type="range" id="calcPlayers" min="${rules.min}" max="${rules.max}" value="${rules.min}">
              <span id="calcPlayersVal">${rules.min}</span>
            </div>
          </div>
        </div>
      <div class="boss-drops-list" id="dropCalcList">
        ${dropInfo.items.map((item, i) => {
          const defaultRate = item.base; // base rate at min players (no bonus)
          return `
          <a href="#/items/${encodeURIComponent(item.name)}" class="boss-drop-item" data-idx="${i}">
            <div class="boss-drop-icon">
              <img src="twicons/${encodeURIComponent(item.name)}.jpg" alt="${esc(item.name)}" onerror="this.style.display='none'">
            </div>
            <span class="boss-drop-name">${esc(item.name)}</span>
            <span class="boss-drop-rate" data-idx="${i}">${defaultRate.toFixed(4)}%</span>
          </a>
        `;}).join('')}
      </div>
      </div>
    </div>
  `;
}

function initDropCalc(boss) {
  const dropInfo = bossDropData?.[boss.name];
  if (!dropInfo) return;

  const isNoWish = NO_WISH_BOSSES.has(boss.name);
  const update = () => {
    const wishing = !isNoWish && document.getElementById('calcWish')?.checked;
    const hasIcon = !isNoWish && document.getElementById('calcIcon')?.checked;
    const seasonal = document.getElementById('calcSeasonal')?.checked;
    const playerCount = parseInt(document.getElementById('calcPlayers')?.value || '1');
    document.getElementById('calcPlayersVal').textContent = playerCount;

    const rates = document.querySelectorAll('#dropCalcList .boss-drop-rate');
    rates.forEach(el => {
      const idx = parseInt(el.dataset.idx);
      const item = dropInfo.items[idx];
      if (!item) return;
      const calc = calcDropRate(item, { wishing, hasIcon, seasonal, playerCount }, boss.name);
      el.textContent = calc.toFixed(4) + '%';
    });
  };

  ['calcWish', 'calcIcon', 'calcSeasonal', 'calcPlayers'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.addEventListener('input', update);
  });
}

// ── Detail view ───────────────────────────────────────────────────────────────
function renderBossDetail(boss) {
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

      ${renderDropCalculator(boss)}

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
  await loadBossDropData();

  if (params.id) {
    const boss = bosses.find(b => b.id === params.id);
    if (boss) {
      app.innerHTML = renderBossDetail(boss);
      initDropCalc(boss);
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
