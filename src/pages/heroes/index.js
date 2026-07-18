import { esc } from '../../ui/escape.js';
import { t } from '../../i18n.js';

let heroData = null;
let skillData = null;
let itemData = null;

async function loadData() {
  if (heroData && skillData) return;
  try {
    const [hr, sr, ir] = await Promise.all([
      fetch('data/heroes.json'),
      fetch('data/skills.json'),
      fetch('data/items.json'),
    ]);
    if (hr.ok) heroData = await hr.json();
    if (sr.ok) skillData = await sr.json();
    if (ir.ok) itemData = await ir.json();
  } catch (e) {}
  if (!heroData) heroData = [];
  if (!skillData) skillData = [];
  if (!itemData) itemData = [];
}

function getSpecDescription(weaponName, heroClass) {
  const item = itemData.find(i => i.name === weaponName);
  if (!item?.stats?.spec) return '';
  const specLine = item.stats.spec.find(s => s.startsWith(heroClass + ' - '));
  if (specLine) return specLine.slice(heroClass.length + 3);
  if (item.stats.spec.length > 1) return item.stats.spec[1].replace(/^[^-]+ - /, '');
  return '';
}

// ── Colors per mainstat ──────────────────────────────────────
const STAT_COLOR = {
  STR: { pill: 'hero-stat-str', hex: '#e94560' },
  AGI: { pill: 'hero-stat-agi', hex: '#4ade80' },
  INT: { pill: 'hero-stat-int', hex: '#60a5fa' },
};

const STAT_ORDER = ['STR', 'AGI', 'INT'];

function iconSrc(name) {
  return 'twicons/' + encodeURIComponent(name) + '.jpg';
}

// ── Role classification ───────────────────────────────────────
const SUPPORT_CLASSES = new Set([
  'Soul Weaver', 'Wind Mage', 'Priest', 'Merchant',
  'Elementalist', 'Dark Knight', 'Paladin', 'Hermit', 'Shooter', 'Witch',
]);
const DPS_CLASSES = new Set([
  'Sniper', 'Fire Mage', 'Lightning Mage', 'Reaper', 'Assassin',
  'Martial Artist', 'Thunderer', 'Berserker', 'Bow Master', 'Fighter',
  'Trickster', 'Lightseeker', 'Blaster', 'Sword Saint', 'Phantom Blade',
  'Swordsman', 'Gunner', 'Sword Enchanter', 'Lancer', 'Crusader',
  'Warlock', 'Dark Knight', 'Paladin', 'Knight', 'Blood Weaver',
  'Water Mage', 'Hermit', 'Shooter',
]);

function heroMatchesRole(hero, role) {
  if (!role) return true;
  if (role === 'DPS') return DPS_CLASSES.has(hero.heroClass);
  if (role === 'Support') return SUPPORT_CLASSES.has(hero.heroClass);
  return true;
}

// ── Hero list ─────────────────────────────────────────────────
function renderHeroList(heroes, query) {
  const activeStat = query.stat || '';
  const activeRole = query.role || '';

  let filtered = heroes;
  if (activeStat) filtered = filtered.filter(h => h.mainstat === activeStat);
  if (activeRole) filtered = filtered.filter(h => heroMatchesRole(h, activeRole));

  // Sort: by mainstat order, then alphabetically by name
  const sorted = [...filtered].sort((a, b) => {
    const si = STAT_ORDER.indexOf(a.mainstat) - STAT_ORDER.indexOf(b.mainstat);
    if (si !== 0) return si;
    return a.name.localeCompare(b.name);
  });

  return `
    <div class="page-header">
      <h1>Heroes</h1>
      <p class="page-subtitle">Class guides, skills, and build information</p>
    </div>

    <div class="hero-filters">
      <div class="filter-search">
        <input type="text" id="heroSearchInput" placeholder="Search heroes..." oninput="window._heroSearch(this.value)">
      </div>
      <div class="filter-pills">
        <button class="filter-pill ${!activeStat ? 'active' : ''}" onclick="window._heroFilterStat('')">All</button>
        <button class="filter-pill hero-stat-str ${activeStat === 'STR' ? 'active' : ''}" onclick="window._heroFilterStat('STR')">STR</button>
        <button class="filter-pill hero-stat-agi ${activeStat === 'AGI' ? 'active' : ''}" onclick="window._heroFilterStat('AGI')">AGI</button>
        <button class="filter-pill hero-stat-int ${activeStat === 'INT' ? 'active' : ''}" onclick="window._heroFilterStat('INT')">INT</button>
        <span class="filter-divider"></span>
        <button class="filter-pill hero-role-dps ${activeRole === 'DPS' ? 'active' : ''}" onclick="window._heroFilterRole('DPS')">DPS</button>
        <button class="filter-pill hero-role-support ${activeRole === 'Support' ? 'active' : ''}" onclick="window._heroFilterRole('Support')">Support</button>
      </div>
    </div>

    <div class="hero-grid">
      ${sorted.length === 0
        ? `<div class="hero-empty">No heroes found.</div>`
        : sorted.map(hero => renderHeroCard(hero)).join('')
      }
    </div>
  `;
}

function renderHeroCard(hero) {
  const statInfo = STAT_COLOR[hero.mainstat] || {};
  const colorHex = '#' + hero.color;
  const roles = (hero.role || []).join(', ');

  return `
    <a href="#/heroes/${esc(hero.id)}" class="hero-card" style="--hero-color: ${colorHex}">
      <div class="hero-card-icon">
        <img src="${iconSrc(hero.icon)}" alt="${esc(hero.name)}" onerror="this.style.display='none'">
      </div>
      <div class="hero-card-info">
        <h3>${esc(hero.name)}</h3>
        <span class="hero-class-name">${esc(hero.heroClass)}</span>
        <div class="hero-card-meta">
          <span class="hero-stat-badge ${statInfo.pill || ''}">${esc(hero.mainstat)}</span>
          ${roles ? `<span class="hero-role-text">${esc(roles)}</span>` : ''}
        </div>
      </div>
    </a>
  `;
}

// ── Hero detail ───────────────────────────────────────────────
function renderHeroDetail(hero, skills) {
  const heroSkills = skills
    .filter(s => s.heroClass === hero.heroClass)
    .sort((a, b) => (a.order || 0) - (b.order || 0));

  const colorHex = '#' + hero.color;
  const statInfo = STAT_COLOR[hero.mainstat] || {};
  const roles = (hero.role || []).join(' / ');
  const weaponTypes = (hero.wearable || []).filter(w => w.startsWith('Weapon'));

  return `
    <button class="back-btn" onclick="location.hash='#/heroes'">Back to Heroes</button>

    <div class="hero-detail">
      <div class="hero-detail-header" style="--hero-color: ${colorHex}">
        <div class="hero-detail-icon">
          <img src="${iconSrc(hero.icon)}" alt="${esc(hero.name)}" onerror="this.style.display='none'">
        </div>
        <div class="hero-detail-title">
          <h1>${esc(hero.name)}</h1>
          <span class="hero-detail-class">${esc(hero.heroClass)}</span>
          <div class="hero-detail-meta">
            <span class="hero-stat-badge ${statInfo.pill || ''}">${esc(hero.mainstat)}</span>
            ${roles ? `<span class="hero-role-badge">${esc(roles)}</span>` : ''}
            ${weaponTypes.map(w => `<span class="hero-weapon-badge">${esc(w)}</span>`).join('')}
          </div>
          ${hero.description?.length ? `
            <p class="hero-detail-desc">${hero.description.map(d => esc(d)).join(' ')}</p>
          ` : ''}
        </div>
      </div>


      ${hero.spec?.length && hero.spec[0] !== 'No Specs!' ? `
        <div class="hero-section">
          <h2>Specializations</h2>
          <div class="hero-spec-list">
            ${hero.spec.map(s => {
              const parts = s.split(' - ');
              const weapon = parts[0] || '';
              const ability = parts[1] || '';
              const desc = getSpecDescription(weapon, hero.heroClass);
              return `
                <div class="hero-spec-item">
                  <div class="hero-spec-header">
                    <span class="hero-spec-weapon">${esc(weapon)}</span>
                    ${ability ? `<span class="hero-spec-arrow">→</span><span class="hero-spec-ability">${esc(ability)}</span>` : ''}
                  </div>
                  ${desc ? `<p class="hero-spec-desc">${esc(desc)}</p>` : ''}
                </div>
              `;
            }).join('')}
          </div>
        </div>
      ` : ''}

      ${heroSkills.length ? `
        <div class="hero-section">
          <h2>Skills</h2>
          <div class="hero-skills-list">
            ${heroSkills.map(skill => renderSkillCard(skill)).join('')}
          </div>
        </div>
      ` : ''}
    </div>
  `;
}

function renderSkillCard(skill) {
  const skillColor = '#' + skill.color;
  const hasPassive = Array.isArray(skill.passive) && skill.passive.length > 0;
  const hasActive = Array.isArray(skill.active) && skill.active.length > 0;

  return `
    <div class="skill-card" style="--skill-color: ${skillColor}">
      <div class="skill-card-header">
        <div class="skill-icon">
          <img src="${iconSrc(skill.icon)}" alt="${esc(skill.name)}" onerror="this.style.display='none'">
        </div>
        <div class="skill-info">
          <h3 class="skill-name">${esc(skill.name)}</h3>
          <div class="skill-meta">
            <span class="skill-hotkey">${esc(skill.hotkey)}</span>
            ${skill.cooldown != null
              ? `<span class="skill-cooldown">${skill.cooldown}s CD</span>`
              : skill.proc_rate != null
                ? `<span class="skill-cooldown">${Math.round(skill.proc_rate * 100)}% Proc</span>`
                : ''
            }
          </div>
        </div>
      </div>
      <div class="skill-body">
        ${hasPassive ? `
          ${hasActive ? `<div class="skill-section-label">Passive</div>` : ''}
          <ul class="skill-desc-list">
            ${skill.passive.map((line, i) => `
              <li class="${i === 0 ? 'skill-flavor' : ''}">${esc(line)}</li>
            `).join('')}
          </ul>
        ` : ''}
        ${hasActive ? `
          ${hasPassive ? `<div class="skill-section-label">Active</div>` : ''}
          <ul class="skill-desc-list">
            ${skill.active.map((line, i) => `
              <li class="${!hasPassive && i === 0 ? 'skill-flavor' : ''}">${esc(line)}</li>
            `).join('')}
          </ul>
        ` : ''}
      </div>
    </div>
  `;
}

// ── Entry point ───────────────────────────────────────────────
export async function initHeroes({ params, query }) {
  const app = document.getElementById('app');
  await loadData();

  if (params.id) {
    const hero = heroData.find(h => h.id === params.id);
    if (hero) {
      app.innerHTML = renderHeroDetail(hero, skillData);
    } else {
      app.innerHTML = `
        <button class="back-btn" onclick="location.hash='#/heroes'">Back to Heroes</button>
        <div class="coming-soon">
          <div class="coming-soon-icon">❓</div>
          <h2>Hero Not Found</h2>
          <p>No hero exists with that ID.</p>
        </div>
      `;
    }
  } else {
    app.innerHTML = renderHeroList(heroData, query);

    window._heroFilterStat = (stat) => {
      const ps = new URLSearchParams();
      if (stat) ps.set('stat', stat);
      if (query.role) ps.set('role', query.role);
      const qs = ps.toString();
      location.hash = '#/heroes' + (qs ? '?' + qs : '');
    };
    window._heroFilterRole = (role) => {
      const ps = new URLSearchParams();
      if (query.stat) ps.set('stat', query.stat);
      if (role && role !== query.role) ps.set('role', role);
      const qs = ps.toString();
      location.hash = '#/heroes' + (qs ? '?' + qs : '');
    };

    window._heroSearch = (val) => {
      const q = val.toLowerCase();
      const cards = document.querySelectorAll('.hero-grid .hero-card');
      cards.forEach(card => {
        const name = card.querySelector('h3').textContent.toLowerCase();
        const cls = card.querySelector('.hero-class-name')?.textContent.toLowerCase() || '';
        card.style.display = !q || name.includes(q) || cls.includes(q) ? '' : 'none';
      });
    };

    return function cleanup() {
      delete window._heroFilterStat;
      delete window._heroFilterRole;
      delete window._heroSearch;
    };
  }
}
