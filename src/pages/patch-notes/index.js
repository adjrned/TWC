import { esc } from '../../ui/escape.js';

let patchData = null;

async function loadData() {
  if (patchData) return;
  try {
    const res = await fetch('data/patch-notes.json');
    if (res.ok) patchData = await res.json();
  } catch(e) {}
  if (!patchData) patchData = [];
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
      html += `<div class="patch-subsection">`;
      html += `<h4 class="patch-subsection-name">${esc(sub.name)}</h4>`;
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
