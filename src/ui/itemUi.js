import { esc } from './escape.js';
import { iconSrc, getItem } from '../data/items.js';
import { showItemTooltip, moveItemTooltip, hideItemTooltip } from './tooltip.js';

// Icon with a lettered fallback when the image is missing.
export function iconHtml(name, cls, src = iconSrc(name)) {
  const initials = name.replace(/[^A-Za-z0-9 ]/g, '').split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]).join('').toUpperCase();
  return `<span class="${cls}" data-initial="${esc(initials || '?')}"><img src="${src}" alt="" loading="lazy" decoding="async" onerror="this.parentNode.classList.add('no-img');this.remove()"></span>`;
}

// Desktop hover preview for any element (inside `root`) carrying data-name.
// Returns an unbind function — call it in page cleanup when `root` outlives the page (e.g. #app).
export function bindItemHover(root) {
  if (!root || !window.matchMedia('(hover: hover) and (pointer: fine)').matches) return () => {};
  let current = null;
  const over = e => {
    const el = e.target.closest('[data-name]');
    if (el === current) return;
    current = el;
    const item = el && getItem(el.dataset.name);
    if (item) showItemTooltip(item, e.clientX, e.clientY);
    else hideItemTooltip();
  };
  const move = e => { if (current) moveItemTooltip(e.clientX, e.clientY); };
  const leave = () => { current = null; hideItemTooltip(); };
  root.addEventListener('mouseover', over);
  root.addEventListener('mousemove', move);
  root.addEventListener('mouseleave', leave);
  return () => {
    root.removeEventListener('mouseover', over);
    root.removeEventListener('mousemove', move);
    root.removeEventListener('mouseleave', leave);
    hideItemTooltip();
  };
}
