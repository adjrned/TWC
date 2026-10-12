// Hero skills (data/skills.json): shared loader plus lookups used by skill tooltips
// on the Effects tab and in patch notes.

let skillsPromise = null;
let skills = [];

export function loadSkills() {
  if (!skillsPromise) {
    skillsPromise = fetch('data/skills.json')
      .then(r => (r.ok ? r.json() : []))
      .catch(() => [])
      .then(list => (skills = list));
  }
  return skillsPromise;
}

// "[R] → [R] → [Q]" / "[D] -> [Q]" / "[Passive]" → ['R', 'R', 'Q'] / ['D', 'Q'] / ['Passive']
export function hotkeyPath(hotkey) {
  return String(hotkey || '').match(/Passive|[A-Z]/g) || [];
}

export function getSkill(heroClass, name) {
  return skills.find(s => s.heroClass === heroClass && s.name === name) || null;
}

// Patch notes write abilities as hotkey prefixes ("TQ", "RRQ", "W3" = W→W→W) or by name
// ("Flame Shot (Q)", "Magnetic Field - …"). Returns the matching skill and the matched text.
export function skillFromNote(heroClass, line) {
  const own = skills.filter(s => s.heroClass === heroClass);
  if (!own.length) return null;
  const lower = line.toLowerCase();
  // Longest name first, so "Power Enchant - allies only" wins over "Power Enchant".
  for (const s of [...own].sort((a, b) => b.name.length - a.name.length)) {
    const n = s.name.toLowerCase();
    if (lower.startsWith(n) && /^($|[\s(:\-–])/.test(line.slice(n.length))) return { skill: s, text: line.slice(0, s.name.length) };
  }
  const m = line.match(/^([A-Z]{1,4})(\d)?(?=\s*(?:\([^)]*\))?\s*(?:[-–:]|$))/);
  if (!m) return null;
  let keys = m[1].split('');
  if (m[2]) keys = Array(Number(m[2])).fill(keys[0]);
  const hit = own.filter(s => {
    const p = hotkeyPath(s.hotkey);
    return p.length === keys.length && p.every((k, i) => k === keys[i]);
  }).sort((a, b) => (a.order || 0) - (b.order || 0))[0];
  return hit ? { skill: hit, text: m[0] } : null;
}
