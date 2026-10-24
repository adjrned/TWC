// Runs public/data/sim.json calibration cases (in-game test hits) through the damage sim engine.
// Usage: npm run sim-check            → pass/fail per case
//        npm run sim-check -- --steps → also print each case's step breakdown
import { readFileSync } from 'node:fs';
import { buildModel } from '../src/sim/model.js';
import { simulate } from '../src/sim/engine.js';

const read = f => JSON.parse(readFileSync(new URL(`../public/data/${f}`, import.meta.url), 'utf8'));
const model = buildModel({
  items: read('items.json'), skills: read('skills.json'), heroes: read('heroes.json'),
  effects: read('effects.json'), sim: read('sim.json'),
});
const showSteps = process.argv.includes('--steps');
const fmt = n => Math.round(n).toLocaleString('en-US');

let failed = 0;
for (const c of model.calibration) {
  const r = simulate(model, c.setup);
  const diff = r ? r.total / c.expect - 1 : NaN;
  const ok = Math.abs(diff) <= (c.tolerance ?? 0.01);
  if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${fmt(r?.total ?? 0)} vs ${fmt(c.expect)} (${(diff * 100).toFixed(2)}%)  ${c.note}`);
  if (showSteps && r) {
    for (const s of r.steps) console.log(`      ${s.id.padEnd(17)} ${s.skipped ? `— (${s.note})` : `${s.op} ${s.op === '+' ? fmt(s.factor) : s.factor.toFixed(4)}`}  → ${fmt(s.value)}`);
  }
}
process.exit(failed ? 1 : 0);
