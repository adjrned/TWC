import { ICONS_PATH } from '../constants.js';

export let iconLibrary = [];

export async function loadIconLibrary() {
  try {
    const r = await fetch(ICONS_PATH + 'manifest.json');
    if (r.ok) {
      const json = await r.json();
      const names = Array.isArray(json) ? json : Array.isArray(json?.files) ? json.files : null;
      if (Array.isArray(names) && names.length) {
        iconLibrary = names.map(n => ({ name: n, src: ICONS_PATH + encodeURIComponent(n) + '.jpg' }));
        return;
      }
    }
  } catch(e) {}
  try {
    const r = await fetch(ICONS_PATH);
    if (r.ok) {
      const html = await r.text();
      const doc = new DOMParser().parseFromString(html, 'text/html');
      const links = [...doc.querySelectorAll('a[href]')]
        .map(a => a.getAttribute('href'))
        .filter(h => h?.toLowerCase().endsWith('.jpg') && !h.startsWith('?') && !h.startsWith('/'));
      if (links.length) {
        iconLibrary = links.map(h => {
          const file = h.split('/').pop();
          const name = decodeURIComponent(file.replace(/\.jpg$/i,''));
          return { name, src: ICONS_PATH + encodeURIComponent(file) };
        }).sort((a,b) => a.name.localeCompare(b.name));
        return;
      }
    }
  } catch(e) {}
  iconLibrary = [];
}
