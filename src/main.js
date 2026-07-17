import './styles/base.css';
import './styles/components.css';
import './styles/builder.css';
import './styles/layout.css';
import './styles/bosses.css';
import './styles/items.css';
import { registerRoute, initRouter } from './router.js';
import { initBuilder } from './pages/builder/index.js';

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
