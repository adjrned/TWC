// Floating "back to top" button, bottom-right. Shown once the page has been
// scrolled past roughly one screen.
import { t } from '../i18n.js';

const SHOW_AFTER = 600; // px scrolled

export function initScrollTop() {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.id = 'scrollTopBtn';
  btn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="6 15 12 9 18 15"/></svg>';
  const label = () => {
    btn.setAttribute('aria-label', t('common.backToTop'));
    btn.title = t('common.backToTop');
  };
  label();
  document.body.appendChild(btn);

  btn.addEventListener('click', () => {
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    window.scrollTo({ top: 0, behavior: reduce ? 'auto' : 'smooth' });
  });

  let ticking = false;
  const update = () => {
    ticking = false;
    btn.classList.toggle('show', window.scrollY > SHOW_AFTER);
  };
  window.addEventListener('scroll', () => {
    if (!ticking) { ticking = true; requestAnimationFrame(update); }
  }, { passive: true });
  // Locale switches re-dispatch hashchange; refresh the label then too.
  window.addEventListener('hashchange', () => { label(); update(); });
  update();
}
