// Single-hit damage engine. Follows the Effects tab's damage formula order:
// base → affinity → conditional → crit → bonus (+) → continuous → proc → skill damage
// → skill amplify → final damage, then the target's damage taken / reductions.
import { PCT_STEPS } from './model.js';

const ELEMENT_KEY = { flame: 'affinityflamepercent', water: 'affinitywaterpercent', wind: 'affinitywindpercent', earth: 'affinityearthpercent', light: 'affinitylightpercent', dark: 'affinitydarkpercent' };
export const ELEMENTS = Object.keys(ELEMENT_KEY);
const STATS3 = ['str', 'agi', 'int'];

const fmtNum = n => Math.round(n).toLocaleString('en-US');
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
  if (m.belowHp != null && (m.targetHp ?? 1) >= m.belowHp) return 0;
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
  for (const f of m.scale || []) {
    // { affinity: 'flame', x } scales with that element's total affinity (fraction).
    const base = f.affinity ? (stats.aff?.[f.affinity] ?? 0) : statOf(f.stat);
    v += f.max != null ? Math.min(base * f.x, f.max) : base * f.x;
  }
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
  // The main stat can be switched on the page (Knight / Dark Knight / Paladin INT builds).
  const main = ['str', 'agi', 'int'].includes(setup.main) ? setup.main : String(hero.mainstat || 'STR').toLowerCase();
  const over = setup.over || {};
  const man = setup.manual || {};
  const cfg = { ...model.heroConfig(cls) };
  for (const k of ['adPerMain', 'mpPerInt', 'hpPerStr', 'critBase']) if (num(over[k]) != null) cfg[k] = num(over[k]);
  const level = num(setup.level) ?? 100;
  const allyStat = num(setup.allyStat) ?? 5000;

  // A skill is made of damage parts (Sword Saint F: 8 pulls + a final slash). Each part has its own
  // hit count, damage type, element and crit; the skill total is the sum of the included parts.
  const gear = Object.entries(setup.gear || {}).map(([slot, name]) => ({ slot, item: name && model.itemByName.get(name) })).filter(g => g.item);
  const gearNames = gear.map(g => g.item.name);
  // Parts tied to an item ("requires": Soul Rift's bomb mark, Soul Bomb) only exist while it's equipped.
  const has = list => [].concat(list).some(r => gearNames.includes(r));
  const hits = model.hits(cls).filter(h => (!h.requires || has(h.requires)) && (!h.requiresNot || !has(h.requiresNot))
    && model.skillAvailable(cls, h.skill, gearNames));
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
  // Riders (Fire Mage Burn, Wings of the Void): extra damage a hero hit leaves behind, a share of that hit's damage.
  // "perCast" riders (Cape of Deep Abyss) trigger once per skill cast, on its first included part.
  for (const r of model.riders(cls, gearNames)) {
    const heroParts = parts.filter(p => !p.item && !p.riderOf && (!r.skillsOnly || p.isSkill));
    for (const parent of r.perCast ? heroParts.filter(p => p.on).slice(0, 1) : heroParts) {
      const key = `${parent.key}~${r.id}`;
      const ps = partState[key] || {};
      const auto = r.perCast ? 1 : parent.count;
      parts.push({
        key, skill, rider: r, riderOf: parent.key, label: r.label, line: r.line, terms: [], icon: parent.icon, source: r.source,
        on: parent.on && (ps.on ?? true), type: ps.type || r.type || parent.type, element: '', crit: false,
        continuous: !!r.continuous, isSkill: false, count: Math.max(0, num(ps.count) ?? auto), autoCount: auto,
      });
    }
  }
  const hit = parts.find(p => p.key === setup.focus) || parts.find(p => p.on) || parts[0];

  // Summons that store damage (Merchant's Cursed Doll): "damage taken" is what you put into it, counted
  // `own` times for your own damage. Defaults to your total for the skill named in the term (e.g. Throw Bomb).
  let stored = null;
  const storedDamage = term => {
    if (stored == null) {
      const typed = num(setup.stored);
      // Without a `from` skill there's nothing to default to: the stored amount must be typed.
      stored = typed ?? (setup._noStored || !term.from ? 0 : (simulate(model, { ...setup, skill: term.from, focus: '', _noStored: true })?.total ?? 0));
    }
    return stored;
  };
  const mods = resolveMods(model.modsFor(cls, gearNames, hit), setup.mods);
  const targetHp = Math.max(0, Math.min(100, num(setup.targetHp) ?? 100)) / 100;
  for (const m of mods) if (m.execute || m.belowHp != null) m.targetHp = targetHp;
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
  // Base stats stay with the hero's own primary attribute; switching the primary only moves its
  // 3 damage per point (and "main stat" effects) to the chosen stat.
  const ownMain = String(hero.mainstat || 'STR').toLowerCase();
  for (const k of STATS3) base[k] = num(baseIn[k]) ?? (k === ownMain ? baseMain : 0);
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
  // Max HP before stat buffs, for HP-scaled stat effects (Righteous Flame's Holy Fire).
  pre.maxHp = (num(baseIn.hp) ?? cfg.baseHp + cfg.hpPerStr * base.str) + cfg.hpPerStr * flat.str + flat.hp;
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
  const gearStat = key => gear.filter(g => g.item.stats?.[key]).map(g => ({ label: g.item.name, value: g.item.stats[key] }));
  const manualPct = k => (num(man[k]) ? [{ label: 'Manual', value: num(man[k]) / 100 }] : []);
  const sum = list => list.reduce((a, s) => a + s.value, 0);
  const prod = list => list.reduce((a, s) => a * (1 + s.value), 1);
  // Stat-mode effects ("STR: …", "If AGI is highest …") apply only when that stat is the hero's highest.
  const heroMode = STATS3.reduce((a, k) => (stats[k] > stats[a] ? k : a), main);
  for (const m of mods) m.modeOff = !!m.mode && m.mode !== heroMode;
  // Affinity totals per element, for "if fire affinity is higher" effects (Akhelius) and affinity-scaled values.
  const affList = (el, from) => [...gearStat(ELEMENT_KEY[el]), ...gearStat('allaffinitypercent'),
    ...from.filter(m => m.step === 'affinity' && (!m.element || m.element === el || m.element === 'all')).map(m => ({ label: m.label, value: modValue(m, stats, allyStat) })),
    ...manualPct('affinity')];
  const plain = on.filter(m => m.step === 'affinity' && !m.modeOff && !m.ifHigher);
  stats.aff = Object.fromEntries(ELEMENTS.map(el => [el, sum(affList(el, plain))]));
  for (const m of mods) if (m.ifHigher) m.modeOff = m.ifHigher.some(o => (m.tieLoses ? stats.aff[o] >= stats.aff[m.ifElement] : stats.aff[o] > stats.aff[m.ifElement]));
  stats.aff = Object.fromEntries(ELEMENTS.map(el => [el, sum(affList(el, [...plain, ...on.filter(m => m.step === 'affinity' && m.ifHigher && !m.modeOff)]))]));
  // Each modifier's automatic value (ignoring any typed override), shown as the placeholder on the page.
  for (const m of mods) m.auto = modValue({ ...m, override: null }, stats, allyStat);
  const live = applyNoStack(on.filter(m => m.step !== 'stat' && m.step !== 'statPct' && !m.modeOff), stats, allyStat);
  const byStep = step => live.filter(m => m.step === step).map(m => ({ label: m.label, value: modValue(m, stats, allyStat), id: m.id }));

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

    // "INT X (5 + LV / 4)": xPerLevel adds to the coefficient per hero level.
    const termStat = t => {
      const x = +(t.x + (t.xPerLevel || 0) * level).toFixed(4);
      return { label: `${t.stat} × ${x}`, value: (stats[t.stat] ?? 0) * x, stat: t.stat, x };
    };
    // A rider's base is its share of the parent hit (before target effects), with a stat floor.
    const R = hit.rider;
    const parent = R && parts.find(p => p.key === hit.riderOf);
    const termSrc = R ? [(() => {
      const share = R.of * (parent?.beforeTarget ?? 0);
      const floor = sum((R.min || []).map(termStat));
      return floor > share
        ? { label: `${R.label}: ${(R.min || []).map(t => `${t.stat} × ${t.x}`).join(' + ')} (minimum)`, value: floor }
        : { label: `${+(R.of * 100).toFixed(2)}% × ${fmtNum(parent?.beforeTarget ?? 0)}`, value: share };
    })()] : hit.terms.map(t => (t.flat != null
      ? { label: 'Flat', value: t.flat }
      : t.stored
        ? { label: t.label || 'Stored damage', value: storedDamage(t) * (t.own ?? 1) * t.x, stored: true }
        : termStat(t)));
    dmg = sum(termSrc);
    steps.push({ id: 'base', op: '=', factor: dmg, sources: termSrc, value: dmg });

    let affFactor = 1;
    // Riders copy an already-multiplied hit: only continuous damage and the target's steps apply.
    if (R) for (const id of ['affinity', 'conditional', 'crit', 'bonus']) skip(id, 'rider');
    else if (hit.element) {
      const list = affList(hit.element, live);
      affFactor = 1 + sum(list);
      push('affinity', '×', affFactor, list);
    } else skip('affinity', 'noElement');

    // Chain stacks (Merchant bombs): hit k of n gets min(k, max) stacks; the part uses the average.
    const chainAvg = (m, n) => {
      const c = Math.max(1, Math.round(n));
      let sumStacks = 0;
      for (let k = 0; k < c; k++) sumStacks += Math.min(k, m.chain.maxStacks);
      return m.chain.per * sumStacks / c;
    };
    // "+0% / +75% / +150% / +225% / +300% …" per hit, so the cap is visible.
    const chainLabel = (m, n) => {
      const c = Math.max(1, Math.round(n));
      const per = Array.from({ length: Math.min(c, m.chain.maxStacks + 2) }, (_, k) => `+${Math.round(Math.min(k, m.chain.maxStacks) * m.chain.per * 100)}%`);
      return `${m.label}: ${per.join(' / ')}${c > per.length ? ' …' : ''} → avg over ${c} hits`;
    };
    const cond = [...live.filter(m => m.step === 'conditional' && (!m.onlyParts || m.onlyParts.includes(hit.key))).map(m => ({
      label: m.chain ? chainLabel(m, hit.count) : m.label,
      value: m.chain && m.override == null ? chainAvg(m, hit.count) : modValue(m, stats, allyStat), id: m.id,
    })), ...manualPct('conditional')];
    if (R) { /* skipped above */ } else if (cond.length) push('conditional', '×', prod(cond), cond); else skip('conditional', 'none');

    if (R) { /* skipped above */ } else if (hit.crit) {
      const list = [{ label: 'Base', value: cfg.critBase }, ...gearStat('critmultiplier'), ...byStep('critMult'),
        ...(num(man.critMult) ? [{ label: 'Manual', value: num(man.critMult) }] : [])];
      push('crit', '×', sum(list), list);
    } else skip('crit', 'noCrit');

    // Bonus damage marked "affinity" (e.g. Primal Shard's Eternal Frost) is scaled by the hit's affinity.
    // Bonus damage can be limited to a damage type ("when dealing magic damage").
    const bonus = [...live.filter(m => m.step === 'bonus' && (!m.onlyTypes || m.onlyTypes.includes(hit.type))).map(m => {
      const v = modValue(m, stats, allyStat);
      return m.affinity && affFactor !== 1 ? { label: `${m.label} × affinity ${+affFactor.toFixed(4)}`, value: v * affFactor } : { label: m.label, value: v };
    }), ...(num(man.bonus) ? [{ label: 'Manual', value: num(man.bonus) }] : [])];
    if (R) { /* skipped above */ } else if (bonus.length) push('bonus', '+', sum(bonus), bonus); else skip('bonus', 'none');

    if (hit.continuous) { const l = [...gearStat('periodicdamagepercent'), ...byStep('continuous')]; push('continuous', '×', 1 + sum(l), l); }
    else skip('continuous', 'notContinuous');
    if (hit.proc) { const l = [...gearStat('procdamagepercent'), ...byStep('proc')]; push('proc', '×', 1 + sum(l), l); }
    else skip('proc', 'notProc');

    if (hit.isSkill) {
      const sd = [...gearStat('skilldamagepercent'), ...byStep('skillDamage'), ...manualPct('skillDamage')];
      push('skillDamage', '×', 1 + sum(sd), sd);
      const amp = [...byStep('amplify'), ...manualPct('amplify')];
      if (amp.length) push('amplify', '×', prod(amp), amp); else skip('amplify', 'none');
    } else { skip('skillDamage', R ? 'rider' : 'notSkill'); skip('amplify', R ? 'rider' : 'notSkill'); }

    const fin = [...gearStat('damagedealtpercent'), ...byStep('final'), ...manualPct('final')];
    if (R) skip('final', 'rider'); else if (fin.length) push('final', '×', prod(fin), fin); else skip('final', 'none');

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
  // Parents first: riders read their parent's damage.
  for (const p of [...parts.filter(x => !x.rider), ...parts.filter(x => x.rider)]) {
    Object.assign(p, hitSteps(p));
    p.subtotal = p.perHit * p.count;
    p.subBefore = p.beforeTarget * p.count;
  }
  const included = parts.filter(p => p.on);
  const total = included.reduce((a, p) => a + p.subtotal, 0);
  const beforeTarget = included.reduce((a, p) => a + p.subBefore, 0);
  return { skill, skills, hit, parts, hits, stored, stats, statTable, main, cfg, baseMain, mods, steps: hit.steps, beforeTarget, total, warnings };
}
