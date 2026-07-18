import { esc } from '../../ui/escape.js';
import { t } from '../../i18n.js';

let awakeningData = null;
let heroData = null;

async function loadData() {
  if (awakeningData) return;
  try {
    const [ar, hr] = await Promise.all([
      fetch('data/awakenings.json'),
      fetch('data/heroes.json'),
    ]);
    if (ar.ok) awakeningData = await ar.json();
    if (hr.ok) heroData = await hr.json();
  } catch(e) {}
  if (!awakeningData) awakeningData = [];
  if (!heroData) heroData = [];
}

function getHero(heroClass) {
  return heroData.find(h => h.heroClass === heroClass);
}

function iconSrc(name) {
  return 'twicons/' + encodeURIComponent(name) + '.jpg';
}

const EFFECT_TYPE_LABELS = {
  'STR': 'STR Path',
  'AGI': 'AGI Path',
  'INT': 'INT Path',
  'Passive': 'Passive',
  'Skill': 'Skill Enhancement',
  'Active': 'Active Effect',
};

const EFFECT_TYPE_CSS = {
  'STR': 'awk-type-str',
  'AGI': 'awk-type-agi',
  'INT': 'awk-type-int',
  'Passive': 'awk-type-passive',
  'Skill': 'awk-type-skill',
  'Active': 'awk-type-active',
};

function renderAwakeningList() {
  const totalHeroes = heroData.length;
  const awakened = awakeningData.length;

  return `
    <div class="page-header">
      <h1>Awakening</h1>
      <p class="page-subtitle">Upgraded abilities and new effects</p>
    </div>

    <p class="awk-progress">${awakened} / ${totalHeroes} heroes have awakening data</p>

    <div class="awk-grid">
      ${awakeningData.map(awk => {
        const hero = getHero(awk.heroClass);
        const colorHex = hero ? '#' + hero.color : '#666';
        return `
          <div class="awk-card" style="--awk-color: ${colorHex}">
            <div class="awk-card-header">
              ${hero ? `<div class="awk-card-icon"><img src="${iconSrc(hero.icon)}" alt="${esc(awk.heroClass)}" onerror="this.style.display='none'"></div>` : ''}
              <div class="awk-card-title">
                <h3>${esc(awk.heroClass)}</h3>
                <div class="awk-card-skill">
                  <span class="awk-original">${esc(awk.original)}</span>
                  <span class="awk-arrow">→</span>
                  <span class="awk-awakened">${esc(awk.awakened)}</span>
                </div>
              </div>
            </div>
            <div class="awk-card-effects">
              ${awk.effects.map(effect => `
                <div class="awk-effect">
                  <span class="awk-effect-type ${EFFECT_TYPE_CSS[effect.type] || ''}">${esc(EFFECT_TYPE_LABELS[effect.type] || effect.type)}</span>
                  <p class="awk-effect-desc">${esc(effect.description)}</p>
                </div>
              `).join('')}
            </div>
          </div>
        `;
      }).join('')}
    </div>
  `;
}

export async function initAwakening({ params, query }) {
  const app = document.getElementById('app');
  await loadData();
  app.innerHTML = renderAwakeningList();
}
