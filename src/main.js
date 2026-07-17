import './styles/base.css';
import './styles/components.css';
import './styles/builder.css';
import './styles/layout.css';
import './styles/bosses.css';
import './styles/items.css';
import { registerRoute, initRouter } from './router.js';
import { initBuilder } from './pages/builder/index.js';
import { getLocale, setLocale } from './i18n.js';

import { t } from './i18n.js';

function updateNavText() {
  const links = document.querySelectorAll('.sidebar .nav-link');
  const labels = ['nav.builder', 'nav.items', 'nav.bosses'];
  links.forEach((link, i) => {
    const textNodes = [...link.childNodes].filter(n => n.nodeType === 3);
    textNodes.forEach(n => { if (n.textContent.trim()) n.textContent = '\n        ' + t(labels[i]) + '\n        '; });
  });

  const mobileLinks = document.querySelectorAll('.bottom-nav .nav-link');
  const shortLabels = ['nav.builder.short', 'nav.items.short', 'nav.bosses.short'];
  mobileLinks.forEach((link, i) => {
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

registerRoute('/items', async (ctx) => {
  const { initItems } = await import('./pages/items/index.js');
  return await initItems(ctx);
});

registerRoute('/items/:name', async (ctx) => {
  const { initItems } = await import('./pages/items/index.js');
  return await initItems(ctx);
});

initRouter();
