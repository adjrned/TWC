import { t } from '../../i18n.js';

export async function initHeroes({ params, query }) {
  const app = document.getElementById('app');
  app.innerHTML = `
    <div class="page-header">
      <h1>Heroes</h1>
      <p class="page-subtitle">Class guides, skill trees, and build recommendations</p>
    </div>
    <div class="coming-soon">
      <div class="coming-soon-icon">🧙</div>
      <h2>Coming Soon</h2>
      <p>Hero guides and class information will be available here.</p>
    </div>
  `;
}
