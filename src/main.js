import './styles/base.css';
import './styles/components.css';
import './styles/builder.css';
import './styles/layout.css';
import './styles/bosses.css';
import './styles/items.css';
import './styles/heroes.css';
import './styles/awakening.css';
import './styles/patch-notes.css';
import './styles/tracker.css';
import { registerRoute, initRouter } from './router.js';
import { initBuilder } from './pages/builder/index.js';
import { getLocale, setLocale } from './i18n.js';
import { initCompareTray } from './ui/compareTray.js';
import { initEasterEgg } from './ui/easterEgg.js';

import { t } from './i18n.js';

// Every translatable nav / footer label carries data-i18n="<key>".
function updateNavText() {
  document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.dataset.i18n); });
  document.querySelectorAll('.sidebar .nav-link').forEach(link => {
    const label = link.querySelector('.nav-text');
    if (label) link.dataset.tooltip = label.textContent;
  });
  document.documentElement.lang = getLocale() === 'zh' ? 'zh-CN' : getLocale();
}

// Desktop sidebar and the mobile "More" sheet each have a switcher; keep both in sync.
function initLocaleSwitcher() {
  const buttons = document.querySelectorAll('.locale-switcher .locale-btn');
  const sync = () => buttons.forEach(b => b.classList.toggle('active', b.dataset.locale === getLocale()));
  buttons.forEach(btn => btn.addEventListener('click', () => {
    setLocale(btn.dataset.locale);
    sync();
    updateNavText();
    window.dispatchEvent(new HashChangeEvent('hashchange'));
  }));
  sync();
  updateNavText();
}

// Mobile "More" sheet: secondary pages + language switcher.
function initMoreSheet() {
  const btn = document.getElementById('bnMore');
  const sheet = document.getElementById('bnSheet');
  if (!btn || !sheet) return;
  const setOpen = open => {
    sheet.hidden = !open;
    btn.setAttribute('aria-expanded', String(open));
  };
  btn.addEventListener('click', e => { e.stopPropagation(); setOpen(sheet.hidden); });
  document.addEventListener('click', e => { if (!sheet.hidden && !e.target.closest('#bnSheet')) setOpen(false); });
  document.addEventListener('keydown', e => { if (e.key === 'Escape') setOpen(false); });
  // Highlight "More" when the current page lives in the sheet.
  const highlight = () => {
    const path = (location.hash.slice(1) || '/').split('?')[0];
    btn.classList.toggle('active', ['/heroes', '/awakening', '/patch-notes'].some(r => path.startsWith(r)));
  };
  window.addEventListener('hashchange', () => { setOpen(false); highlight(); });
  highlight();
}

initMoreSheet();
initLocaleSwitcher();

const sidebarToggle = document.getElementById('sidebarToggle');
const sidebar = document.getElementById('sidebar');
if (sidebarToggle && sidebar) {
  const saved = localStorage.getItem('sidebarCollapsed');
  if (saved === 'true') sidebar.classList.add('collapsed');
  sidebarToggle.addEventListener('click', () => {
    sidebar.classList.toggle('collapsed');
    localStorage.setItem('sidebarCollapsed', sidebar.classList.contains('collapsed'));
  });
}

registerRoute('/', async (ctx) => {
  return await initBuilder(ctx);
});

registerRoute('/bosses', async (ctx) => {
  const { initBosses } = await import('./pages/bosses/index.js');
  return await initBosses(ctx);
});

registerRoute('/bosses/:id', async (ctx) => {
  const { initBosses } = await import('./pages/bosses/index.js');
  return await initBosses(ctx);
});

registerRoute('/heroes', async (ctx) => {
  const { initHeroes } = await import('./pages/heroes/index.js');
  return await initHeroes(ctx);
});

registerRoute('/heroes/:id', async (ctx) => {
  const { initHeroes } = await import('./pages/heroes/index.js');
  return await initHeroes(ctx);
});

registerRoute('/awakening', async (ctx) => {
  const { initAwakening } = await import('./pages/awakening/index.js');
  return await initAwakening(ctx);
});

registerRoute('/items', async (ctx) => {
  const { initItems } = await import('./pages/items/index.js');
  return await initItems(ctx);
});

// Must be registered before /items/:name so "compare" isn't read as an item name.
registerRoute('/items/compare', async (ctx) => {
  const { initCompare } = await import('./pages/compare/index.js');
  return await initCompare(ctx);
});

registerRoute('/items/:name', async (ctx) => {
  const { initItems } = await import('./pages/items/index.js');
  return await initItems(ctx);
});

registerRoute('/patch-notes', async (ctx) => {
  const { initPatchNotes } = await import('./pages/patch-notes/index.js');
  return await initPatchNotes(ctx);
});

registerRoute('/patch-notes/:version', async (ctx) => {
  const { initPatchNotes } = await import('./pages/patch-notes/index.js');
  return await initPatchNotes(ctx);
});

registerRoute('/tracker', async (ctx) => {
  const { initTracker } = await import('./pages/tracker/index.js');
  return await initTracker(ctx);
});

initCompareTray();
initEasterEgg();
initRouter();
