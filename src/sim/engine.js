// Single-hit damage engine. Follows the Effects tab's damage formula order:
// base → affinity → conditional → crit → bonus (+) → continuous → proc → skill damage
// → skill amplify → final damage, then the target's damage taken / reductions.
import { PCT_STEPS } from './model.js';

const ELEMENT_KEY = { flame: 'affinityflamepercent', water: 'affinitywaterpercent', wind: 'affinitywindpercent', earth: 'affinityearthpercent', light: 'affinitylightpercent', dark: 'affinitydarkpercent' };
export const ELEMENTS = Object.keys(ELEMENT_KEY);
const STATS3 = ['str', 'agi', 'int'];

const num = v => (v === '' || v == null || Number.isNaN(Number(v)) ? null : Number(v));

// Resolves which modifiers are on, their stack counts and values.
function resolveMods(mods, setupMods = {}) {
  return mods.map(m => {
    const st = setupMods[m.id] || {};
    const on = st.on ?? (m.default ?? true);
    const stacks = m.maxStacks ? Math.max(0, Math.min(m.maxStacks, num(st.stacks) ?? m.stacks ?? m.maxStacks)) : null;
    return { ...m, on, stacks, override: num(st.value) };
  });
}

function modValue(m, stats, allyStat) {
  const pct = PCT_STEPS.has(m.step);
  if (m.override != null) return pct ? m.override / 100 : m.override;
  let v = m.value || 0;
  if (m.perStack) v += m.perStack * (m.stacks ?? 0);
  if (m.atMax && m.maxStacks && m.stacks >= m.maxStacks) v += m.atMax;
  // Execute: scales with the target's missing HP (m.targetHp, 0–1).
  if (m.execute) {
    const ex = m.execute, hp = m.targetHp ?? 1;
    if (ex.below != null) return hp < ex.below ? ex.max : 0;
    const frac = Math.max(0, Math.min(1, (1 - hp) / (1 - (ex.fullAt || 0))));
    return ex.min + (ex.max - ex.min) * frac;
  }
  const statOf = s => (m.ally ? allyStat : (s === 'main' ? stats.main : stats[s] ?? 0));
  for (const f of m.formula || []) v += (f.base + statOf(f.stat) / f.div) / 100;
  for (const f of m.scale || []) v += f.max != null ? Math.min(statOf(f.stat) * f.x, f.max) : statOf(f.stat) * f.x;
  return v;
}

// Same-type Effects entries don't stack: only the strongest active one per type applies.
function applyNoStack(active, stats, allyStat) {
  const best = new Map();
  for (const m of active) {
    if (!m.fxType) continue;
    m._v = modValue(m, stats, allyStat);
    const b = best.get(m.fxType);
    if (!b || m._v > b._v) best.set(m.fxType, m);
  }
  return active.filter(m => {
    if (!m.fxType || best.get(m.fxType) === m) return true;
    m.blocked = best.get(m.fxType).label;
    return false;
  });
}

export function simulate(model, setup) {
  const cls = setup.hero;
  const hero = model.heroByClass.get(cls);
  if (!hero) return null;
  const main = String(hero.mainstat || 'STR').toLowerCase();
  const over = setup.over || {};
  const man = setup.manual || {};
  const cfg = { ...model.heroConfig(cls) };
  for (const k of ['adPerMain', 'mpPerInt', 'hpPerStr', 'critBase']) if (num(over[k]) != null) cfg[k] = num(over[k]);
  const level = num(setup.level) ?? 100;
  const allyStat = num(setup.allyStat) ?? 5000;

  // A skill is made of damage parts (Sword Saint F: 8 pulls + a final slash). Each part has its own
  // hit count, damage type, element and crit; the skill total is the sum of the included parts.
  const hits = model.hits(cls);
  const skills = [...new Set(hits.map(h => h.skill))];
  const skill = skills.includes(setup.skill) ? setup.skill : (hits.find(h => h.key === setup.hit)?.skill || skills[0]);
  if (!skill) return null;
  const partState = setup.parts || {};
  const parts = hits.filter(h => h.skill === skill).map(h0 => {
    const ps = partState[h0.key] || {};
    return {
      ...h0,
      on: ps.on ?? !h0.alt,
      type: ps.type || h0.type,
      element: ps.element ?? h0.element ?? '',
      crit: ps.crit ?? h0.canCrit ?? false,
      count: Math.max(0, num(ps.count) ?? h0.count ?? 1),
      autoCount: h0.count ?? 1,
    };
  });
  const hit = parts.find(p => p.key === setup.focus) || parts.find(p => p.on) || parts[0];

  const gear = Object.entries(setup.gear || {}).map(([slot, name]) => ({ slot, item: name && model.itemByName.get(name) })).filter(g => g.item);
  const gearNames = gear.map(g => g.item.name);
  const mods = resolveMods(model.modsFor(cls, gearNames, hit), setup.mods);
  const targetHp = Math.max(0, Math.min(100, num(setup.targetHp) ?? 100)) / 100;
  for (const m of mods) if (m.execute) m.targetHp = targetHp;
  const on = mods.filter(m => m.on);

  // ── Stats ──
  // Base values (editable on the page) + bonuses from gear, active conditions and manual extras.
  const baseIn = setup.base || {};
  const flat = { str: 0, agi: 0, int: 0, hp: 0, mp: 0, ad: 0 };
  const pct = { str: 0, agi: 0, int: 0, hp: 0, mp: 0, ad: 0 };
  const src = { str: [], agi: [], int: [], hp: [], mp: [], ad: [] };
  const addFlat = (k, v, label) => { if (!v) return; if (k === 'all') return STATS3.forEach(s => addFlat(s, v, label)); if (k === 'main') k = main; flat[k] += v; src[k].push({ label, value: v }); };
  const addPct = (k, v, label) => { if (!v) return; if (k === 'all') return STATS3.forEach(s => addPct(s, v, label)); if (k === 'main') k = main; pct[k] += v; src[k].push({ label, value: v, pct: true }); };

  const baseMain = num(over.baseMain) ?? model.baseMainAt(cls, level);
  const base = {};
  for (const k of STATS3) base[k] = num(baseIn[k]) ?? (k === main ? baseMain : 0);
  for (const { item } of gear) {
    const s = item.stats || {};
    for (const k of STATS3) addFlat(k, s[k], item.name);
    addFlat('all', s.allstat, item.name);
    addFlat('main', s.mainstat, item.name);
    addFlat('hp', s.hp, item.name);
    addFlat('mp', s.mp, item.name);
    addFlat('ad', s.damage, item.name);
  }
  const statMods = on.filter(m => m.step === 'stat' || m.step === 'statPct');
  const pre = Object.fromEntries(STATS3.map(k => [k, base[k] + flat[k]]));
  pre.main = pre[main];
  for (const m of applyNoStack(statMods, pre, allyStat)) {
    const v = modValue(m, pre, allyStat);
    (m.step === 'stat' ? addFlat : addPct)(m.stat || 'main', v, m.label);
  }
  addPct('main', (num(man.mainPct) ?? 0) / 100, 'Manual');

  const stats = {};
  for (const k of STATS3) stats[k] = (base[k] + flat[k]) * (1 + pct[k]);
  stats.main = stats[main];
  // Derived stats: their base follows the base stat; bonus stats add through the same ratio.
  base.ad = num(baseIn.ad) ?? cfg.adPerMain * base[main] + cfg.adBase;
  base.mp = num(baseIn.mp) ?? cfg.baseMp + cfg.mpPerInt * base.int;
  base.hp = num(baseIn.hp) ?? cfg.baseHp + cfg.hpPerStr * base.str;
  const derive = (k, ratio, from, label) => {
    const v = ratio * (stats[from] - base[from]);
    if (v) src[k].unshift({ label, value: v });
    return v;
  };
  stats.ad = (base.ad + derive('ad', cfg.adPerMain, main, `${main.toUpperCase()} bonus × ${cfg.adPerMain}`) + flat.ad) * (1 + pct.ad);
  stats.maxMp = (base.mp + derive('mp', cfg.mpPerInt, 'int', `INT bonus × ${cfg.mpPerInt}`) + flat.mp) * (1 + pct.mp);
  stats.maxHp = (base.hp + derive('hp', cfg.hpPerStr, 'str', `STR bonus × ${cfg.hpPerStr}`) + flat.hp) * (1 + pct.hp);
  const statTable = {
    str: { base: base.str, total: stats.str, sources: src.str },
    agi: { base: base.agi, total: stats.agi, sources: src.agi },
    int: { base: base.int, total: stats.int, sources: src.int },
    ad: { base: base.ad, total: stats.ad, sources: src.ad },
    hp: { base: base.hp, total: stats.maxHp, sources: src.hp },
    mp: { base: base.mp, total: stats.maxMp, sources: src.mp },
  };

  const warnings = [];
  const usesHp = parts.some(p => p.on && p.terms.some(t => t.stat === 'maxHp'));
  if (usesHp && num(baseIn.hp) == null && !cfg.hpPerStr && !cfg.baseHp) warnings.push('maxHp');

  // ── Damage steps ──
  // Each modifier's automatic value (ignoring any typed override), shown as the placeholder on the page.
  for (const m of mods) m.auto = modValue({ ...m, override: null }, stats, allyStat);
  // Stat-mode effects ("STR: …", "If AGI is highest …") apply only when that stat is the hero's highest.
  const heroMode = STATS3.reduce((a, k) => (stats[k] > stats[a] ? k : a), main);
  for (const m of mods) m.modeOff = !!m.mode && m.mode !== heroMode;
  const live = applyNoStack(on.filter(m => m.step !== 'stat' && m.step !== 'statPct' && !m.modeOff), stats, allyStat);
  const byStep = step => live.filter(m => m.step === step).map(m => ({ label: m.label, value: modValue(m, stats, allyStat), id: m.id }));
  const gearStat = key => gear.filter(g => g.item.stats?.[key]).map(g => ({ label: g.item.name, value: g.item.stats[key] }));
  const manualPct = k => (num(man[k]) ? [{ label: 'Manual', value: num(man[k]) / 100 }] : []);
  const sum = list => list.reduce((a, s) => a + s.value, 0);
  const prod = list => list.reduce((a, s) => a * (1 + s.value), 1);

  // One hit of one part, step by step.
  function hitSteps(hit) {
    const steps = [];
    let dmg = 0;
    const push = (id, op, factor, sources, note) => {
      if (op === '×') dmg *= factor;
      else if (op === '+') dmg += factor;
      steps.push({ id, op, factor, sources, value: dmg, note });
    };
    const skip = (id, note) => steps.push({ id, skipped: true, note, value: dmg });

    const termSrc = hit.terms.map(t => (t.flat != null
      ? { label: 'Flat', value: t.flat }
      : { label: `${t.stat} × ${t.x}`, value: (stats[t.stat] ?? 0) * t.x, stat: t.stat, x: t.x }));
    dmg = sum(termSrc);
    steps.push({ id: 'base', op: '=', factor: dmg, sources: termSrc, value: dmg });

    let affFactor = 1;
    if (hit.element) {
      const key = ELEMENT_KEY[hit.element];
      const list = [...gearStat(key), ...gearStat('allaffinitypercent'),
        ...live.filter(m => m.step === 'affinity' && (!m.element || m.element === hit.element || m.element === 'all')).map(m => ({ label: m.label, value: modValue(m, stats, allyStat) })),
        ...manualPct('affinity')];
      affFactor = 1 + sum(list);
      push('affinity', '×', affFactor, list);
    } else skip('affinity', 'noElement');

    const cond = [...byStep('conditional'), ...manualPct('conditional')];
    if (cond.length) push('conditional', '×', prod(cond), cond); else skip('conditional', 'none');

    if (hit.crit) {
      const list = [{ label: 'Base', value: cfg.critBase }, ...gearStat('critmultiplier'), ...byStep('critMult'),
        ...(num(man.critMult) ? [{ label: 'Manual', value: num(man.critMult) }] : [])];
      push('crit', '×', sum(list), list);
    } else skip('crit', 'noCrit');

    // Bonus damage marked "affinity" (e.g. Primal Shard's Eternal Frost) is scaled by the hit's affinity.
    const bonus = [...live.filter(m => m.step === 'bonus').map(m => {
      const v = modValue(m, stats, allyStat);
      return m.affinity && affFactor !== 1 ? { label: `${m.label} × affinity ${+affFactor.toFixed(4)}`, value: v * affFactor } : { label: m.label, value: v };
    }), ...(num(man.bonus) ? [{ label: 'Manual', value: num(man.bonus) }] : [])];
    if (bonus.length) push('bonus', '+', sum(bonus), bonus); else skip('bonus', 'none');

    if (hit.continuous) { const l = [...gearStat('periodicdamagepercent'), ...byStep('continuous')]; push('continuous', '×', 1 + sum(l), l); }
    else skip('continuous', 'notContinuous');
    if (hit.proc) { const l = [...gearStat('procdamagepercent'), ...byStep('proc')]; push('proc', '×', 1 + sum(l), l); }
    else skip('proc', 'notProc');

    if (hit.isSkill) {
      const sd = [...gearStat('skilldamagepercent'), ...byStep('skillDamage'), ...manualPct('skillDamage')];
      push('skillDamage', '×', 1 + sum(sd), sd);
      const amp = [...byStep('amplify'), ...manualPct('amplify')];
      if (amp.length) push('amplify', '×', prod(amp), amp); else skip('amplify', 'none');
    } else { skip('skillDamage', 'notSkill'); skip('amplify', 'notSkill'); }

    const fin = [...gearStat('damagedealtpercent'), ...byStep('final'), ...manualPct('final')];
    if (fin.length) push('final', '×', prod(fin), fin); else skip('final', 'none');

    const beforeTarget = dmg;
    const taken = [...byStep('targetTaken'), ...manualPct('targetTaken')];
    if (taken.length) push('targetTaken', '×', 1 + sum(taken), taken); else skip('targetTaken', 'none');
    if (hit.type === 'magic') {
      const mt = [...byStep('targetMagicTaken'), ...manualPct('targetMagicTaken')];
      if (mt.length) push('targetMagicTaken', '×', 1 + sum(mt), mt); else skip('targetMagicTaken', 'none');
    } else skip('targetMagicTaken', 'notMagic');
    const dr = num(man.targetDR);
    if (dr) push('targetDR', '×', 1 - dr / 100, [{ label: 'Manual', value: -dr / 100 }]); else skip('targetDR', 'none');
    const md = num(man.targetMD);
    if (hit.type === 'magic' && md) push('targetMD', '×', 1 - md / 100, [{ label: 'Manual', value: -md / 100 }]);
    else skip('targetMD', hit.type === 'pure' ? 'pure' : (hit.type === 'magic' ? 'none' : 'notMagic'));

    return { steps, perHit: dmg, beforeTarget };
  }

  // Multi-hit: every hit of a part is calculated the same way, then multiplied by its hit count.
  for (const p of parts) {
    Object.assign(p, hitSteps(p));
    p.subtotal = p.perHit * p.count;
    p.subBefore = p.beforeTarget * p.count;
  }
  const included = parts.filter(p => p.on);
  const total = included.reduce((a, p) => a + p.subtotal, 0);
  const beforeTarget = included.reduce((a, p) => a + p.subBefore, 0);
  return { skill, skills, hit, parts, hits, stats, statTable, main, cfg, baseMain, mods, steps: hit.steps, beforeTarget, total, warnings };
}
