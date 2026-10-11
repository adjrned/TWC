// Boss drop tables (data/boss-drops.json): base rate in %, plus Wish / Icon multipliers.
// Shared by the Monster page calculator and the item database.

let dropsPromise = null;

export function loadBossDrops() {
  if (!dropsPromise) {
    dropsPromise = fetch('data/boss-drops.json')
      .then(r => (r.ok ? r.json() : {}))
      .catch(() => ({}));
  }
  return dropsPromise;
}

// Wish and Icon bonuses don't apply on these bosses.
export const NO_WISH_BOSSES = new Set(['Styrix, the Harvester of Souls', 'Lightbringer Kamael', 'Arcane Lord']);

// Coins, tokens and soulstones ignore every drop bonus.
export function isCurrencyItem(item) {
  const l = item.name.toLowerCase();
  return l.includes('soulstone') || l.includes('token') || l.includes('coin');
}

// Every boss table that lists the item: [{ boss, base, wishMult, iconMult, wishIconMult }].
// Tables are keyed by the boss name used in bosses.json (the inner `name` can be an older spelling).
export function bossDropsForItem(drops, itemName) {
  const out = [];
  for (const [boss, b] of Object.entries(drops || {})) {
    const d = (b.items || []).find(i => i.name === itemName);
    if (d) out.push({ boss, ...d });
  }
  return out;
}
