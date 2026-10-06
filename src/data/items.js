import { getLocale } from '../i18n.js';
import { translateItemName } from './translate.js';
import { ICON_EXT } from '../constants.js';

// ── Shared item database ─────────────────────────────────────────────────────
// items.json is ~700KB; every page used to fetch + parse its own copy. This
// module loads it once and exposes lookup helpers shared by all pages.
let itemsPromise = null;
let byName = new Map();
let byNameLower = new Map();
let usedInIndex = null;

export function loadItems() {
  if (!itemsPromise) {
    itemsPromise = fetch('data/items.json')
      .then(r => (r.ok ? r.json() : []))
      .catch(() => [])
      .then(items => {
        byName = new Map(items.map(i => [i.name, i]));
        byNameLower = new Map(items.map(i => [i.name.toLowerCase(), i]));
        return items;
      });
  }
  return itemsPromise;
}

export function getItem(name) {
  return byName.get(name) || null;
}

export function getItemCI(name) {
  return name ? byNameLower.get(name.toLowerCase()) || null : null;
}

// Items whose recipe references `name` in any slot (including "or" alternatives),
// unioned with curated required_by. Built lazily once for the whole database.
export function getUsedIn(item, items) {
  if (!usedInIndex) {
    usedInIndex = new Map();
    for (const other of items) {
      for (const slot of other.recipe || []) {
        for (const ing of Object.keys(slot)) {
          if (!usedInIndex.has(ing)) usedInIndex.set(ing, new Set());
          usedInIndex.get(ing).add(other.name);
        }
      }
    }
  }
  const out = new Set(item.required_by || []);
  for (const n of usedInIndex.get(item.name) || []) out.add(n);
  return [...out];
}

// Commas stay literal: some static servers (incl. Vite dev) don't decode %2C.
export function iconPath(name) {
  return encodeURIComponent(name).replace(/%2C/g, ',');
}

export function iconSrc(name) {
  return `twicons/${iconPath(name)}${ICON_EXT}`;
}

// ── Tiers ────────────────────────────────────────────────────────────────────
// Tier is determined by rank + grade together.
// Grade 0: none/Normal/Magic/Rare. Grade 1-5 (all [Epic]): Deltirama→Arcana.
export const TIERS = {
  none:      { key: 'none',      label: '',          css: '' },
  normal:    { key: 'normal',    label: 'Normal',    css: '' },
  magic:     { key: 'magic',     label: 'Magic',     css: 'rarity-magic' },
  rare:      { key: 'rare',      label: 'Rare',      css: 'rarity-rare' },
  deltirama: { key: 'deltirama', label: 'Deltirama', css: 'rarity-deltirama' },
  neptinos:  { key: 'neptinos',  label: 'Neptinos',  css: 'rarity-neptinos' },
  gnosis:    { key: 'gnosis',    label: 'Gnosis',    css: 'rarity-gnosis' },
  alteia:    { key: 'alteia',    label: 'Alteia',    css: 'rarity-alteia' },
  arcana:    { key: 'arcana',    label: 'Arcana',    css: 'rarity-arcana' },
};
export const TIER_ORDER = ['arcana', 'alteia', 'gnosis', 'neptinos', 'deltirama', 'rare', 'magic', 'normal', 'none'];

const GRADE_TO_TIER = { 1: 'deltirama', 2: 'neptinos', 3: 'gnosis', 4: 'alteia', 5: 'arcana' };
const RANK_TO_TIER = { '[Normal]': 'normal', '[Magic]': 'magic', '[Rare]': 'rare' };

export function rankInfo(item) {
  if (!item) return TIERS.none;
  if (item.rank === '[Epic]' && item.grade >= 1) return TIERS[GRADE_TO_TIER[item.grade]] || TIERS.deltirama;
  return TIERS[RANK_TO_TIER[item.rank]] || TIERS.none;
}

export function tierIndex(item) {
  return item ? TIER_ORDER.indexOf(rankInfo(item).key) : 99;
}

// ── Types ────────────────────────────────────────────────────────────────────
// Collapse weapon subtypes; normalise inconsistent casing / naming.
export function typeGroup(type) {
  if (!type) return 'other';
  const l = type.toLowerCase();
  if (l.startsWith('weapon')) return 'weapon';
  if (l === 'armor' || l === 'headwear' || l === 'wings' || l === 'accessory' || l === 'material') return l;
  return 'other';
}

// "Weapon (Gun)" and "Weapon - Firearms" are the same slot in game.
export function weaponSubtype(type) {
  const l = (type || '').toLowerCase();
  if (!l.startsWith('weapon')) return '';
  if (l.includes('gun') || l.includes('firearm')) return 'gun';
  if (l.includes('bag') || l.includes('backpack')) return 'bag';
  if (l.includes('bow')) return 'bow';
  if (l.includes('staff')) return 'staff';
  if (l.includes('melee')) return 'melee';
  return 'shared';
}

// ── Stats ────────────────────────────────────────────────────────────────────
export const STAT_LABELS = {
  damage: 'Damage', armor: 'Armor', hp: 'HP', mp: 'MP',
  str: 'STR', agi: 'AGI', int: 'INT', allstat: 'All Stats',
  mainstat: 'Main Stat', hpregen: 'HP Regen', mpregen: 'MP Regen',
  movespeed: 'Move Speed', critchancepercent: 'Crit Chance',
  critmultiplier: 'Crit Multiplier', attackspeedpercent: 'Attack Speed',
  skilldamagepercent: 'Skill Damage', periodicdamagepercent: 'Periodic Damage',
  procdamagepercent: 'Proc Damage', damagedealtpercent: 'Damage Dealt',
  healingpercent: 'Healing', healreceivedpercent: 'Heal Received',
  dodgechancepercent: 'Dodge', drpercent: 'Damage Resist',
  dtpercent: 'Damage Taken', mdpercent: 'Magic Resist',
  aadamagepercent: 'AA Damage', expgainpercent: 'EXP Gain',
  revivaltimepercent: 'Revival Time',
  affinityflamepercent: 'Fire Affinity', affinityearthpercent: 'Earth Affinity',
  affinitylightpercent: 'Light Affinity', affinitydarkpercent: 'Dark Affinity',
  affinitywindpercent: 'Wind Affinity', affinitywaterpercent: 'Water Affinity',
  affinityiwpercent: 'Ice/Wind Affinity', affinitywlpercent: 'Water/Lightning Affinity',
  allaffinitypercent: 'All Affinities',
};

// Compact labels for dense list rows.
export const STAT_SHORT = {
  damage: 'Dmg', armor: 'Armor', hp: 'HP', mp: 'MP',
  str: 'STR', agi: 'AGI', int: 'INT', allstat: 'All',
  mainstat: 'Main', hpregen: 'HP/s', mpregen: 'MP/s',
  movespeed: 'MS', critchancepercent: 'Crit', critmultiplier: 'Crit×',
  attackspeedpercent: 'AS', skilldamagepercent: 'Skill', periodicdamagepercent: 'DoT',
  procdamagepercent: 'Proc', damagedealtpercent: 'Dmg Dealt',
  healingpercent: 'Heal', healreceivedpercent: 'Heal Rcv',
  dodgechancepercent: 'Dodge', drpercent: 'DR', dtpercent: 'DT', mdpercent: 'MR',
  aadamagepercent: 'AA', expgainpercent: 'EXP', revivaltimepercent: 'Revive',
  affinityflamepercent: 'Fire', affinityearthpercent: 'Earth',
  affinitylightpercent: 'Light', affinitydarkpercent: 'Dark',
  affinitywindpercent: 'Wind', affinitywaterpercent: 'Water',
  affinityiwpercent: 'Ice/Wind', affinitywlpercent: 'Water/Ltn',
  allaffinitypercent: 'All Aff',
};

// Elemental affinity → colour class suffix (`affinity-<element>`).
export const AFFINITY_ELEMENT = {
  affinityflamepercent: 'flame', affinityearthpercent: 'earth',
  affinitylightpercent: 'light', affinitydarkpercent: 'dark',
  affinitywindpercent: 'wind', affinitywaterpercent: 'water',
  affinityiwpercent: 'iw', affinitywlpercent: 'wl',
  allaffinitypercent: 'all',
};

const NON_NUMERIC = new Set(['passive', 'active', 'spec']);

// Numeric [key, value] pairs of an item's stats, in data order.
export function numericStats(item) {
  if (!item?.stats) return [];
  return Object.entries(item.stats).filter(([k, v]) => !NON_NUMERIC.has(k) && typeof v === 'number');
}

export function formatStat(key, val) {
  const sign = val < 0 ? '' : '+';
  if (key.endsWith('percent')) return `${sign}${parseFloat((val * 100).toFixed(2))}%`;
  if (key === 'critmultiplier') return `x${val}`;
  return `${sign}${val}`;
}

// `droprate` is usually one number, but some items store one rate per entry
// in `dropped_by` (e.g. Frorist: [0.1, 0.1, 0.05]). Always read it through these.
export function dropRateFor(item, bossName) {
  const r = item?.droprate;
  if (Array.isArray(r)) {
    const i = (item.dropped_by || []).indexOf(bossName);
    return typeof r[i] === 'number' ? r[i] : null;
  }
  return typeof r === 'number' && r > 0 ? r : null;
}

export function dropRates(item) {
  return (item?.dropped_by || []).map(boss => ({ boss, rate: dropRateFor(item, boss) }));
}

export function formatDropRate(rate) {
  return `${parseFloat((rate * 100).toFixed(3))}%`;
}

// ── Localised names ──────────────────────────────────────────────────────────
// Korean uses the curated `koreanname`; Chinese (and Korean gaps) fall back to
// the word-map translator. English passes through unchanged.
export function localizedItemName(item) {
  if (!item) return '';
  const loc = getLocale();
  if (loc === 'ko') return item.koreanname || translateItemName(item.name, 'ko');
  if (loc === 'zh') return translateItemName(item.name, 'zh');
  return item.name;
}

export function localizedNameByName(name) {
  const target = getItem(name);
  if (target) return localizedItemName(target);
  const loc = getLocale();
  return loc === 'en' ? name : translateItemName(name, loc);
}
