// Patch notes: shared loader + a flat line index used by the Patch Notes page
// (search / filters) and the "Patch history" panels on item, hero and monster pages.
//
// patch: { version, released?, compatible, notice?, source?, sections: [{ title, entries?, subsections? }] }
// entries are strings, or nested string arrays = sub-points of the preceding line.

let patchesPromise = null;
let index = null;

export const SECTION_KEYS = ['Bug Fixes', 'Events', 'Items', 'Monsters', 'Characters', 'Miscellaneous'];

// Hero names in older notes use other spellings.
export const HERO_ALIASES = {
  'Mage (Fire)': 'Fire Mage', 'Mage (Water)': 'Water Mage', 'Mage (Arcane)': 'Arcane Mage',
  'Mage (Lightning)': 'Lightning Mage', 'Mage (Wind)': 'Wind Mage',
  'Soulweaver': 'Soul Weaver', 'Bloodweaver': 'Blood Weaver', 'Bowmaster': 'Bow Master',
  'Sword saint': 'Sword Saint', 'Witch (now Warlock)': 'Warlock', 'Wizard (Fire)': 'Fire Mage',
};
// Short names and old names of bosses. (Typos are fixed in the data: scripts/patch-note-fixes.mjs.)
export const BOSS_ALIASES = {
  'Kamael, the Lightbringer': 'Lightbringer Kamael', 'Kamael': 'Lightbringer Kamael',
  'Valtora': 'Lightning God Valtora',
  'Agareth': 'Underlord Agareth',
  'Gaia': 'Gaia, the Earth Goddess',
  'Styrix': 'Styrix, the Harvester of Souls', 'Soul Harvester Styrix': 'Styrix, the Harvester of Souls',
  'Ancient Construct': 'Arcane Construct',
  'Samael': 'Archangel Samael',
  'Shadow Dragon': 'Shadow Dragon Irbert',
  'Mad Clown': 'Wallachia Mad Clown',
  'Skeleton King Desperia': 'Skeletal King Desperia', 'Skull King Desperia': 'Skeletal King Desperia',
  'Skeleton King': 'Skeletal King Desperia', 'Skeletal King': 'Skeletal King Desperia',
  'Chaos Elemental': 'Elemental of Chaos',
  'Corrupt Angel': "The Devil's Right Arm Corrupt Angel",
  'Guardian Angels': "The 3rd Army's Guardian Angel",
  'Count Wallachia': 'Duchy of Wallachia Count', 'Count of Wallachia': 'Duchy of Wallachia Count',
  'Gatekeeper': 'Castle Avalon Gatekeeper', "Guardian Spirit, Avalon's Gatekeeper": 'Castle Avalon Gatekeeper',
  'Demon Lord': 'Demon Lord Beriel',
  'Duke': 'Duke Lazarus',
  'Driads': 'Dryad',
  'Guardian of the Sea': 'Guardian of Sea',
  'Jack-o-Lantern': 'Jack o Lantern',
};

export function loadPatches() {
  if (!patchesPromise) {
    patchesPromise = fetch('data/patch-notes.json')
      .then(r => (r.ok ? r.json() : []))
      .catch(() => []);
  }
  return patchesPromise;
}

// "v0.69e" → "0.69" (timeline grouping)
export function minorOf(version) {
  const m = String(version).match(/^v?(\d+\.\d+)/);
  return m ? m[1] : version;
}

// Splits "Subject - rest" for bug-fix style lines.
export function splitSubject(text) {
  const m = String(text).match(/^(.{2,60}?)\s+-\s+(.+)$/);
  return m ? { subject: m[1], rest: m[2] } : null;
}

/**
 * Flat list of every line:
 *   { p: patchIndex, version, released, section, subject, text, depth, line }
 * `subject` is the subsection name (Items / Monsters / Characters) or the
 * "Subject - …" prefix of list lines; `line` is a running id for keys.
 */
export async function getIndex() {
  if (index) return index;
  const patches = await loadPatches();
  const out = [];
  let line = 0;
  patches.forEach((patch, p) => {
    for (const section of patch.sections || []) {
      const push = (list, subject, depth) => {
        for (const x of list || []) {
          if (Array.isArray(x)) { push(x, subject, depth + 1); continue; }
          const own = !subject && depth === 0 ? splitSubject(x)?.subject || '' : '';
          out.push({ p, version: patch.version, released: patch.released || '', section: section.title, subject: subject || own, text: x, depth, line: line++ });
        }
      };
      push(section.entries, '', 0);
      for (const sub of section.subsections || []) push(sub.entries, sub.name, 0);
    }
  });
  index = { patches, lines: out };
  return index;
}

/** Lines about one subject, newest first. `names` are accepted spellings (exact, case-insensitive). */
export async function historyFor(names) {
  const { lines } = await getIndex();
  const wanted = new Set(names.filter(Boolean).map(n => n.toLowerCase()));
  for (const [alias, real] of Object.entries({ ...HERO_ALIASES, ...BOSS_ALIASES })) {
    if (wanted.has(real.toLowerCase())) wanted.add(alias.toLowerCase());
  }
  return lines.filter(l => l.subject && wanted.has(l.subject.toLowerCase()));
}
