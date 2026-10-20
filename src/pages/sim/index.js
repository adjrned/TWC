import { esc } from '../../ui/escape.js';
import { t, getClassName } from '../../i18n.js';
import { loadItems, getItem, rankInfo, localizedNameByName, iconSrc } from '../../data/items.js';
import { loadSkills, getSkill } from '../../data/skills.js';
import { iconHtml, bindItemHover } from '../../ui/itemUi.js';
import { slotIcon } from '../../ui/slotIcons.js';
import { openItemPicker, EQUIP_TABS, ALL_TAB } from '../../ui/itemPicker.js';
import { state } from '../../state.js';
import { ROSTER, classIconPath } from '../../constants.js';
import { load as loadPlanner } from '../../data/storage.js';
import { fetchCreatorsForClass } from '../../data/builds.js';
import { fetchBuild } from '../builder/buildBrowser.js';
import { buildModel, GEAR_SLOTS, PCT_STEPS } from '../../sim/model.js';
import { simulate, ELEMENTS } from '../../sim/engine.js';

const STORE_KEY = 'simState';
const SLOT_TAB = { weapon: 'weapon', helm: 'headwear', body: 'armor', wings: 'wings', accessory: 'accessory', icon: 'all' };
const SLOT_ICON = { weapon: 'weapon', helm: 'helm', body: 'body', wings: 'wings', accessory: 'accessory', icon: 'all' };
const STAT_LABEL = { str: 'STR', agi: 'AGI', int: 'INT', ad: 'Attack Damage', maxMp: 'Max MP', maxHp: 'Max HP', main: 'Main Stat' };
const GROUPS = ['hero', 'gear', 'ally', 'target'];

// Manual adjustments: [key, kind] — 'flat' adds an amount, 'pct' a percent.
const MANUAL = {
  stats: [['mainPct', 'pct']],
  damage: [['affinity', 'pct'], ['conditional', 'pct'], ['critMult', 'flat'], ['bonus', 'flat'], ['skillDamage', 'pct'], ['amplify', 'pct'], ['final', 'pct']],
  target: [['targetTaken', 'pct'], ['targetMagicTaken', 'pct'], ['targetDR', 'pct'], ['targetMD', 'pct']],
};
const CONVERSIONS = ['adPerMain', 'mpPerInt', 'hpPerStr', 'critBase'];
const STAT_ROWS = [['str', 'STR'], ['agi', 'AGI'], ['int', 'INT'], ['ad', 'Attack Damage'], ['hp', 'Max HP'], ['mp', 'Max MP']];

let model = null;

async function loadModel() {
  if (model) return model;
  const get = f => fetch(f).then(r => (r.ok ? r.json() : null)).catch(() => null);
  const [items, skills, heroes, effects, sim] = await Promise.all([loadItems(), loadSkills(), get('data/heroes.json'), get('data/effects.json'), get('data/sim.json')]);
  model = buildModel({ items, skills, heroes: heroes || [], effects, sim });
  return model;
}

const fmt = n => (Number.isFinite(n) ? Math.round(n).toLocaleString('en-US') : '—');
const fmtPct = v => `${+(v * 100).toFixed(2)}%`;
const fmtFactor = f => `×${+f.toFixed(4)}`;

function blankState(hero) {
  return { hero, level: 100, skill: '', focus: '', parts: {}, gear: { icon: 'Immortal Icon' }, base: {}, mods: {}, manual: {}, over: {}, allyStat: 5000 };
}

const CHEVRON = '<svg class="custom-select-chevron" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 12 15 18 9"/></svg>';

// Hero picker with portraits: same look, grouping and order as the build planner's class picker.
function heroPickerHtml(m, sel) {
  const have = new Set(m.heroList().map(h => h.heroClass));
  const opt = c => `<div class="custom-select-option${c === sel ? ' selected' : ''}" data-hero="${esc(c)}" data-search="${esc(`${c} ${getClassName(c)}`.toLowerCase())}">
      <img class="opt-icon" src="${classIconPath(c)}" alt="" onerror="this.remove()"><span class="opt-name">${esc(getClassName(c))}</span></div>`;
  const listed = new Set(Object.values(ROSTER).flat());
  const rest = [...have].filter(c => !listed.has(c)).sort();
  const list = Object.entries(ROSTER).map(([type, names]) =>
    `<div class="custom-select-group-label" data-stat="${type}">${esc(t('stat.' + type))}</div>${names.filter(c => have.has(c)).map(opt).join('')}`).join('')
    + rest.map(opt).join('');
  return `<div class="custom-select-wrap sim-hero-picker" id="simHeroWrap">
      <div class="custom-select-trigger" id="simHeroTrigger" role="button" tabindex="0">
        <img class="bp-class-icon" src="${classIconPath(sel)}" alt="" onerror="this.remove()">
        <span class="custom-select-label">${esc(getClassName(sel))}</span>${CHEVRON}
      </div>
      <div class="custom-select-dropdown">
        <div class="custom-select-search"><input type="text" id="simHeroSearch" autocomplete="off" spellcheck="false" placeholder="${esc(t('builder.searchClass'))}"></div>
        <div class="custom-select-list" id="simHeroList">${list}</div>
        <div class="custom-select-empty" id="simHeroEmpty" hidden>${esc(t('builder.noClassMatch'))}</div>
      </div>
    </div>`;
}

const termsText = h => h.terms.map(x => (x.flat != null ? fmt(x.flat) : `${STAT_LABEL[x.stat] || x.stat} × ${x.x}`)).join(' + ');
const keyText = hotkey => (String(hotkey || '').match(/Passive|[A-Z]/g) || []).map(k => (k === 'Passive' ? 'P' : k)).join('→');

// Skill bar: one icon button per skill with damage, in skill order (hover shows the skill tooltip).
function skillBarHtml(hits, hero, sel) {
  const seen = new Map();
  for (const h of hits) {
    if (!seen.has(h.skill)) seen.set(h.skill, { hotkey: h.hotkey, icon: h.icon, n: 0 });
    seen.get(h.skill).n++;
  }
  return `<div class="sim-skillbar">${[...seen].map(([name, v]) => `<button type="button" class="sim-skill${name === sel ? ' active' : ''}" data-pick-skill="${esc(name)}" data-skill="${esc(hero.heroClass + '|' + name)}" data-color="${esc(hero.color || '')}" aria-pressed="${name === sel}">
      ${iconHtml(name, 'sim-skill-icon', iconSrc(v.icon || name))}
      <kbd>${esc(keyText(v.hotkey))}</kbd>
    </button>`).join('')}</div>
    ${sel ? `<p class="sim-skill-name"><kbd class="hs-key">${esc(keyText(seen.get(sel)?.hotkey))}</kbd> <b>${esc(sel)}</b>${seen.get(sel)?.n > 1 ? ` <span>${esc(t('sim.nParts', { n: seen.get(sel).n }))}</span>` : ''}</p>` : ''}`;
}

function gearHtml(s) {
  return GEAR_SLOTS.map(slot => {
    const name = s.gear[slot];
    const item = name && getItem(name);
    const alt = s.alts?.[slot];
    return `<div class="sim-slot">
      <button type="button" class="sim-slot-btn ${item ? rankInfo(item).css : 'empty'}" data-slot="${slot}" ${item ? `data-name="${esc(name)}"` : ''}>
        ${item ? iconHtml(name, 'sim-slot-icon') : `<span class="sim-slot-icon empty">${slotIcon(SLOT_ICON[slot], 18)}</span>`}
        <span class="sim-slot-text"><small>${esc(t('sim.slot.' + slot))}</small><b>${esc(item ? localizedNameByName(name) : t('sim.emptySlot'))}</b>${item ? '<em class="sim-delta" data-gear-delta="' + slot + '"></em>' : ''}</span>
      </button>
      ${item ? `<button type="button" class="sim-slot-clear" data-clear="${slot}" aria-label="${esc(t('sim.clear'))}">×</button>` : ''}
      ${alt && alt !== name ? `<button type="button" class="sim-alt" data-alt="${slot}" title="${esc(t('sim.swapAlt'))}">⇄ ${esc(localizedNameByName(alt))}</button>` : ''}
    </div>`;
  }).join('');
}

function modValueText(m) {
  if (m.raw) return m.raw;
  if (m.execute) {
    const ex = m.execute, pc = v => `${+(v * 100).toFixed(1)}%`;
    if (ex.below != null) return t('sim.execBelow', { v: pc(ex.max), hp: pc(ex.below) });
    return t('sim.execRange', { min: pc(ex.min), max: pc(ex.max), hp: pc(ex.fullAt || 0) });
  }
  if (m.step === 'info') return '';
  const pct = PCT_STEPS.has(m.step);
  const show = v => (pct ? fmtPct(v) : fmt(v));
  if (m.perStack) return `${show(m.perStack)} ${t('sim.perStack')}${m.atMax ? ` (+${show(m.atMax)} ${t('sim.atMax')})` : ''}`;
  if (m.atMax) return `+${show(m.atMax)} ${t('sim.atMax')}`;
  if (m.formula?.length) return m.formula.map(f => `(${f.base} + ${STAT_LABEL[f.stat] || f.stat} / ${f.div})%`).join(' + ');
  if (m.scale?.length) return m.scale.map(f => `${STAT_LABEL[f.stat] || f.stat} × ${f.x}`).join(' + ');
  return show(m.value || 0);
}

// "INT +", "Attack Damage %", "All stats +"… for stat modifiers; the step name otherwise.
function stepText(m) {
  if (m.step !== 'stat' && m.step !== 'statPct') return t('sim.step.' + m.step);
  const name = m.stat === 'all' ? t('sim.allStats') : m.stat === 'main' || !m.stat ? t('sim.mainStat') : (STAT_LABEL[m.stat === 'hp' ? 'maxHp' : m.stat === 'mp' ? 'maxMp' : m.stat] || m.stat);
  return `${name} ${m.step === 'stat' ? '+' : '%'}`;
}

// Item icon, the hero skill's icon, or an empty square so labels line up.
function modIcon(m) {
  if (m.source?.item) return iconHtml(m.source.item, `sim-mod-icon ${rankInfo(getItem(m.source.item)).css}`);
  const sk = m.source?.hero && m.source.skill && getSkill(m.source.hero, m.source.skill);
  if (sk) return iconHtml(sk.name, 'sim-mod-icon', iconSrc(sk.icon || sk.name));
  return '<span class="sim-mod-icon empty"></span>';
}

// The modifier's automatic value as typed units (15 for 15%, 400 for +400).
const autoText = m => (m.auto == null ? '' : PCT_STEPS.has(m.step) ? String(+(m.auto * 100).toFixed(2)) : fmt(m.auto));

function modRow(m) {
  const st = m.state || {};
  const unit = PCT_STEPS.has(m.step) ? '%' : '';
  return `<li class="sim-mod${m.on ? ' on' : ''}${m.blocked ? ' blocked' : ''}${m.modeOff ? ' modeoff' : ''}${m.unmodelled ? ' unmodelled' : ''}" data-mod="${esc(m.id)}">
    <label class="sim-mod-main">
      <input type="checkbox" data-mod-on ${m.on ? 'checked' : ''} ${m.step === 'info' ? 'disabled' : ''}>
      ${modIcon(m)}
      <span class="sim-mod-label">${esc(m.label)}
        <small>${m.unmodelled ? `<span class="sim-unmodelled">${esc(t(m.defensive ? 'sim.noDamageEffect' : 'sim.unmodelled'))}</span>` : `${esc(stepText(m))} · ${esc(modValueText(m))}`}${m.via ? ` · ${esc(m.via)}` : ''}${m.mode ? ` · <span class="sim-mode">${esc(t('sim.modeOnly', { mode: m.mode.toUpperCase() }))}</span>` : ''}${m.blocked ? ` · ${esc(t('sim.blockedBy', { name: m.blocked }))}` : ''}${m.raisedBy ? ` · +${esc(m.raisedBy.join(', '))}` : ''}${m.note ? ` · ${esc(m.note)}` : ''}</small>
      </span>
    </label>
    ${m.maxStacks ? `<label class="sim-mini sim-col-stacks" title="${esc(t('sim.stacks'))}"><input type="number" min="0" max="${m.maxStacks}" step="1" data-mod-stacks value="${esc(st.stacks ?? '')}" placeholder="${m.maxStacks}"><span>/${m.maxStacks}</span></label>` : '<span class="sim-col-stacks"></span>'}
    ${m.step !== 'info' ? `<label class="sim-mini sim-col-value" title="${esc(t('sim.overrideValue'))}"><input type="number" step="any" data-mod-value value="${esc(st.value ?? '')}" placeholder="${esc(autoText(m))}"><span>${unit}</span></label>` : '<span class="sim-col-value"></span>'}
    <span class="sim-delta" data-delta></span>
  </li>`;
}

function modsHtml(r, s) {
  const by = Object.fromEntries(GROUPS.map(g => [g, []]));
  for (const m of r.mods) (by[m.group] || by.ally).push({ ...m, state: s.mods[m.id] });
  // Target HP drives execute effects (bonus damage from the target's missing HP); shown when the hero has one.
  const targetHp = r.mods.some(m => m.execute)
    ? `<label class="sim-inline sim-target-hp" title="${esc(t('sim.targetHpHint'))}">${esc(t('sim.targetHp'))} <input type="number" min="0" max="100" step="any" data-target-hp value="${esc(s.targetHp ?? '')}" placeholder="100"> %</label>`
    : '';
  return targetHp + GROUPS.map(g => {
    if (!by[g].length) return '';
    const onCount = by[g].filter(m => m.on).length;
    const open = g === 'hero' || g === 'gear' || onCount > 0;
    return `<details class="sim-group" ${open ? 'open' : ''}>
      <summary>${esc(t('sim.group.' + g))} <span class="sim-count">${onCount}/${by[g].length}</span></summary>
      ${g === 'ally' ? `<label class="sim-inline">${esc(t('sim.allyStat'))} <input type="number" data-ally-stat value="${esc(s.allyStat ?? 5000)}"></label>` : ''}
      <ul class="sim-mods">
        <li class="sim-mod-head" aria-hidden="true"><span></span><span>${esc(t('sim.col.stacks'))}</span><span>${esc(t('sim.col.value'))}</span><span>${esc(t('sim.col.damage'))}</span></li>
        ${by[g].map(modRow).join('')}
      </ul>
    </details>`;
  }).join('') || `<p class="sim-empty">${esc(t('sim.noMods'))}</p>`;
}

function manualHtml(s) {
  const field = ([k, kind], obj, attr) => `<label class="sim-field"><span>${esc(t('sim.man.' + k))}</span>
    <input type="number" step="any" ${attr}="${k}" value="${esc(obj[k] ?? '')}" placeholder="0"><em>${kind === 'pct' ? '%' : ''}</em></label>`;
  const cfg = model.heroConfig(s.hero);
  const ovField = k => `<label class="sim-field"><span>${esc(t('sim.ov.' + k))}</span>
    <input type="number" step="any" data-over="${k}" value="${esc(s.over[k] ?? '')}" placeholder="${esc(cfg[k] ?? '—')}"></label>`;
  return `<div class="sim-man-grid">
      <h4>${esc(t('sim.man.statsHead'))}</h4>${MANUAL.stats.map(f => field(f, s.manual, 'data-man')).join('')}
      <h4>${esc(t('sim.man.damageHead'))}</h4>${MANUAL.damage.map(f => field(f, s.manual, 'data-man')).join('')}
      <h4>${esc(t('sim.man.targetHead'))}</h4>${MANUAL.target.map(f => field(f, s.manual, 'data-man')).join('')}
      <h4>${esc(t('sim.man.overHead'))}</h4><p class="sim-hint">${esc(t('sim.man.overHint'))}</p>${CONVERSIONS.map(ovField).join('')}
    </div>
    <button type="button" class="btn" data-reset-manual>${esc(t('sim.resetManual'))}</button>`;
}

// Stats card: editable base value, then what gear / conditions add, then the total.
// Max MP only shows for heroes with a skill that scales with it.
const statRows = (m, hero) => {
  const usesMp = m.hits(hero).some(h => h.terms.some(x => x.stat === 'maxMp'));
  return STAT_ROWS.filter(([k]) => k !== 'mp' || usesMp);
};
const bonusTip = row => row.sources.map(x => `${x.label}: ${x.pct ? '+' + fmtPct(x.value) : (x.value >= 0 ? '+' : '') + fmt(x.value)}`).join('\n');

function statsHtml(r, s) {
  return `<table class="sim-stattable">
    <thead><tr><th></th><th>${esc(t('sim.stat.base'))}</th><th>${esc(t('sim.stat.bonus'))}</th><th>${esc(t('sim.stat.total'))}</th></tr></thead>
    <tbody>${statRows(model, s.hero).map(([k, label]) => {
      const row = r.statTable[k];
      return `<tr class="${k === r.main ? 'main' : ''}" data-stat-row="${k}">
        <th>${esc(label)}</th>
        <td><input type="number" step="any" data-base="${k}" value="${esc(s.base?.[k] ?? '')}" placeholder="${esc(fmt(row.base))}"></td>
        <td class="bonus" title="${esc(bonusTip(row))}">+${fmt(row.total - row.base)}</td>
        <td class="num">${fmt(row.total)}</td>
      </tr>`;
    }).join('')}</tbody></table>
    <div class="sim-stat-foot"><p class="sim-hint">${esc(t('sim.statsHint'))}</p><button type="button" class="btn" data-reset-base>${esc(t('sim.resetBase'))}</button></div>`;
}

// Refreshes bonus / total cells and base placeholders without rebuilding the inputs.
function updateStats(el, r) {
  for (const tr of el.querySelectorAll('[data-stat-row]')) {
    const row = r.statTable[tr.dataset.statRow];
    tr.querySelector('input').placeholder = fmt(row.base);
    const b = tr.querySelector('.bonus');
    b.textContent = '+' + fmt(row.total - row.base);
    b.title = bonusTip(row);
    tr.querySelector('.num').textContent = fmt(row.total);
  }
}

// A skill's damage parts: include, hit count, damage type, element and crit per part.
function partsHtml(r, s) {
  const types = ['physical', 'magic', 'pure'].map(v => [v, t('sim.type.' + v)]);
  const els = [['', t('sim.none')], ...ELEMENTS.map(e => [e, t('sim.el.' + e)])];
  return `<ul class="sim-parts">${r.parts.map(p => {
    const st = s.parts?.[p.key] || {};
    return `<li class="sim-part${p.on ? ' on' : ''}${p.key === r.hit.key ? ' focus' : ''}" data-part="${esc(p.key)}">
      <label class="sim-part-main">
        <input type="checkbox" data-part-on ${p.on ? 'checked' : ''}>
        <span><b>${esc(termsText(p))}</b><em>“${esc(p.line)}”</em></span>
      </label>
      <div class="sim-part-opts">
        <label class="sim-mini" title="${esc(t('sim.hit.countHint'))}">${esc(t('sim.hit.count'))}
          <input type="number" min="0" step="any" data-part-count value="${esc(st.count ?? '')}" placeholder="${esc(String(+p.autoCount.toFixed(2)))}"></label>
        <div class="sim-seg" role="group" aria-label="${esc(t('sim.hit.type'))}">${types.map(([v, l]) => `<button type="button" class="t-${v}${p.type === v ? ' on' : ''}" data-part-type="${v}" aria-pressed="${p.type === v}">${esc(l)}</button>`).join('')}</div>
        <select class="sim-el affinity-${esc(p.element || 'none')}" data-part-element title="${esc(t('sim.hit.element'))}">${els.map(([v, l]) => `<option value="${esc(v)}" ${p.element === v ? 'selected' : ''}>${esc(v ? l : t('sim.noElement'))}</option>`).join('')}</select>
        <label class="sim-check"><input type="checkbox" data-part-crit ${p.crit ? 'checked' : ''}> ${esc(t('sim.hit.crit'))}</label>
      </div>
    </li>`;
  }).join('')}</ul>`;
}

function resultHtml(r) {
  const label = id => t('sim.step.' + id);
  const srcText = s => s.sources?.map(x => `${esc(x.stat ? `${STAT_LABEL[x.stat] || x.stat} × ${x.x}` : x.label)}: ${x.stat ? fmt(x.value) : (s.op === '+' || s.id === 'base' || s.id === 'crit' ? (s.id === 'crit' ? '+' + (+x.value.toFixed(3)) : fmt(x.value)) : fmtPct(x.value))}`).join(' · ') || '';
  const h = r.hit;
  const rows = h.steps.map(s => `<tr class="${s.skipped ? 'skip' : ''}">
      <th>${esc(label(s.id))}</th>
      <td class="op">${s.skipped ? '—' : s.op === '=' ? '' : s.op === '+' ? '+' + fmt(s.factor) : fmtFactor(s.factor)}</td>
      <td class="num">${fmt(s.value)}</td>
      <td class="src">${s.skipped ? esc(t('sim.skip.' + s.note)) : srcText(s)}</td>
    </tr>`).join('') + (h.count !== 1 ? `<tr class="sim-hits-row">
      <th>${esc(t('sim.hit.count'))}</th><td class="op">×${+h.count.toFixed(2)}</td><td class="num">${fmt(h.subtotal)}</td><td class="src"></td>
    </tr>` : '');
  // Skill total = sum of included parts; click a part to see its steps below.
  const partRows = r.parts.length > 1 ? `<table class="sim-partsum"><tbody>${r.parts.map(p => `<tr class="${p.on ? '' : 'off'}${p.key === h.key ? ' focus' : ''}" data-focus="${esc(p.key)}">
      <th>${esc(termsText(p))}</th>
      <td class="num">${fmt(p.perHit)}</td><td class="op">×${+p.count.toFixed(2)}</td><td class="num"><b>${p.on ? fmt(p.subtotal) : '—'}</b></td>
    </tr>`).join('')}</tbody></table>` : '';
  return `<div class="sim-total">
      <span>${esc(t('sim.total'))} · ${esc(r.skill)}</span><b>${fmt(r.total)}</b>
      ${r.parts.length === 1 && h.count !== 1 ? `<small>${esc(t('sim.perHit', { dmg: fmt(h.perHit), n: +h.count.toFixed(2) }))}</small>` : ''}
      ${r.total !== r.beforeTarget ? `<small>${esc(t('sim.beforeTarget'))}: ${fmt(r.beforeTarget)}</small>` : ''}
    </div>
    ${r.warnings.map(w => `<p class="sim-warn">${esc(t('sim.warn.' + w))}</p>`).join('')}
    ${partRows}
    ${r.parts.length > 1 ? `<h4 class="sim-sub">${esc(t('sim.breakdownOf', { part: termsText(h) }))}</h4>` : ''}
    <table class="sim-steps"><tbody>${rows}</tbody></table>
    <p class="sim-hint">${esc(t('sim.formulaNote'))} <a href="#/effects?group=formula">${esc(t('sim.formulaLink'))}</a></p>`;
}

export async function initSim() {
  const app = document.getElementById('app');
  app.innerHTML = `<div class="idb-empty">${esc(t('sim.loading'))}</div>`;
  const m = await loadModel();
  loadPlanner();

  const heroes = m.heroList().map(h => h.heroClass);
  let s = (() => { try { return JSON.parse(localStorage.getItem(STORE_KEY) || 'null'); } catch { return null; } })();
  if (!s || !heroes.includes(s.hero)) s = blankState(heroes.includes('Water Mage') ? 'Water Mage' : heroes[0]);
  s = { ...blankState(s.hero), ...s };
  // Icons are account-wide: default to Immortal Icon unless the slot was cleared on purpose ('').
  if (!('icon' in (s.gear || {}))) s.gear = { ...s.gear, icon: 'Immortal Icon' };
  let builds = [];

  app.innerHTML = `
    <div class="page-header">
      <h1>${esc(t('sim.title'))}</h1>
      <p class="page-subtitle">${esc(t('sim.subtitle'))}</p>
    </div>
    <div class="sim-layout">
      <div class="sim-left">
        <section class="sim-card" id="simSetup"></section>
        <section class="sim-card"><h3>${esc(t('sim.stats'))}</h3><div id="simStats"></div></section>
        <section class="sim-card"><h3>${esc(t('sim.conditions'))}</h3><div id="simMods"></div></section>
        <details class="sim-card sim-manual"><summary><h3>${esc(t('sim.manual'))}</h3></summary><p class="sim-hint">${esc(t('sim.manualHint'))}</p><div id="simManual"></div></details>
      </div>
      <aside class="sim-card sim-right" id="simResult"></aside>
    </div>`;
  const setupEl = document.getElementById('simSetup');
  const modsEl = document.getElementById('simMods');
  const manEl = document.getElementById('simManual');
  const resEl = document.getElementById('simResult');
  const statsEl = document.getElementById('simStats');

  const persist = () => {
    try { localStorage.setItem(STORE_KEY, JSON.stringify(s)); } catch {}
    history.replaceState(null, '', '#/sim');
  };
  const run = () => simulate(m, s);

  async function loadBuildList() {
    builds = [];
    const own = state.builds[s.hero];
    if (own && state.rows.length) {
      const rows = state.rows.filter(r => own[r.id] && Object.keys(own[r.id]).length).map(r => ({ name: r.name, slots: own[r.id] }));
      if (rows.length) builds.push({ label: t('sim.myPlanner'), rows });
    }
    for (const creator of await fetchCreatorsForClass(s.hero)) {
      const data = await fetchBuild(s.hero, creator);
      if (data?.rows?.length) builds.push({ label: creator, rows: data.rows.filter(r => Object.keys(r.slots || {}).length) });
    }
  }

  function renderSetup(r) {
    const hits = r ? r.hits : m.hits(s.hero);
    const hero = m.heroByClass.get(s.hero) || {};
    setupEl.innerHTML = `
      <div class="sim-row">
        ${heroPickerHtml(m, s.hero)}
        <label class="idb-select sim-level"><span>${esc(t('sim.level'))}</span><input type="number" id="simLevel" min="1" max="109" value="${esc(s.level)}"></label>
        <label class="idb-select sim-build"><span>${esc(t('sim.loadBuild'))}</span><select id="simBuild">
          <option value="">${esc(builds.length ? t('sim.pickBuild') : t('sim.noBuilds'))}</option>
          ${builds.map((b, bi) => `<optgroup label="${esc(b.label)}">${b.rows.map((row, ri) => `<option value="${bi}:${ri}">${esc(b.label)} · ${esc(row.name)}</option>`).join('')}</optgroup>`).join('')}
        </select></label>
      </div>
      ${skillBarHtml(hits, hero, r?.skill)}
      ${r ? partsHtml(r, s) : `<p class="sim-empty">${esc(t('sim.noHits'))}</p>`}
      <h4 class="sim-sub">${esc(t('sim.gear'))}</h4>
      <div class="sim-gear">${gearHtml(s)}</div>`;
    updateDeltas();
  }

  // Damage differentials: how much the skill total changes if each condition / item were toggled.
  // On → its contribution (total minus total without it); off → what turning it on would add.
  let deltaTimer = 0;
  const signed = v => (Math.abs(v) < 0.5 ? '—' : (v > 0 ? '+' : '−') + fmt(Math.abs(v)));
  function updateDeltas() {
    clearTimeout(deltaTimer);
    deltaTimer = setTimeout(() => {
      const r = run();
      if (!r) return;
      for (const mod of r.mods) {
        const el = modsEl.querySelector(`[data-mod="${CSS.escape(mod.id)}"] [data-delta]`);
        if (!el) continue;
        if (mod.step === 'info') { el.textContent = ''; continue; }
        const alt = simulate(m, { ...s, mods: { ...s.mods, [mod.id]: { ...s.mods[mod.id], on: !mod.on } } });
        const d = mod.on ? r.total - alt.total : alt.total - r.total;
        el.textContent = signed(d);
        el.className = 'sim-delta' + (mod.on ? '' : ' potential') + (d < -0.5 ? ' neg' : '');
        el.title = mod.on ? t('sim.deltaOn') : t('sim.deltaOff');
      }
      for (const el of setupEl.querySelectorAll('[data-gear-delta]')) {
        const slot = el.dataset.gearDelta;
        const alt = simulate(m, { ...s, gear: { ...s.gear, [slot]: '' } });
        el.textContent = signed(r.total - alt.total);
        el.className = 'sim-delta' + (r.total - alt.total < -0.5 ? ' neg' : '');
        el.title = t('sim.deltaGear');
      }
    }, 120);
  }

  // Full re-render (hero / skill / gear changes); value edits only refresh the result.
  function renderAll() {
    const r = run();
    if (r && !s.skill) s.skill = r.skill;
    renderSetup(r);
    modsEl.innerHTML = r ? modsHtml(r, s) : '';
    statsEl.innerHTML = r ? statsHtml(r, s) : '';
    manEl.innerHTML = manualHtml(s);
    resEl.innerHTML = r ? resultHtml(r) : '';
    updateDeltas();
    persist();
  }
  function renderResult() {
    const r = run();
    if (!r) return;
    resEl.innerHTML = resultHtml(r);
    updateStats(statsEl, r);
    // Blocked / on states can change with values; refresh the classes without rebuilding inputs.
    for (const mod of r.mods) {
      const li = modsEl.querySelector(`[data-mod="${CSS.escape(mod.id)}"]`);
      if (!li) continue;
      li.classList.toggle('on', mod.on);
      li.classList.toggle('blocked', !!mod.blocked);
      li.classList.toggle('modeoff', !!mod.modeOff);
      const v = li.querySelector('[data-mod-value]');
      if (v) v.placeholder = autoText(mod);
    }
    updateDeltas();
    persist();
  }

  const setHero = async hero => {
    const icon = s.gear.icon;
    s = blankState(hero);
    if (icon !== undefined) s.gear.icon = icon;
    renderAll();
    await loadBuildList();
    renderSetup(run());
  };

  setupEl.addEventListener('change', e => {
    const el = e.target;
    if (el.id === 'simLevel') { s.level = Number(el.value) || 100; return renderResult(); }
    if (el.id === 'simBuild' && el.value) {
      const [bi, ri] = el.value.split(':').map(Number);
      const row = builds[bi]?.rows[ri];
      if (!row) return;
      const col = { weapon: 'weapon', helm: 'helm', body: 'body', wings: 'wings', accessory: 'accessory' };
      const icon = s.gear.icon;
      s.gear = {}; s.alts = {};
      for (const [slot, c] of Object.entries(col)) {
        const arr = Array.isArray(row.slots[c]) ? row.slots[c] : [row.slots[c]].filter(Boolean);
        if (arr[0]?.name) s.gear[slot] = arr[0].name;
        if (arr[1]?.name) s.alts[slot] = arr[1].name;
      }
      if (icon !== undefined) s.gear.icon = icon;
      return renderAll();
    }
    const li = el.closest('[data-part]');
    if (li) {
      const st = partState(li.dataset.part);
      if (el.matches('[data-part-on]')) { st.on = el.checked; li.classList.toggle('on', el.checked); }
      if (el.matches('[data-part-crit]')) st.crit = el.checked;
      if (el.matches('[data-part-element]')) { st.element = el.value; el.className = `sim-el affinity-${el.value || 'none'}`; }
      return renderResult();
    }
  });
  setupEl.addEventListener('input', e => {
    const el = e.target;
    if (!el.matches('[data-part-count]')) return;
    partState(el.closest('[data-part]').dataset.part).count = el.value === '' ? undefined : Number(el.value);
    renderResult();
  });
  resEl.addEventListener('click', e => {
    const row = e.target.closest('[data-focus]');
    if (!row) return;
    s.focus = row.dataset.focus;
    for (const li of setupEl.querySelectorAll('[data-part]')) li.classList.toggle('focus', li.dataset.part === s.focus);
    renderResult();
  });
  // Hero picker: open/close, search, pick.
  const heroWrap = () => document.getElementById('simHeroWrap');
  const filterHeroes = () => {
    const q = document.getElementById('simHeroSearch').value.trim().toLowerCase();
    let label = null, labelHas = false, any = false;
    const finish = () => { if (label) label.hidden = !labelHas; };
    for (const el of document.getElementById('simHeroList').children) {
      if (el.classList.contains('custom-select-group-label')) { finish(); label = el; labelHas = false; continue; }
      const match = !q || el.dataset.search.includes(q);
      el.hidden = !match;
      if (match) { labelHas = true; any = true; }
    }
    finish();
    document.getElementById('simHeroEmpty').hidden = any;
  };
  const toggleHeroes = open => {
    const wrap = heroWrap();
    if (!wrap) return;
    wrap.classList.toggle('open', open);
    if (!open) return;
    const search = document.getElementById('simHeroSearch');
    search.value = '';
    filterHeroes();
    wrap.querySelector('.custom-select-option.selected')?.scrollIntoView({ block: 'nearest' });
    search.focus();
  };
  const onDocClick = e => { if (!e.target.closest('#simHeroWrap')) toggleHeroes(false); };
  document.addEventListener('click', onDocClick);
  setupEl.addEventListener('input', e => { if (e.target.id === 'simHeroSearch') filterHeroes(); });
  setupEl.addEventListener('keydown', e => {
    if (e.target.id === 'simHeroTrigger' && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); toggleHeroes(true); }
    if (e.target.id !== 'simHeroSearch') return;
    if (e.key === 'Escape') toggleHeroes(false);
    if (e.key === 'Enter') {
      const first = heroWrap().querySelector('.custom-select-option:not([hidden])');
      if (first) setHero(first.dataset.hero);
    }
  });

  setupEl.addEventListener('click', e => {
    if (e.target.closest('#simHeroTrigger')) return toggleHeroes(!heroWrap().classList.contains('open'));
    const heroOpt = e.target.closest('[data-hero]');
    if (heroOpt) return void setHero(heroOpt.dataset.hero);
    const typeBtn = e.target.closest('button[data-part-type]');
    if (typeBtn) {
      partState(typeBtn.closest('[data-part]').dataset.part).type = typeBtn.dataset.partType;
      for (const b of typeBtn.parentElement.children) { b.classList.toggle('on', b === typeBtn); b.setAttribute('aria-pressed', String(b === typeBtn)); }
      return renderResult();
    }
    const pick = e.target.closest('[data-pick-skill]');
    if (pick) { s.skill = pick.dataset.pickSkill; s.focus = ''; return renderAll(); }
    const clear = e.target.closest('[data-clear]');
    if (clear) { s.gear[clear.dataset.clear] = ''; return renderAll(); }
    const alt = e.target.closest('[data-alt]');
    if (alt) {
      const slot = alt.dataset.alt;
      const cur = s.gear[slot];
      s.gear[slot] = s.alts[slot];
      s.alts[slot] = cur;
      return renderAll();
    }
    const btn = e.target.closest('[data-slot]');
    if (!btn) return;
    const slot = btn.dataset.slot;
    openItemPicker({
      title: t('sim.slot.' + slot),
      titleIcon: SLOT_ICON[slot] === 'all' ? null : SLOT_ICON[slot],
      tabs: slot === 'icon' ? [ALL_TAB] : [...EQUIP_TABS, ALL_TAB],
      tab: SLOT_TAB[slot],
      allItems: slot === 'icon',
      current: () => new Set([s.gear[slot]].filter(Boolean)),
      currentLabel: t('picker.equipped'),
      onPick: item => { s.gear[slot] = item.name; renderAll(); },
      // Damage difference of each item vs. what's in the slot now, best first.
      annotate: (() => {
        const base = run()?.total ?? 0;
        return item => {
          if (!item.stats || !Object.keys(item.stats).some(k => typeof item.stats[k] === 'number')) return null;
          const d = (simulate(m, { ...s, gear: { ...s.gear, [slot]: item.name } })?.total ?? base) - base;
          return { score: d, text: item.name === s.gear[slot] ? '' : signed(d), cls: d > 0.5 ? 'up' : d < -0.5 ? 'down' : '', title: t('sim.deltaSwap') };
        };
      })(),
      byScore: true,
      scoreLabel: t('sim.bestFirst'),
    });
  });

  const modState = id => (s.mods[id] = s.mods[id] || {});
  const partState = key => ((s.parts = s.parts || {})[key] = s.parts[key] || {});
  modsEl.addEventListener('change', e => {
    const el = e.target;
    if (el.matches('[data-ally-stat]')) { s.allyStat = Number(el.value) || 0; return renderResult(); }
    const li = el.closest('[data-mod]');
    if (!li) return;
    const st = modState(li.dataset.mod);
    if (el.matches('[data-mod-on]')) st.on = el.checked;
    renderResult();
  });
  modsEl.addEventListener('input', e => {
    const el = e.target;
    if (el.matches('[data-target-hp]')) { s.targetHp = el.value === '' ? undefined : Number(el.value); return renderResult(); }
    const li = el.closest('[data-mod]');
    if (!li) return;
    const st = modState(li.dataset.mod);
    if (el.matches('[data-mod-stacks]')) st.stacks = el.value === '' ? undefined : Number(el.value);
    if (el.matches('[data-mod-value]')) st.value = el.value === '' ? undefined : Number(el.value);
    renderResult();
  });
  statsEl.addEventListener('input', e => {
    const k = e.target.dataset.base;
    if (!k) return;
    s.base = s.base || {};
    s.base[k] = e.target.value === '' ? undefined : Number(e.target.value);
    renderResult();
  });
  statsEl.addEventListener('click', e => {
    if (!e.target.closest('[data-reset-base]')) return;
    s.base = {};
    statsEl.innerHTML = statsHtml(run(), s);
    renderResult();
  });
  manEl.addEventListener('input', e => {
    const el = e.target;
    const v = el.value === '' ? undefined : Number(el.value);
    if (el.dataset.man) s.manual[el.dataset.man] = v;
    if (el.dataset.over) s.over[el.dataset.over] = v;
    renderResult();
  });
  manEl.addEventListener('click', e => {
    if (!e.target.closest('[data-reset-manual]')) return;
    s.manual = {}; s.over = {};
    manEl.innerHTML = manualHtml(s);
    renderResult();
  });

  renderAll();
  await loadBuildList();
  renderSetup(run());
  const unbindA = bindItemHover(setupEl);
  const unbindB = bindItemHover(modsEl);
  return () => { unbindA(); unbindB(); document.removeEventListener('click', onDocClick); };
}
