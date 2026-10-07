import { state } from '../../state.js';
import { DEFAULT_ROWS, COLS, buildFileNameForCreator } from '../../constants.js';
import { esc } from '../../ui/escape.js';
import { t, getClassName, getLocale } from '../../i18n.js';
import { fetchCreatorsForClass, hasLocalData, loadBuildFile } from '../../data/builds.js';
import { save } from '../../data/storage.js';
import { getItem, rankInfo, iconSrc } from '../../data/items.js';

// Panel listing a class's community builds, each with a preview of its final phase.
const fileCache = new Map();

async function fetchBuild(cls, creator) {
  const key = cls + '|' + creator;
  if (!fileCache.has(key)) {
    fileCache.set(key, fetch('builds/' + buildFileNameForCreator(cls, creator))
      .then(r => (r.ok ? r.json() : null)).catch(() => null));
  }
  return fileCache.get(key);
}

function lastFilledRow(data) {
  const rows = (data?.rows || []).filter(r => Object.values(r.slots || {}).some(v => (Array.isArray(v) ? v.length : v)));
  return rows[rows.length - 1] || null;
}

function previewHtml(data) {
  const row = lastFilledRow(data);
  if (!row) return '';
  return `<span class="bb-preview">${COLS.map(col => {
    const v = row.slots?.[col];
    const first = Array.isArray(v) ? v[0] : v;
    if (!first?.name) return '<span class="bb-pv empty"></span>';
    return `<span class="bb-pv ${rankInfo(getItem(first.name)).css}"><img src="${iconSrc(first.name)}" alt="" loading="lazy"></span>`;
  }).join('')}</span>`;
}

export function fmtBuildDate(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  const locale = getLocale() === 'zh' ? 'zh-CN' : getLocale();
  return isNaN(d) ? '' : d.toLocaleDateString(locale, { year: 'numeric', month: 'short', day: 'numeric' });
}

export function isBuildBrowserOpen() {
  return !document.getElementById('buildBrowser')?.hidden;
}

export function closeBuildBrowser() {
  const el = document.getElementById('buildBrowser');
  if (el) el.hidden = true;
  document.getElementById('buildBrowserBtn')?.setAttribute('aria-expanded', 'false');
}

// `onChosen` re-syncs the builder UI after a build is loaded.
export async function openBuildBrowser(onChosen) {
  const el = document.getElementById('buildBrowser');
  const cls = state.selectedClass;
  if (!el || !cls) return;
  const creators = await fetchCreatorsForClass(cls);
  const datas = await Promise.all(creators.map(c => fetchBuild(cls, c)));

  el.innerHTML = `
    <div class="bb-head">
      <h2>${t('builder.communityBuilds', { cls: esc(getClassName(cls)) })}</h2>
      <button type="button" class="bb-close" data-bb-close aria-label="${esc(t('picker.close'))}">×</button>
    </div>
    ${creators.length ? '' : `<p class="bb-none">${t('builder.noBuilds')}</p>`}
    <div class="bb-cards">
      ${creators.map((c, i) => {
        const data = datas[i];
        const phases = (data?.rows || []).length;
        const active = state.selectedCreator === c;
        return `<button type="button" class="bb-card${active ? ' active' : ''}" data-creator="${esc(c)}">
          <span class="bb-creator">${esc(c)}${active ? ` <span class="bb-current">${t('builder.current')}</span>` : ''}</span>
          <span class="bb-meta">${[phases ? t('builder.phases', { n: phases }) : '', fmtBuildDate(data?.publishedAt)].filter(Boolean).join(' · ')}</span>
          ${previewHtml(data)}
        </button>`;
      }).join('')}
      <button type="button" class="bb-card bb-blank" data-creator="">
        <span class="bb-creator">${t('builder.startScratch')}</span>
        <span class="bb-meta">${t('builder.startScratchHint')}</span>
      </button>
    </div>`;
  el.hidden = false;
  document.getElementById('buildBrowserBtn')?.setAttribute('aria-expanded', 'true');

  el.onclick = async e => {
    if (e.target.closest('[data-bb-close]')) return closeBuildBrowser();
    const card = e.target.closest('.bb-card');
    if (!card) return;
    const creator = card.dataset.creator || null;
    if (creator && creator === state.selectedCreator) return closeBuildBrowser();
    if (hasLocalData(cls) && !confirm(t('builder.replaceConfirm', { cls: getClassName(cls) }))) return;
    await chooseBuild(cls, creator);
    closeBuildBrowser();
    onChosen?.();
  };
}

export async function chooseBuild(cls, creator) {
  delete state.builds[cls];
  state.selectedCreator = creator;
  state.creatorName = '';
  state.publishedAt = '';
  if (creator) {
    await loadBuildFile(cls, creator);
  } else {
    state.rows = DEFAULT_ROWS.map(n => ({ id: state.uid++, name: n }));
    state.builds[cls] = {};
  }
  save();
}
