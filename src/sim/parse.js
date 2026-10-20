// Text parsers for the damage sim: skill damage lines (data/skills.json) and
// Effects tab values (data/effects.json). Pure functions, shared by the page and node scripts.

const STAT_WORDS = [
  [/^(attack damage|attack power)$/i, 'ad'],
  [/^(agi|agility)$/i, 'agi'],
  [/^(str|strength)$/i, 'str'],
  [/^(int|intelligence)$/i, 'int'],
  [/^(main stat|primary stat)$/i, 'main'],
  [/^max(imum)? (mp|mana)$/i, 'maxMp'],
  [/^max(imum)? (hp|health)$/i, 'maxHp'],
];
const STAT_ALT = 'Attack Damage|Attack Power|Agility|Strength|Intelligence|Main Stat|Primary Stat|Max(?:imum)? MP|Max(?:imum)? Mana|Max(?:imum)? HP|Max(?:imum)? Health|AGI|STR|INT';
// Coefficients may be ranges ("X 2~4", based on hero level); the sim uses the top of the range.
const NUM = String.raw`\d+(?:\.\d+)?(?:\s*~\s*\d+(?:\.\d+)?)?`;
const MUL = String.raw`\s*[X×x]\s*`;
// A term is "STAT X n", a group "(STR + INT) X n", or a flat number.
const TERM = String.raw`(?:\((?:${STAT_ALT})(?:\s*\+\s*(?:${STAT_ALT}))+\)${MUL}${NUM}|(?:${STAT_ALT})${MUL}${NUM}%?|\d[\d,]*(?:\.\d+)?(?![\d%~]))`;
// An aside may sit between the formula and "damage": "X 2~4 (based on hero level) bonus damage".
const DAMAGE_RE = new RegExp(String.raw`(${TERM}(?:\s*\+\s*${TERM})*)(?:\s*\([^)]*\))?\s*(bonus\s+)?(?:(magic|physical|pure)\s+)?damage`, 'gi');
const GROUP_RE = new RegExp(String.raw`^\(([^)]*)\)${MUL}(${NUM})$`, 'i');
const SINGLE_RE = new RegExp(String.raw`^(${STAT_ALT})${MUL}(${NUM})(%)?$`, 'i');

export function statKey(word) {
  const w = word.trim().replace(/\s+/g, ' ');
  for (const [re, key] of STAT_WORDS) if (re.test(w)) return key;
  return null;
}

const coef = str => Math.max(...str.split('~').map(Number));

// Splits on "+" outside parentheses.
function topLevelParts(expr) {
  const parts = [];
  let depth = 0, cur = '';
  for (const ch of expr) {
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === '+' && depth === 0) { parts.push(cur); cur = ''; } else cur += ch;
  }
  parts.push(cur);
  return parts;
}

// "Attack Damage X 1 + AGI X 4" → [{stat:'ad', x:1}, {stat:'agi', x:4}]; "40000" → [{flat:40000}];
// "(STR + INT) X 9" → [{stat:'str', x:9}, {stat:'int', x:9}]
export function parseTerms(expr) {
  const out = [];
  for (const raw of topLevelParts(expr)) {
    const part = raw.trim();
    const g = part.match(GROUP_RE);
    if (g) {
      for (const st of g[1].split('+')) {
        const k = statKey(st);
        if (!k) return null;
        out.push({ stat: k, x: coef(g[2]) });
      }
      continue;
    }
    const m = part.match(SINGLE_RE);
    if (m) { out.push({ stat: statKey(m[1]), x: coef(m[2]) / (m[3] ? 100 : 1) }); continue; }
    const n = part.replace(/,/g, '');
    if (/^\d+(\.\d+)?$/.test(n)) { out.push({ flat: Number(n) }); continue; }
    return null;
  }
  return out;
}

const MULTI_WORDS = 'strikes|slashes|arrows|hits|bolts|waves|projectiles|blades|meteors|swords|explosions|shots|missiles|shards|comets|attacks|spears|lances|daggers|knives|bullets|beams|rockets|fireballs|blasts|stars|souls|spirits|pillars|thorns|feathers|cards|coins|bombs|grenades|punches|kicks|stabs';
const MULTI_RE = new RegExp(String.raw`\b(\d+)\s+(?:[a-z]+\s+){0,2}(?:${MULTI_WORDS})\b`, 'i');

// How many times a damage line hits, read from the same line:
// "Calls down 12 lightning strikes … each dealing" → 12, "Slashes 3 times, each" → 3,
// "per second for 8 seconds" → 8, "every 0.125 seconds" for 1 second → 8. Defaults to 1.
export function hitCount(line) {
  const times = line.match(/(\d+)\s+(?:additional\s+)?times,?\s+each/i)
    || line.match(/damage\s+(\d+)\s+times/i)
    || line.match(/strikes?\s+(\d+)\s+additional\s+times/i);
  if (times) return Number(times[1]);
  const n = line.match(MULTI_RE);
  if (n) return Number(n[1]);
  const dur = line.match(/for\s+(?:up to\s+)?(\d+(?:\.\d+)?)\s+seconds?/i) || line.match(/over\s+(\d+(?:\.\d+)?)\s+seconds?/i);
  if (dur) {
    const every = line.match(/every\s+(\d+(?:\.\d+)?)\s+seconds?/i);
    if (every) return Math.max(1, Math.floor(Number(dur[1]) / Number(every[1]) + 1e-9));
    // Damage per second × duration ("per second for 2.5 seconds" → 2.5).
    if (/per second|every second/i.test(line)) return Math.max(1, Number(dur[1]));
  }
  return 1;
}

// All damage hits in one skill description line.
export function parseDamageLine(line) {
  const hits = [];
  DAMAGE_RE.lastIndex = 0;
  let m;
  while ((m = DAMAGE_RE.exec(line))) {
    // Shields and reductions ("Absorbs up to INT X 0.5 damage") aren't hits.
    if (/absorb|shield|reduc|heal/i.test(line.slice(0, m.index))) continue;
    const terms = parseTerms(m[1]);
    // A lone flat number ("deals 3 damage") is too ambiguous unless it's big enough to be a real hit.
    if (!terms || (terms.length === 1 && terms[0].flat != null && terms[0].flat < 100)) continue;
    const rest = line.slice(m.index + m[0].length);
    hits.push({
      terms,
      type: (m[3] || 'physical').toLowerCase(),
      bonus: !!m[2],
      continuous: /^\s*(per second|every|over\b)/i.test(rest) || /continuously|per second/i.test(line),
      count: hitCount(line),
    });
  }
  return hits;
}

const FIELDS = ['active', 'toggle', 'passive'];

// Every parseable damage part of a hero, keyed "<skill name>#<n>" (n counts parts within the skill).
// A skill's total is the sum of its parts (each part × its hit count); `alt` parts start excluded.
export function parseHeroHits(skills, heroClass) {
  const out = [];
  for (const sk of skills.filter(s => s.heroClass === heroClass).sort((a, b) => (a.order || 0) - (b.order || 0))) {
    let n = 0;
    const start = out.length;
    for (const field of FIELDS) {
      for (const line of sk[field] || []) {
        for (const h of parseDamageLine(line)) {
          out.push({
            key: `${sk.name}#${n++}`, skill: sk.name, hotkey: sk.hotkey, icon: sk.icon, field, line, ...h,
            // "Counts as basic attack" (Sniper Glide, Lightseeker Light Dash) only means it triggers
            // on-hit effects; the hit is still a skill for skill damage / amplify.
            isSkill: true,
            proc: field === 'passive' && /attack/i.test(line),
            // Passives and alternative modes ("If enhanced by…", "Empowered:", "STR: …") start excluded.
            alt: field === 'passive' || /^(if enhanced|empowered:|(str|agi|int):)/i.test(line),
          });
        }
      }
    }
    // "Last slash deals double damage": one extra hit's worth on the multi-hit part.
    const lines = FIELDS.flatMap(f => sk[f] || []);
    if (lines.some(l => /\blast \w+ deals double damage/i.test(l))) {
      const multi = out.slice(start).find(h => h.count > 1);
      if (multi) { multi.count += 1; multi.countNote = 'lastDouble'; }
    }
  }
  return out;
}

// Execute effects: bonus damage that scales with the target's missing HP.
// "up to 40% bonus damage based on target's missing HP (max damage reached at 40% HP)",
// "by 15~35% based on target's missing HP", "100% bonus damage to enemies below 40% HP".
// Returns { min, max, fullAt, below, final } as fractions, or null. Own-HP effects ("based on missing HP"
// without target/enemy) aren't executes.
export function parseExecute(line) {
  const below = line.match(/(\d+(?:\.\d+)?)%\s+bonus damage to enemies below (\d+(?:\.\d+)?)% HP/i);
  if (below) return { min: 0, max: Number(below[1]) / 100, below: Number(below[2]) / 100, final: false };
  if (!/(target's|enemy's|enemies'?) (missing (hp|health)|lost health)/i.test(line)) return null;
  const by = line.match(/by (\d+(?:\.\d+)?)\s*~\s*(\d+(?:\.\d+)?)%/i);
  const upTo = line.match(/up to (\d+(?:\.\d+)?)(?:\s*~\s*(\d+(?:\.\d+)?))?%/i);
  if (!by && !upTo) return null;
  const min = by ? Number(by[1]) / 100 : 0;
  const max = Number(by ? by[2] : upTo[2] || upTo[1]) / 100;
  const full = line.match(/max damage reached at (\d+(?:\.\d+)?)% HP/i);
  return { min, max, fullAt: full ? Number(full[1]) / 100 : 0, final: /increases damage you deal/i.test(line) };
}

// Execute modifiers for one hero, read from its skill text.
export function heroExecutes(skills, heroClass) {
  const out = [];
  for (const sk of skills.filter(s => s.heroClass === heroClass)) {
    for (const field of FIELDS) for (const line of sk[field] || []) {
      const ex = parseExecute(line);
      if (!ex) continue;
      out.push({
        id: `exec:${sk.name}`, label: line.replace(/^(empowered|str|agi|int):\s*/i, ''), skill: sk.name,
        step: ex.final ? 'final' : 'conditional', execute: ex,
        // A skill's own execute applies to that skill; "increases damage you deal" is a buff for everything.
        onlyHits: ex.final ? undefined : [sk.name],
      });
    }
  }
  return out;
}

// Damage lines a hero has that the parser can't read (for the coverage report).
export function unparsedDamageLines(skills) {
  const out = [];
  for (const sk of skills) for (const field of FIELDS) for (const line of sk[field] || []) {
    if (/damage/i.test(line) && /\b(deals?|dealing)\b/i.test(line) && !parseDamageLine(line).length) {
      out.push({ hero: sk.heroClass, skill: sk.name, hotkey: sk.hotkey, line });
    }
  }
  return out;
}

const STAT_FX = 'STR|AGI|INT|Main Stat|MAIN STAT';
const fxStat = s => statKey(s) || null;

// Effects tab value text → { pct, pctTerms, flat, flatTerms, onlyStat, chance }.
// pct values are percent numbers (15 = 15%). `self` picks "(8% self)" variants.
export function parseFxValue(raw, { self = false } = {}) {
  if (!raw) return null;
  let s = String(raw);
  const chance = /chance/i.test(s);
  const selfM = s.match(/\((\d+(?:\.\d+)?)% self\)/i);
  if (self && selfM) s = selfM[1] + '%';
  // "3% (6% active)": the sim assumes perfect conditions, so the active value wins.
  const activeM = s.match(/\((\d+(?:\.\d+)?)% active\)/i);
  if (activeM) s = activeM[1] + '%';
  const max = s.match(/\((?:max|up to)\s*(\d+(?:\.\d+)?)%\)/i);
  if (max && /per\b/i.test(s)) s = max[1] + '%';
  const times = s.match(/per (?:stack|sword)[^(]*\(×(\d+)\)/i);
  s = s.replace(/^up to\s*/i, '').replace(/(\d+(?:\.\d+)?)\s*[–-]\s*(\d+(?:\.\d+)?)%/, '$2%');
  const out = { pct: 0, pctTerms: [], flat: 0, flatTerms: [], onlyStat: null, chance };
  const lead = s.match(new RegExp(`^(${STAT_FX})\\s+(?=\\d)`, 'i'));
  if (lead) { out.onlyStat = fxStat(lead[1]); s = s.slice(lead[0].length); }
  // Cut trailing notes like "(target)", "vs. target", "(10% chance)".
  s = s.replace(/\s*\((?!max)(?![^)]*[/×])[^)]*\)/g, '').replace(/\s+(vs\.|on|for|at|when|while|in|per)\b.*$/i, '');
  let found = false;
  s = s.replace(new RegExp(`\\(\\s*(\\d+(?:\\.\\d+)?)\\s*\\+\\s*(${STAT_FX})\\s*\\/\\s*(\\d+)\\s*\\)%`, 'gi'), (_, b, st, d) => {
    out.pctTerms.push({ base: Number(b), stat: fxStat(st), div: Number(d) }); found = true; return '';
  });
  s = s.replace(new RegExp(`\\(\\s*(${STAT_FX})\\s*\\/\\s*(\\d+)\\s*\\)%`, 'gi'), (_, st, d) => {
    out.pctTerms.push({ base: 0, stat: fxStat(st), div: Number(d) }); found = true; return '';
  });
  s = s.replace(new RegExp(`(${STAT_FX})\\s*×\\s*(\\d+(?:\\.\\d+)?)(?:\\s*\\(max\\s*([\\d,]+)\\))?`, 'gi'), (_, st, x, mx) => {
    out.flatTerms.push({ stat: fxStat(st), x: Number(x), max: mx ? Number(mx.replace(/,/g, '')) : null }); found = true; return '';
  });
  s = s.replace(/(\d+(?:\.\d+)?)×/, (_, x) => { out.pct += (Number(x) - 1) * 100; found = true; return ''; });
  s = s.replace(/(\d+(?:\.\d+)?)%/g, (_, n) => { out.pct += Number(n); found = true; return ''; });
  s = s.replace(/\+?\s*(\d[\d,]*(?:\.\d+)?)/g, (_, n) => { out.flat += Number(n.replace(/,/g, '')); found = true; return ''; });
  if (times) out.pct *= Number(times[1]);
  return found ? out : null;
}
