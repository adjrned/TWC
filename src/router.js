const routes = [];
let currentCleanup = null;
let lastPage = null;
let lastPath = null;

export function registerRoute(pattern, handler) {
  const paramNames = [];
  const regexStr = pattern.replace(/:([^/]+)/g, (_, name) => {
    paramNames.push(name);
    return '([^/]+)';
  });
  routes.push({ regex: new RegExp('^' + regexStr + '$'), paramNames, handler });
}

function parseHash() {
  const raw = location.hash.slice(1) || '/';
  const [path, queryStr] = raw.split('?');
  const query = Object.fromEntries(new URLSearchParams(queryStr || ''));
  return { path, query };
}

function matchRoute(path) {
  for (const route of routes) {
    const match = path.match(route.regex);
    if (match) {
      const params = {};
      route.paramNames.forEach((name, i) => {
        params[name] = decodeURIComponent(match[i + 1]);
      });
      return { handler: route.handler, params };
    }
  }
  return null;
}

// Navigations run one at a time: if the hash changes while a page is still
// loading, wait for it, then render only the latest URL (skipping any in between).
// Otherwise a slow page could finish after a newer one and overwrite it.
let routing = false;
let rerouteQueued = false;

async function handleRoute() {
  if (routing) { rerouteQueued = true; return; }
  routing = true;
  try {
    do {
      rerouteQueued = false;
      await renderRoute();
    } while (rerouteQueued);
  } finally {
    routing = false;
  }
}

async function renderRoute() {
  const { path, query } = parseHash();

  if (currentCleanup) {
    currentCleanup();
    currentCleanup = null;
  }

  navCount++;
  const app = document.getElementById('app');
  app.classList.remove('page-enter');
  if (path !== lastPath) window.scrollTo(0, 0);
  lastPath = path;

  const matched = matchRoute(path);
  if (matched) {
    currentCleanup = await matched.handler({ params: matched.params, query }) || null;
  } else {
    const fallback = matchRoute('/');
    if (fallback) {
      currentCleanup = await fallback.handler({ params: {}, query }) || null;
    }
  }

  // Only fade between pages — re-renders of the same page (filters, locale) stay instant.
  const page = path.split('/')[1] || '';
  if (page !== lastPage) {
    void app.offsetWidth;
    app.classList.add('page-enter');
  }
  lastPage = page;

  updateActiveNav(path);
}

function updateActiveNav(path) {
  document.querySelectorAll('.nav-link').forEach(link => {
    const route = link.dataset.route;
    if (route == null) return; // e.g. the mobile 'More' button
    const isActive = path === route || (route !== '/' && path.startsWith(route));
    link.classList.toggle('active', isActive);
  });
}

export function navigate(hash) {
  location.hash = hash;
}

// Back button: return to the previous in-app page, or to `fallback` when the
// page was opened directly (shared link / new tab) so we never leave the site.
let navCount = 0;
export function goBack(fallback) {
  if (navCount > 1) history.back();
  else location.hash = fallback;
}
window.appBack = goBack;

export function initRouter() {
  window.addEventListener('hashchange', handleRoute);
  handleRoute();
}
