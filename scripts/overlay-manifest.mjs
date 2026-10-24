// Writes dist/overlay-manifest.txt after `vite build`: one line per file with its
// SHA-256, size, path and URL path. tw-companion's overlay compares it with its
// local copy to download only the files that changed (see companion/engine/Updater.ahk).
// Plain tab-separated text so AutoHotkey can read it without a JSON parser.
import { createHash } from 'node:crypto';
import { execSync } from 'node:child_process';
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

const DIST = 'dist';
const NAME = 'overlay-manifest.txt';

function walk(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

let sha = 'local';
try { sha = execSync('git rev-parse --short HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch {}
const stamp = new Date().toISOString().slice(0, 16).replace('T', ' ');

const lines = [`version\t${stamp} ${sha}`];
for (const file of walk(DIST).sort()) {
  const path = relative(DIST, file).split(sep).join('/');
  if (path === NAME) continue;
  const buf = readFileSync(file);
  const hash = createHash('sha256').update(buf).digest('hex');
  lines.push([hash, buf.length, path, path.split('/').map(encodeURIComponent).join('/')].join('\t'));
}
writeFileSync(join(DIST, NAME), lines.join('\n') + '\n');
console.log(`${NAME}: ${lines.length - 1} files, version ${stamp} ${sha}`);
