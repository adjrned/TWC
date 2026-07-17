const routes = [];
let currentCleanup = null;

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

async function handleRoute() {
  const { path, query } = parseHash();

  if (currentCleanup) {
    currentCleanup();
    currentCleanup = null;
  }

  const app = document.getElementById('app');
  app.classList.add('page-exit');
  await new Promise(r => setTimeout(r, 100));

  const matched = matchRoute(path);
  if (matched) {
    currentCleanup = await matched.handler({ params: matched.params, query }) || null;
  } else {
    const fallback = matchRoute('/');
    if (fallback) {
      currentCleanup = await fallback.handler({ params: {}, query }) || null;
    }
  }

  app.classList.remove('page-exit');
  app.classList.add('page-enter');
  setTimeout(() => app.classList.remove('page-enter'), 150);

  updateActiveNav(path);
}

function updateActiveNav(path) {
  document.querySelectorAll('.nav-link').forEach(link => {
    const route = link.dataset.route;
    const isActive = path === route || (route !== '/' && path.startsWith(route));
    link.classList.toggle('active', isActive);
  });
}

export function navigate(hash) {
  location.hash = hash;
}

export function initRouter() {
  window.addEventListener('hashchange', handleRoute);
  handleRoute();
}
