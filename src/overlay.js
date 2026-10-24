// Desktop overlay support. tw-companion (AutoHotkey) hosts this app in a WebView2
// window over Warcraft III, served from a local copy at https://twc.local/TWC/.
// Messages to the host are plain strings ("hide", "update", "open|<url>");
// the host answers with JSON objects ({ type: 'update', state, ... }).
import { t } from './i18n.js';
import { showToast } from './ui/toast.js';

const PUBLIC_URL = 'https://adjrned.github.io/TWC/';
const host = window.chrome?.webview;
export const inOverlay = !!host;

// Base for links people share: the public site in the overlay (the local
// address means nothing to anyone else), this page otherwise.
export function shareBase() {
  return inOverlay ? PUBLIC_URL : location.origin + location.pathname;
}
export const shareHref = () => shareBase() + location.hash;

const send = msg => host?.postMessage(msg);

let bars = [];
let updateState = 'idle';

function renderBars(info = {}) {
  const label = {
    idle: t('overlay.check'),
    checking: t('overlay.checking'),
    current: t('overlay.current'),
    available: t('overlay.install'),
    downloading: info.total ? t('overlay.downloading', { done: info.done, total: info.total }) : t('overlay.checking'),
    error: t('overlay.retry'),
  }[updateState] || t('overlay.check');
  const busy = updateState === 'checking' || updateState === 'downloading';
  for (const bar of bars) {
    const btn = bar.querySelector('.ov-update');
    btn.textContent = label;
    btn.disabled = busy;
    btn.classList.toggle('primary', updateState === 'available');
    if (info.version) bar.querySelector('.ov-ver').textContent = t('overlay.version', { v: info.version });
  }
}

function onHostMessage(msg) {
  if (!msg || typeof msg !== 'object') return;
  if (msg.type === 'version') renderBars({ version: msg.version });
  if (msg.type === 'update') {
    updateState = msg.state;
    renderBars(msg);
    if (msg.state === 'current' && msg.manual) showToast(t('overlay.current'));
    if (msg.state === 'available' && !msg.manual) showToast(t('overlay.available'), { action: { label: t('overlay.install'), onClick: () => send('update') } });
    if (msg.state === 'error') showToast(msg.message || t('overlay.error'));
  }
}

// Esc hides the overlay, unless it closed something in the app first (a menu,
// a picker, a search box): if nothing on the page changes, nothing used it.
function initEscape() {
  window.addEventListener('keydown', e => {
    if (e.key !== 'Escape' || e.defaultPrevented || e.repeat) return;
    let changed = false;
    const obs = new MutationObserver(() => { changed = true; });
    obs.observe(document.body, { subtree: true, childList: true, attributes: true, characterData: true });
    setTimeout(() => { obs.disconnect(); if (!changed) send('hide'); }, 80);
  });
}

// Links to other sites open in the normal browser, not inside the overlay.
function initExternalLinks() {
  document.addEventListener('click', e => {
    const a = e.target.closest('a[href]');
    if (!a) return;
    const url = new URL(a.href, location.href);
    if (url.origin === location.origin || !/^https?:$/.test(url.protocol)) return;
    e.preventDefault();
    send('open|' + url.href);
  }, true);
}

export function initOverlay() {
  if (!inOverlay) return;
  document.documentElement.classList.add('in-overlay');
  for (const foot of document.querySelectorAll('.sidebar-footer, .bn-sheet-foot')) {
    const bar = document.createElement('div');
    bar.className = 'ov-bar';
    bar.innerHTML = '<span class="ov-ver"></span><button type="button" class="btn ov-update"></button>';
    bar.querySelector('.ov-update').addEventListener('click', () => send('update'));
    foot.prepend(bar);
    bars.push(bar);
  }
  renderBars();
  host.addEventListener('message', e => onHostMessage(e.data));
  initEscape();
  initExternalLinks();
  send('ready');
}
