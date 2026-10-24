// Copies the built site (dist/) into tw-companion as the overlay's offline bundle:
// <companion>/web/TWC/. The companion folder defaults to ./companion;
// pass a path as the first argument or set TWC_COMPANION_DIR to change it.
import { cpSync, existsSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';

const companion = resolve(process.argv[2] || process.env.TWC_COMPANION_DIR || 'companion');
if (!existsSync(join(companion, 'tw-companion.ahk'))) {
  console.error(`tw-companion.ahk not found in ${companion}`);
  process.exit(1);
}
if (!existsSync('dist/overlay-manifest.txt')) {
  console.error('dist/overlay-manifest.txt missing - run `npm run build` first');
  process.exit(1);
}
const target = join(companion, 'web', 'TWC');
rmSync(target, { recursive: true, force: true });
cpSync('dist', target, { recursive: true });
console.log(`Overlay bundle copied to ${target}`);
