import { esc } from './escape.js';
import { t, tf, getLocale } from '../i18n.js';
import { historyFor } from '../data/patches.js';

function fmtDate(iso) {
  if (!/^\d{4}-\d\d-\d\d$/.test(iso || '')) return iso || '';
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString(getLocale() === 'zh' ? 'zh-CN' : getLocale(), { year: 'numeric', month: 'short', day: 'numeric' });
}

const arrow = s => esc(s).replace(/\s*(?:-&gt;|→)\s*/g, ' <span class="pn-arrow">→</span> ');

/**
 * Appends a "Patch history" section to a detail page's side column, listing the
 * most recent patches that changed `names[0]` (other entries are alternate spellings).
 * Loads patch data lazily, after the page has rendered; does nothing if there's no history.
 */
export async function appendPatchHistory(detailEl, names, { maxPatches = 6 } = {}) {
  if (!detailEl) return;
  const lines = await historyFor(names);
  if (!lines.length || !detailEl.isConnected) return;

  const byPatch = new Map();
  for (const l of lines) {
    if (!byPatch.has(l.version)) byPatch.set(l.version, { released: l.released, section: l.section, lines: [] });
    byPatch.get(l.version).lines.push(l);
  }
  const shown = [...byPatch.entries()].slice(0, maxPatches);
  const html = `<section class="idb-section ph-section">
    <h2>${t('pn.history')} <span class="idb-count">${byPatch.size}</span></h2>
    <div class="ph-list">${shown.map(([version, g]) => `
      <div class="ph-patch">
        <div class="ph-head">
          <a href="#/patch-notes/${esc(version)}">${esc(version)}</a>
          ${g.released ? `<time datetime="${esc(g.released)}">${esc(fmtDate(g.released))}</time>` : ''}
          <span class="ph-sec">${esc(tf('pn.section.' + g.section, g.section))}</span>
        </div>
        <ul class="pn-lines">${g.lines.map(l => `<li class="d${Math.min(l.depth, 2)}">${arrow(l.text)}</li>`).join('')}</ul>
      </div>`).join('')}
    </div>
    <a class="ph-all" href="#/patch-notes?q=${encodeURIComponent(names[0])}">${t('pn.historyAll', { n: lines.length })} →</a>
  </section>`;

  // Use the existing side column, or create one for single-column layouts.
  let side = detailEl.querySelector(':scope > .idb-side');
  if (!side) {
    side = document.createElement('div');
    side.className = 'idb-side';
    detailEl.appendChild(side);
    detailEl.classList.remove('single');
  }
  side.insertAdjacentHTML('beforeend', html);
}
