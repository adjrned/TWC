// Damage sim model: turns loaded data (items, skills, heroes, effects, sim) into the
// hits and modifiers the engine works with. No DOM; shared by the page and node scripts.
import { parseHeroHits, parseFxValue, heroExecutes, heroConditionals } from './parse.js';

export const GEAR_SLOTS = ['weapon', 'helm', 'body', 'wings', 'accessory', 'icon'];

// Effects tab category → sim step. `split` categories can carry a flat and a % part ("80 + 4%").
const CAT_STEP = {
  'all-stats': { step: 'statPct', stat: 'all' },
  'attack-damage': { split: true, stat: 'ad' },
  'unique-attack-damage': { step: 'statPct', stat: 'ad' },
  'main-stat': { split: true, stat: 'main' },
  'unique-main-stat': { step: 'statPct', stat: 'main' },
  'skill-damage': { step: 'skillDamage' },
  'unique-skill-damage-amplify': { step: 'amplify' },
  'final-damage': { step: 'final' },
  'unique-final-damage': { step: 'final' },
  'damage-taken': { step: 'targetTaken', target: true },
  'unique-damage-taken': { step: 'targetTaken', target: true },
  'magic-damage-taken': { step: 'targetMagicTaken', target: true },
  'unique-magic-damage-taken': { step: 'targetMagicTaken', target: true },
};
const belowHp = value => {
  const m = String(value).match(/(?:below|under) (\d+(?:\.\d+)?)% HP/i);
  return m ? Number(m[1]) / 100 : undefined;
};
const ALLY_VIA =new Set(['Buff', 'Aura', 'Sigil', 'Devotion', 'Harmony', "Raguel's passive"]);

// Steps whose values are fractions (0.15 = 15%); everything else is a flat amount.
export const PCT_STEPS = new Set(['statPct', 'affinity', 'conditional', 'continuous', 'proc', 'skillDamage', 'amplify', 'final', 'targetTaken', 'targetMagicTaken']);

export const HERO_DEFAULTS = {
  baseMain: { 100: 697, perLevel: 15 }, adPerMain: 3, adBase: 9, mpPerInt: 5, baseMp: 0,
  hpPerStr: 0, baseHp: 0, critBase: 2,
};

export function buildModel({ items, skills, heroes, effects, sim }) {
  const itemByName = new Map(items.map(i => [i.name, i]));
  const heroByClass = new Map(heroes.map(h => [h.heroClass, h]));
  const curated = sim || {};
  const fxCats = (effects?.sections || []).flatMap(s => s.categories).filter(c => CAT_STEP[c.id]);

  const heroConfig = cls => ({ ...HERO_DEFAULTS, ...(curated.defaults || {}), ...(curated.heroes?.[cls]?.stats || {}) });

  const baseMainAt = (cls, level) => {
    const b = heroConfig(cls).baseMain;
    if (b[level] != null) return b[level];
    return b[100] + (level - 100) * (b.perLevel || 0);
  };

  // Item damage (Atricia's Dream Ender, Grim Scythe's Culling…) from sim.json item "hits"; each only exists
  // while the item is equipped. Item hits aren't skills unless marked.
  const itemHits = Object.entries(curated.items || {}).flatMap(([name, it]) => (it.hits || []).map(h => ({
    isSkill: false, field: 'active', ...h, key: `${name}:${h.key || h.skill}`, item: name, requires: name,
  })));

  function hits(cls) {
    const cur = curated.heroes?.[cls] || {};
    const parsed = parseHeroHits(skills, cls).map(h => ({ ...h, ...(cur.hits?.[h.key] || {}) }));
    return [...parsed, ...(cur.extraHits || []), ...itemHits].filter(h => !h.hidden);
  }

  // Dual-stat heroes swap skills by stat mode: "INT: Changed into Unholy Light" on Phantom Rush means
  // Phantom Rush is the STR-mode skill and Unholy Light the INT-mode one.
  const skillModes = cls => {
    const out = new Map();
    const other = { str: 'int', int: 'str' };
    for (const sk of skills.filter(x => x.heroClass === cls)) {
      for (const line of [...(sk.active || []), ...(sk.passive || [])]) {
        const mm = line.match(/^(STR|INT):\s*Changed (?:to|into)\s+(.+?)\s*$/i);
        if (!mm) continue;
        const mode = mm[1].toLowerCase();
        out.set(sk.name, other[mode]);
        out.set(mm[2], mode);
      }
    }
    return out;
  };
  // Does a passive line change how hard a hit lands? Healing, regen, shields, damage taken, defense
  // and speed lines don't.
  const affectsDamage = line => {
    if (/heal|regen|shield|revive|immun|stealth|movement speed|attack speed|magic defense|charges? \d|store/i.test(line)) return false;
    const rest = line.replace(/(?:reduces?|reduced|decreases?)\s+(?:\w+\s+){0,3}damage(?:\s+(?:taken|received))?|damage\s+(?:taken|received)|received damage/gi, '');
    return /damage|crit|amplif|\b(STR|AGI|INT)\b|main stat|affinity/i.test(rest);
  };
  const curatedSkills = cls => new Set((curated.heroes?.[cls]?.modifiers || []).map(x => x.skill).filter(Boolean));

  // Curated modifiers (data/sim.json) for a hero and the equipped items.
  function curatedMods(cls, gearNames) {
    const out = [];
    for (const m of curated.heroes?.[cls]?.modifiers || []) out.push({ ...m, group: m.group || 'hero', source: { hero: cls, skill: m.skill } });
    for (const m of heroExecutes(skills, cls)) out.push({ ...m, group: 'hero', source: { hero: cls, skill: m.skill } });
    // Skill-text conditionals, except for skills already written up in sim.json.
    for (const m of heroConditionals(skills, cls, curatedSkills(cls))) out.push({ ...m, group: 'hero', source: { hero: cls, skill: m.skill } });
    for (const name of gearNames) {
      for (const m of curated.items?.[name]?.modifiers || []) out.push({ ...m, id: m.id || `${name}:${m.label}`, group: m.group || 'gear', source: { item: name } });
    }
    for (const m of curated.party || []) out.push({ ...m, group: m.group || 'ally', default: m.default ?? false, source: { text: m.label } });
    return out;
  }

  // Effects tab entries as modifiers. Curated items/heroes replace their Effects entries.
  function effectMods(cls, gearNames) {
    const gear = new Set(gearNames);
    const heroSkills = curatedSkills(cls);
    const out = [];
    for (const c of fxCats) {
      const map = CAT_STEP[c.id];
      for (const tp of c.types) {
        tp.entries.forEach((e, i) => {
          if (e.text) return;
          let group;
          if (e.item) {
            if (curated.items?.[e.item]?.modifiers) return;
            if (gear.has(e.item)) group = 'gear';
            else if (map.target) group = 'target';
            else return;
          } else if (e.hero) {
            if (e.hero === cls) { if (heroSkills.has(e.skill)) return; group = 'hero'; }
            else if (map.target) group = 'target';
            // Other heroes' buffs; entries without "via" in buff categories are ally buffs too.
            else if (ALLY_VIA.has(e.via) || !e.via) group = 'ally';
            else return;
          } else return;
          const self = group === 'gear' || group === 'hero';
          const v = parseFxValue(e.value, { self });
          if (!v) return;
          const item = e.item ? itemByName.get(e.item) : null;
          const base = {
            label: e.item || `${e.hero} ${e.key || ''} ${e.skill || ''}`.replace(/\s+/g, ' ').trim(),
            via: e.via, raw: e.value, group, chance: v.chance,
            // "15% vs. enemies below 50% HP" only applies while the target-HP input is under that.
            belowHp: belowHp(e.value),
            fxType: tp.type ? `${c.id}|${tp.type}` : null, cat: c.id,
            source: e.item ? { item: e.item } : { hero: e.hero, skill: e.skill, key: e.key },
            ally: group === 'ally' || (group === 'target' && !!e.hero && e.hero !== cls),
            // "(STR)" / "(INT)" entries only apply in that stat mode (dual-stat heroes like Dark Knight).
            mode: e.hero === cls ? (String(e.value).match(/\((STR|AGI|INT)\b/i)?.[1].toLowerCase() || null) : null,
            // A hero's own ally buffs (Merchant F Scroll, W potion) start off: they're usually cast on someone else.
            default: (group === 'gear' || group === 'hero') && !v.chance && !(e.hero === cls && (ALLY_VIA.has(e.via) || /allies|\(target\)/i.test(e.value))),
          };
          const id = `fx:${c.id}:${tp.type || ''}:${i}`;
          const pctPart = (v.pct || v.pctTerms.length) ? { value: v.pct / 100, formula: v.pctTerms } : null;
          const flatPart = (v.flat || v.flatTerms.length) ? { value: v.flat, scale: v.flatTerms } : null;
          if (map.split) {
            if (flatPart) out.push({ ...base, ...flatPart, id: id + ':flat', step: 'stat', stat: map.stat });
            if (pctPart) out.push({ ...base, ...pctPart, id: id + ':pct', step: 'statPct', stat: map.stat });
            return;
          }
          if (!pctPart) return;
          // Base stats already counted from items.json (e.g. icons' Final Damage) aren't added twice.
          if (item && map.step === 'final' && Math.abs((item.stats?.damagedealtpercent || 0) - pctPart.value) < 1e-9) return;
          if (item && map.step === 'skillDamage' && Math.abs((item.stats?.skilldamagepercent || 0) - pctPart.value) < 1e-9) return;
          out.push({ ...base, ...pctPart, id, step: map.step, stat: map.stat === 'main' && v.onlyStat ? v.onlyStat : map.stat });
        });
      }
    }
    return out;
  }

  // Skills an item swaps in or out (Merchant bags: Throw Bomb, Cursed Doll, Devour…), from sim.json "skillGates".
  function skillAvailable(cls, skill, gearNames) {
    const g = curated.heroes?.[cls]?.skillGates?.[skill];
    if (!g) return true;
    const has = list => [].concat(list).some(r => gearNames.includes(r));
    return (!g.requires || has(g.requires)) && (!g.requiresNot || !has(g.requiresNot));
  }

  function modsFor(cls, gearNames, hit) {
    const modes = skillModes(cls);
    const every = [...curatedMods(cls, gearNames), ...effectMods(cls, gearNames)]
      .map(m => (!m.mode && m.source?.hero === cls && modes.has(m.source.skill) ? { ...m, mode: modes.get(m.source.skill) } : m));
    const all = every.filter(m => (!m.onlyHits || (hit && m.onlyHits.includes(hit.skill))) && (!m.onlyHero || m.onlyHero === cls)
      && !(m.source?.hero === cls && m.source.skill && !skillAvailable(cls, m.source.skill, gearNames)));
    // Every hero passive is listed: ones without any sim effect (or damage part) show as info rows,
    // so it's clear what isn't modelled yet.
    const covered = new Set([...every.map(m => m.source?.hero === cls && m.source.skill).filter(Boolean),
      ...hits(cls).filter(h => h.field === 'passive').map(h => h.skill)]);
    for (const sk of skills.filter(s => s.heroClass === cls && s.passive?.length > 1 && !covered.has(s.name))) {
      all.push({
        id: `passive:${sk.name}`, label: `${sk.name}: ${sk.passive.slice(1).join(' · ')}`, step: 'info', group: 'hero',
        source: { hero: cls, skill: sk.name }, unmodelled: true, mode: modes.get(sk.name) || null,
        // Purely defensive / utility passives (damage taken, healing, mana, speed) can't change a hit.
        defensive: !sk.passive.slice(1).some(affectsDamage),
      });
    }
    // "raises": an item that adds max stacks to another modifier (Crimson Whisper → Storm Shaft charges).
    const byId = new Map(all.map((m, i) => [m.id, i]));
    for (const m of all) for (const r of m.raises || []) {
      const i = byId.get(r.id);
      if (i != null) all[i] = { ...all[i], maxStacks: (all[i].maxStacks || 0) + r.by, raisedBy: [...(all[i].raisedBy || []), m.source?.item || m.label] };
    }
    return all;
  }

  return {
    items, itemByName, heroByClass, curated, heroConfig, baseMainAt, hits, modsFor, skillAvailable,
    heroList: () => heroes.filter(h => h.heroClass && h.mainstat),
    calibration: curated.calibration || [],
  };
}
