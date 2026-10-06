// Imports historical patch notes from sfarmani/twrpg-info's changelog.json and
// merges them into data/patch-notes.json (our own entries win on conflicts).
//
//   node scripts/import-changelog.mjs [path-or-url]
//
// Source format (per patch):
//   { name: "69e", notes: ["Released on: …", "Compatible Version: …", …],
//     bugs|events|misc: [string | string[]],          // nested array = sub-points of previous line
//     items|monsters|heroes: [{ name, changes: [string | string[]] | string }] }
import fs from 'fs';
import { fixPatches } from './patch-note-fixes.mjs';
import { compareVersions } from './versions.mjs';

const SRC = process.argv[2] || 'https://raw.githubusercontent.com/sfarmani/twrpg-info/master/changelog.json';
const OUT = 'data/patch-notes.json';

const SECTIONS = [
  ['bugs', 'Bug Fixes', 'list'],
  ['events', 'Events', 'list'],
  ['items', 'Items', 'subjects'],
  ['monsters', 'Monsters', 'subjects'],
  ['heroes', 'Characters', 'subjects'],
  ['misc', 'Miscellaneous', 'list'],
];

const MONTHS = { january: 1, february: 2, march: 3, april: 4, may: 5, june: 6, july: 7, august: 8, september: 9, october: 10, november: 11, december: 12 };

// "December 22nd, 2024" → "2024-12-22"
function isoDate(text) {
  const m = String(text).toLowerCase().match(/([a-z]+),?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})/);
  if (!m || !MONTHS[m[1]]) return null;
  return `${m[3]}-${String(MONTHS[m[1]]).padStart(2, '0')}-${m[2].padStart(2, '0')}`;
}

// Normalise a list to strings / nested string arrays, dropping empties.
function lines(list) {
  if (typeof list === 'string') return list.trim() ? [list.trim()] : [];
  if (!Array.isArray(list)) return [];
  return list
    .map(x => (Array.isArray(x) ? lines(x) : String(x ?? '').trim()))
    .filter(x => (Array.isArray(x) ? x.length : x));
}

function convert(p) {
  const out = { version: 'v0.' + p.name, compatible: '', sections: [] };
  const extra = [];
  for (const n of p.notes || []) {
    if (n.startsWith('Released on:')) out.released = isoDate(n) || n.replace('Released on:', '').trim();
    else if (n.startsWith('Compatible Version:')) out.compatible = n.replace('Compatible Version:', '').trim();
    else if (n.trim()) extra.push(n.trim());
  }
  if (extra.length) out.notice = extra.join(' ');

  for (const [key, title, kind] of SECTIONS) {
    const raw = p[key];
    if (!raw?.length) continue;
    const entries = [], subsections = [];
    for (const x of raw) {
      if (kind === 'subjects' && x && typeof x === 'object' && !Array.isArray(x)) {
        const changes = lines(x.changes);
        if (x.name && changes.length) subsections.push({ name: String(x.name).trim(), entries: changes });
      } else {
        entries.push(...lines([x]));
      }
    }
    if (!entries.length && !subsections.length) continue;
    out.sections.push({ title, ...(entries.length ? { entries } : {}), ...(subsections.length ? { subsections } : {}) });
  }
  return out;
}

const text = /^https?:/.test(SRC) ? await (await fetch(SRC)).text() : fs.readFileSync(SRC, 'utf8');
const imported = JSON.parse(text).map(convert).map(p => ({ ...p, source: 'twrpg-info' }));

// A few dates omit the year ("April 29th"): use the previous (older) patch's year,
// rolling over to the next year when the month wraps (e.g. Dec 24 → Dec 30 vs Jan 5).
imported.forEach((p, i) => {
  if (!p.released || /^\d{4}-/.test(p.released)) return;
  const older = imported.slice(i + 1).find(n => /^\d{4}-/.test(n.released || ''));
  if (!older) return;
  const year = +older.released.slice(0, 4);
  let guess = isoDate(`${p.released}, ${year}`);
  if (guess && guess < older.released) guess = isoDate(`${p.released}, ${year + 1}`);
  if (guess) p.released = guess;
});
fixPatches(imported);

const existing = fs.existsSync(OUT) ? JSON.parse(fs.readFileSync(OUT, 'utf8')).filter(p => p.source !== 'twrpg-info') : [];

const byVersion = new Map(imported.map(p => [p.version, p]));
for (const p of existing) byVersion.set(p.version, p); // ours win
const merged = [...byVersion.values()].sort(compareVersions);

fs.writeFileSync(OUT, JSON.stringify(merged, null, 1) + '\n');
console.log(`${imported.length} imported + ${existing.length} existing → ${merged.length} patches (${merged[0].version} … ${merged[merged.length - 1].version})`);
