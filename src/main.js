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

import { t } from './i18n.js';

function updateNavText() {
  const links = document.querySelectorAll('.sidebar .nav-link');
  const labels = ['nav.builder', 'nav.items', null, 'nav.bosses', 'nav.heroes', 'nav.awakening'];
  links.forEach((link, i) => {
    if (!labels[i]) return;
    const textNodes = [...link.childNodes].filter(n => n.nodeType === 3);
    textNodes.forEach(n => { if (n.textContent.trim()) n.textContent = '\n        ' + t(labels[i]) + '\n        '; });
  });

  const mobileLinks = document.querySelectorAll('.bottom-nav .nav-link');
  const shortLabels = ['nav.builder.short', 'nav.heroes.short', 'nav.items.short', 'nav.bosses.short', 'nav.awakening.short'];
  mobileLinks.forEach((link, i) => {
    if (!shortLabels[i]) return;
    const textNodes = [...link.childNodes].filter(n => n.nodeType === 3);
    textNodes.forEach(n => { if (n.textContent.trim()) n.textContent = '\n    ' + t(shortLabels[i]) + '\n  '; });
  });

  const footer = document.querySelector('.sidebar-footer > p');
  if (footer) footer.textContent = t('common.madeBy');
}

function initLocaleSwitcher() {
  const switcher = document.getElementById('localeSwitcher');
  if (!switcher) return;
  const current = getLocale();
  switcher.querySelectorAll('.locale-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.locale === current);
    btn.addEventListener('click', () => {
      setLocale(btn.dataset.locale);
      switcher.querySelectorAll('.locale-btn').forEach(b => b.classList.toggle('active', b === btn));
      updateNavText();
      window.dispatchEvent(new HashChangeEvent('hashchange'));
    });
  });
  updateNavText();
}

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

registerRoute('/items/:name', async (ctx) => {
  const { initItems } = await import('./pages/items/index.js');
  return await initItems(ctx);
});

registerRoute('/patch-notes', async (ctx) => {
  const { initPatchNotes } = await import('./pages/patch-notes/index.js');
  return await initPatchNotes(ctx);
});

registerRoute('/tracker', async (ctx) => {
  const { initTracker } = await import('./pages/tracker/index.js');
  return await initTracker(ctx);
});

initRouter();
