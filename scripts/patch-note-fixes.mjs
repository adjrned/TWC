// Spelling fixes for patch notes, so names match our item / boss / hero / skill data
// (search, subject links and "Patch history" panels all match on exact names).
// Used by import-changelog.mjs; run directly to fix data/patch-notes.json in place:
//
//   node scripts/patch-note-fixes.mjs
//
// Old names and nicknames (Valtora, Skeleton King, …) are not typos; those are
// handled as aliases in src/data/patches.js.
import fs from 'fs';
import { fileURLToPath } from 'url';

// [pattern, replacement]: plain strings match whole words, case-sensitively.
export const TYPOS = [
  // Tiers / places
  ['Altheia', 'Alteia'],
  ['Castle AValon', 'Castle Avalon'],
  ['walalchia', 'Wallachia'],
  ['Pruis', 'Prius'],
  // Monsters
  ['Sahdow', 'Shadow'],
  ['Shadown', 'Shadow'],
  ['Anceint', 'Ancient'],
  ['Irfrit', 'Ifrit'],
  ['Ifirit', 'Ifrit'],
  ['Corrputor', 'Corruptor'],
  ['Gaint', 'Giant'],
  ['monstrostity', 'monstrosity'],
  // Heroes
  ['Wing Mage', 'Wind Mage'],
  ['Wing mage', 'Wind Mage'],
  ['Lightning MAge', 'Lightning Mage'],
  ['Swordman', 'Swordsman'],
  ['Figthers', 'Fighters'],
  ['merchange', 'merchant'],
  // Items
  ['Spirit Besat', 'Spirit Beast'],
  ['Vengance', 'Vengeance'],
  ['Cyrstal', 'Crystal'],
  ['Espichu', 'Espishu'],
  ['Nepthtys', 'Nephthys'],
  ['Reaoer', 'Reaper'],
  ['Plauge', 'Plague'],
  ['Bloostone', 'Bloodstone'],
  ['Purfied', 'Purified'],
  ['Amror', 'Armor'],
  ['Crown of Ferver', 'Crown of Fervor'],
  ["Oath of Courages's", "Oath of Courage's"],
  ['Coins of Effor', 'Coins of Effort'],
  ['Heavens Door', "Heaven's Door"],
  ['Atricia, the Sword of Nightmare', 'Atricia, the Sword of Nightmares'],
  ['King Kong Claws', "King Kong's Claws"],
  ['Hydrobuster', 'Hydro Buster'],
  ['Harvester Token', "Harvester's Token"],
  ['Halo of Judgement', 'Halo of Judgment'],
  ['Echo of the Void', 'Echoes of the Void'],
  // Skills
  ['Ambus', 'Ambush'],
  ['Barage', 'Barrage'],
  ['Cresent', 'Crescent'],
  ['Echant', 'Enchant'],
  ['Enchanced', 'Enhanced'],
  ['Harvet', 'Harvest'],
  ['Hyperchargec', 'Hypercharge'],
  ['Grimore', 'Grimoire'],
  ['Tranfer', 'Transfer'],
  ['Power Slame', 'Power Slam'],
  ['Heart Breat', 'Heart Break'],
  ['Footwalk', 'Footwork'],
  ['Nanaomachine', 'Nanomachine'],
  ['Amplication', 'Amplification'],
  ['transmuation', 'transmutation'],
  ['trasmutation', 'transmutation'],
  ['ressurection', 'resurrection'],
  ['framgents', 'fragments'],
  ['sheild', 'shield'],
].map(([from, to]) => [new RegExp(`\\b${from.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'g'), to]);

export const fixText = s => TYPOS.reduce((t, [re, to]) => t.replace(re, to), s);

// Every name a subject can link to, keyed by lowercase.
export function loadCanonicalNames(dir = 'data') {
  const read = f => JSON.parse(fs.readFileSync(`${dir}/${f}`, 'utf8'));
  const names = new Map();
  const add = n => n && !names.has(n.toLowerCase()) && names.set(n.toLowerCase(), n);
  read('items.json').forEach(i => add(i.name));
  read('bosses.json').forEach(b => add(b.name));
  read('heroes.json').forEach(h => add(h.heroClass));
  return names;
}

/**
 * Fixes typos in every string of `patches` (mutates), and gives subjects that only
 * differ in case from a known name the canonical casing ("Shrine priestess" → "Shrine Priestess").
 * Returns the number of strings changed.
 */
export function fixPatches(patches, names = loadCanonicalNames()) {
  let changed = 0;
  const canon = s => names.get(s.toLowerCase()) || s;
  const fix = (s, subject) => {
    let out = fixText(s);
    if (subject) out = canon(out);
    else {
      const m = out.match(/^(.{2,60}?)(\s+-\s+.+)$/); // "Subject - rest", as in splitSubject()
      if (m) out = canon(m[1]) + m[2];
    }
    if (out !== s) changed++;
    return out;
  };
  const fixList = (list, depth = 0) => (list || []).map(x => (Array.isArray(x) ? fixList(x, depth + 1) : fix(x, false)));
  for (const p of patches) {
    if (p.notice) p.notice = fixText(p.notice);
    for (const sec of p.sections || []) {
      if (sec.entries) sec.entries = fixList(sec.entries);
      for (const sub of sec.subsections || []) {
        sub.name = fix(sub.name, true);
        sub.entries = fixList(sub.entries);
      }
    }
  }
  return changed;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const OUT = 'data/patch-notes.json';
  const patches = JSON.parse(fs.readFileSync(OUT, 'utf8'));
  const n = fixPatches(patches);
  fs.writeFileSync(OUT, JSON.stringify(patches, null, 1) + '\n');
  console.log(`${n} lines fixed in ${OUT}`);
}
