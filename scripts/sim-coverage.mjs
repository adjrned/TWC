// Damage sim coverage report: what still needs hand entry in data/sim.json.
// Writes sim-todo.txt (repo root) and prints a summary.
//   - skill damage lines the parser can't read
//   - equipment with passive/active text that has neither curated sim data nor an Effects tab entry
import { readFileSync, writeFileSync } from 'node:fs';
import { unparsedDamageLines, parseConditional, parseExecute } from '../src/sim/parse.js';

const read = f => JSON.parse(readFileSync(new URL(`../data/${f}`, import.meta.url), 'utf8'));
const skills = read('skills.json');
const items = read('items.json');
const effects = read('effects.json');
const sim = read('sim.json');

const fxItems = new Set(effects.sections.flatMap(s => s.categories).flatMap(c => c.types).flatMap(t => t.entries).map(e => e.item).filter(Boolean));
const curatedItems = new Set(Object.keys(sim.items || {}));
const curatedHeroes = new Set(Object.keys(sim.heroes || {}));

// Lines read as conditionals / executes, "last … deals double damage", or on skills curated in sim.json are handled.
const curatedSkill = (hero, skill) => [...(sim.heroes?.[hero]?.modifiers || []), ...(sim.heroes?.[hero]?.extraHits || [])].some(m => m.skill === skill);
const lines = unparsedDamageLines(skills).filter(l => !parseConditional(l.line) && !parseExecute(l.line)
  && !/\blast \w+ deals double damage/i.test(l.line) && !curatedSkill(l.hero, l.skill));
const itemTodo = items
  .filter(i => i.grade > 0 && (i.stats?.passive || i.stats?.active) && !curatedItems.has(i.name) && !fxItems.has(i.name) && !sim.reviewed?.[i.name])
  .sort((a, b) => b.grade - a.grade || a.name.localeCompare(b.name));
const heroes = [...new Set(skills.map(s => s.heroClass))].sort();

const out = [
  `# Damage sim coverage (${new Date().toISOString().slice(0, 10)})`,
  '',
  `Curated heroes: ${curatedHeroes.size}/${heroes.length} — missing: ${heroes.filter(h => !curatedHeroes.has(h)).join(', ')}`,
  `Curated items: ${curatedItems.size}`,
  '',
  `## Unparsed skill damage lines (${lines.length})`,
  ...lines.map(l => `${l.hero} ${l.hotkey} ${l.skill}: ${l.line}`),
  '',
  `## Items with effect text and no sim/Effects data (${itemTodo.length}), highest grade first`,
  ...itemTodo.map(i => `[grade ${i.grade}] ${i.name}`),
  '',
  `## Reviewed and left out (${Object.keys(sim.reviewed || {}).length}; sim.json "reviewed")`,
  ...Object.entries(Object.values(sim.reviewed || {}).reduce((a, r) => ({ ...a, [r]: (a[r] || 0) + 1 }), {})).map(([r, n]) => `${n} × ${r}`),
  '',
];
writeFileSync(new URL('../sim-todo.txt', import.meta.url), out.join('\n'));
console.log(`heroes curated ${curatedHeroes.size}/${heroes.length}, unparsed damage lines ${lines.length}, items to encode ${itemTodo.length} → sim-todo.txt`);
