import { esc } from '../../ui/escape.js';
import { iconLibrary, loadIconLibrary } from '../../data/icons.js';

let patchData = null;
let itemNames = null;
let bossNames = null;
let heroClasses = null;

async function loadData() {
  if (patchData) return;
  try {
    const [patchRes, itemsRes, bossesRes, heroesRes] = await Promise.all([
      fetch('data/patch-notes.json'),
      fetch('data/items.json'),
      fetch('data/bosses.json'),
      fetch('data/heroes.json'),
    ]);
    if (patchRes.ok) patchData = await patchRes.json();
    if (itemsRes.ok) itemNames = new Set((await itemsRes.json()).map(i => i.name));
    if (bossesRes.ok) bossNames = new Set((await bossesRes.json()).map(b => b.name));
    if (heroesRes.ok) heroClasses = new Set((await heroesRes.json()).map(h => h.heroClass));
  } catch(e) {}
  if (!patchData) patchData = [];
  if (!itemNames) itemNames = new Set();
  if (!bossNames) bossNames = new Set();
  if (!heroClasses) heroClasses = new Set();
  await loadIconLibrary();
}

const HERO_ALIASES = {
  'Mage (Fire)': 'Fire Mage',
  'Mage (Water)': 'Water Mage',
  'Mage (Arcane)': 'Arcane Mage',
  'Mage (Lightning)': 'Lightning Mage',
  'Mage (Wind)': 'Wind Mage',
};

const BOSS_ALIASES = {
  'Kamael, the Lightbringer': 'Lightbringer Kamael',
  'Styrix, the Harvester of Souls': 'Styrix, the Harvester of Souls',
  'Gaia, the Earth Goddess': 'Gaia, the Earth Goddess',
};

function toCamelCase(name) {
  return name.replace(/\s+/g, '');
}

function iconExists(name) {
  return iconLibrary.some(i => i.name === name);
}

function iconSrc(name) {
  return 'twicons/' + encodeURIComponent(name) + '.jpg';
}

function getSubsectionIcon(name, sectionTitle) {
  const resolved = HERO_ALIASES[name] || name;

  if (sectionTitle === 'Characters' || heroClasses.has(resolved)) {
    const camel = toCamelCase(resolved) + 'Icon';
    if (iconExists(camel)) return iconSrc(camel);
  }

  if (sectionTitle === 'Items' || itemNames.has(name)) {
    if (iconExists(name)) return iconSrc(name);
  }

  if (sectionTitle === 'Monsters' || bossNames.has(name)) {
    const bossResolved = BOSS_ALIASES[name] || name;
    const bossIcon = bossResolved + ' Icon';
    if (iconExists(bossIcon)) return iconSrc(bossIcon);
  }

  const camel = toCamelCase(resolved) + 'Icon';
  if (iconExists(camel)) return iconSrc(camel);
  if (iconExists(name)) return iconSrc(name);
  if (iconExists(name + ' Icon')) return iconSrc(name + ' Icon');

  return null;
}

function renderSection(section) {
  let html = `<div class="patch-section">`;
  html += `<h3 class="patch-section-title">${esc(section.title)}</h3>`;

  if (section.entries) {
    html += `<ul class="patch-entries">`;
    for (const entry of section.entries) {
      html += `<li>${esc(entry)}</li>`;
    }
    html += `</ul>`;
  }

  if (section.subsections) {
    for (const sub of section.subsections) {
      const icon = getSubsectionIcon(sub.name, section.title);
      html += `<div class="patch-subsection">`;
      html += `<h4 class="patch-subsection-name">`;
      if (icon) html += `<img class="patch-icon" src="${icon}" alt="" onerror="this.style.display='none'">`;
      html += `${esc(sub.name)}</h4>`;
      html += `<ul class="patch-entries">`;
      for (const entry of sub.entries) {
        html += `<li>${esc(entry)}</li>`;
      }
      html += `</ul>`;
      html += `</div>`;
    }
  }

  html += `</div>`;
  return html;
}

function renderPatchNotes() {
  return `
    <div class="page-header">
      <h1>Patch Notes</h1>
      <p class="page-subtitle">Game balance changes and bug fixes</p>
    </div>

    <div class="patch-notes-list">
      ${patchData.map(patch => `
        <div class="patch-note">
          <div class="patch-header">
            <span class="patch-version">${esc(patch.version)}</span>
            <span class="patch-compat">Compatible Version: ${esc(patch.compatible)}</span>
          </div>
          ${patch.notice ? `<div class="patch-notice">${esc(patch.notice)}</div>` : ''}
          ${patch.sections.map(renderSection).join('')}
        </div>
      `).join('')}
    </div>
  `;
}

export async function initPatchNotes({ params, query }) {
  const app = document.getElementById('app');
  await loadData();
  app.innerHTML = renderPatchNotes();
}
