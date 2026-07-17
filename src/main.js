import './styles/base.css';
import './styles/components.css';
import './styles/builder.css';
import './styles/layout.css';
import './styles/bosses.css';
import './styles/items.css';
import { registerRoute, initRouter } from './router.js';
import { initBuilder } from './pages/builder/index.js';
import { getLocale, setLocale } from './i18n.js';

// Locale switcher
function initLocaleSwitcher() {
  const switcher = document.getElementById('localeSwitcher');
  if (!switcher) return;
  const current = getLocale();
  switcher.querySelectorAll('.locale-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.locale === current);
    btn.addEventListener('click', () => {
      setLocale(btn.dataset.locale);
      switcher.querySelectorAll('.locale-btn').forEach(b => b.classList.toggle('active', b === btn));
      // Re-navigate to reload current page with new locale
      window.dispatchEvent(new HashChangeEvent('hashchange'));
    });
  });
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
