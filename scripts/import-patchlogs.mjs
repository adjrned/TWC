// Imports plain-text patch logs (one file per patch, e.g. "v72b-patchlog.txt") into
// data/patch-notes.json, replacing any existing patch with the same version.
//
//   node scripts/import-patchlogs.mjs <dir>
//
// Log format: a "Compatible version:" line, then section headers ("Bug Fixes", "Items",
// "Monster", "System", …) at column 0 with lines indented below them (tabs or 4 spaces;
// "* " bullets optional). In Items / Monsters / Characters a line with lines below it
// is a subject (item, boss or hero name); deeper lines become nested sub-points.
import fs from 'fs';
import path from 'path';
import { fixPatches } from './patch-note-fixes.mjs';
import { compareVersions } from './versions.mjs';

const DIR = process.argv[2];
const OUT = 'data/patch-notes.json';
if (!DIR) { console.error('usage: node scripts/import-patchlogs.mjs <dir>'); process.exit(1); }

const SECTIONS = {
  'bug fix': 'Bug Fixes', 'bug fixes': 'Bug Fixes',
  'event': 'Events', 'events': 'Events',
  'item': 'Items', 'items': 'Items',
  'monster': 'Monsters', 'monsters': 'Monsters',
  'character': 'Characters', 'characters': 'Characters',
  'system': 'Miscellaneous', 'system changes': 'Miscellaneous', 'misc': 'Miscellaneous',
  'miscellaneous': 'Miscellaneous', 'temporary': 'Miscellaneous',
};
const SUBJECT_SECTIONS = new Set(['Items', 'Monsters', 'Characters']);
const ORDER = ['Bug Fixes', 'Events', 'Items', 'Monsters', 'Characters', 'Miscellaneous'];

// Indent level (tab = 4 spaces), whether it had a "* " bullet, and the cleaned text.
// "X – Y" becomes "X - Y" so "Subject - …" lines split like the rest of the notes, and curly
// quotes become straight ones to match item names ("Heaven’s Fall" → "Heaven's Fall").
function parseLine(raw) {
  const [, ws, rest] = raw.replace(/\s+$/, '').match(/^([\t ]*)(.*)$/);
  const bullet = /^[*•]\s*/.test(rest);
  const text = rest.replace(/^[*•]\s*/, '').replace(/\s+[–—]\s+/g, ' - ').replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/ {2,}/g, ' ').trim();
  return { level: Math.floor(ws.replace(/\t/g, '    ').length / 4), bullet, text };
}

// Re-base levels so the shallowest line is 0.
function rebase(ls) {
  const min = Math.min(...ls.map(l => l.level));
  return ls.map(l => ({ ...l, level: l.level - min }));
}

// Lines → strings, each followed by a nested array of the deeper lines below it
// (or, in unindented logs, of the bullets right after a plain line).
function tree(ls) {
  const out = [];
  for (let i = 0; i < ls.length;) {
    let j = i + 1;
    while (j < ls.length && ls[j].level > ls[i].level) j++;
    if (j === i + 1 && !ls[i].bullet) while (j < ls.length && ls[j].bullet && ls[j].level === ls[i].level) j++;
    out.push(ls[i].text);
    if (j > i + 1) out.push(tree(rebase(ls.slice(i + 1, j))));
    i = j;
  }
  return out;
}

// Items / Monsters / Characters: subjects with their lines, plus loose lines as entries.
function subjects(ls) {
  const entries = [], subsections = [];
  for (let i = 0; i < ls.length;) {
    const l = ls[i];
    let j = i + 1;
    while (j < ls.length && ls[j].level > l.level) j++;
    // Unindented logs: a plain line followed by bullets at the same level.
    if (j === i + 1 && !l.bullet) while (j < ls.length && ls[j].bullet && ls[j].level === l.level) j++;
    if (j > i + 1) subsections.push({ name: l.text, entries: tree(rebase(ls.slice(i + 1, j))) });
    else entries.push(l);
    i = j;
  }
  return { ...(entries.length ? { entries: tree(entries) } : {}), ...(subsections.length ? { subsections } : {}) };
}

function convert(file) {
  const version = 'v0.' + path.basename(file).match(/^v(\d+[a-z]*\d*)/i)[1];
  const lines = fs.readFileSync(file, 'utf8').replace(/^﻿/, '').split(/\r?\n/).map(parseLine).filter(l => l.text);
  const out = { version, compatible: '', sections: [], source: 'patchlog' };
  const bySection = new Map();
  let section = 'Bug Fixes'; // logs without headers are lists of fixes
  for (const l of lines) {
    const compat = l.text.match(/^compatible version:\s*(.*)$/i);
    if (compat) { out.compatible = compat[1]; continue; }
    const header = !l.bullet && SECTIONS[l.text.toLowerCase()];
    if (header) { section = header; continue; }
    if (!bySection.has(section)) bySection.set(section, []);
    bySection.get(section).push(l);
  }
  for (const title of ORDER) {
    if (!bySection.has(title)) continue;
    const ls = rebase(bySection.get(title));
    out.sections.push({ title, ...(SUBJECT_SECTIONS.has(title) ? subjects(ls) : { entries: tree(ls) }) });
  }
  return out;
}

const imported = fs.readdirSync(DIR).filter(f => /^v\d.*\.txt$/i.test(f)).map(f => convert(path.join(DIR, f)));
fixPatches(imported);

const byVersion = new Map(JSON.parse(fs.readFileSync(OUT, 'utf8')).map(p => [p.version, p]));
for (const p of imported) byVersion.set(p.version, p);
const merged = [...byVersion.values()].sort(compareVersions);
fs.writeFileSync(OUT, JSON.stringify(merged, null, 1) + '\n');
console.log(`${imported.length} logs imported (${imported.map(p => p.version).join(', ')}) → ${merged.length} patches`);
