import { dropRates } from '../../data/items.js';

export function buildItemMap(items) {
  const map = new Map();
  for (const item of items) {
    map.set(item.name, item);
  }
  return map;
}

export function buildOwnedMap(inventory) {
  return new Map(Object.entries(inventory || {}));
}

// "Either" ingredients are resolved only after every fixed ingredient has taken
// its share of the bag, so an alternative never grabs a material another recipe
// needs outright (e.g. Mark of Lord vs Fragment of Hell). Picks whichever option
// has the most left over.
function pickAlternative(options, pool) {
  return [...options].sort((a, b) => (pool.get(b[0]) || 0) - (pool.get(a[0]) || 0));
}

export function buildRecipeTree(name, neededQty, itemMap, ownedMap, remaining = null, ancestors = new Set(), deferred = null) {
  if (!remaining) {
    remaining = new Map();
    for (const [k, v] of ownedMap) remaining.set(k, v);
  }
  const isRoot = !deferred;
  if (isRoot) deferred = [];

  const item = itemMap.get(name);
  const available = remaining.get(name) || 0;
  const consumed = Math.min(available, neededQty);
  remaining.set(name, available - consumed);

  const hasRecipe = item && item.recipe && item.recipe.length > 0;
  const isLeaf = !hasRecipe;

  const node = {
    name,
    neededQty,
    ownedQty: consumed,
    status: consumed >= neededQty ? 'have' : consumed > 0 ? 'partial' : 'none',
    isLeaf,
    droppedBy: item ? (item.dropped_by || []) : [],
    // Per-monster rates — some items store one rate per dropped_by entry.
    drops: dropRates(item),
    children: [],
  };

  if (!isLeaf && !ancestors.has(name)) {
    const next = new Set(ancestors);
    next.add(name);
    // Only the unowned part gets crafted, so only it consumes materials. A fully
    // owned item still shows its recipe, but against a scratch copy of the bag
    // so it doesn't steal materials from sibling branches.
    const stillNeeded = neededQty - consumed;
    const craftQty = stillNeeded > 0 ? stillNeeded : neededQty;
    const pool = stillNeeded > 0 ? remaining : new Map(remaining);
    for (const ingredient of item.recipe) {
      const entries = Object.entries(ingredient);
      const nonExcluded = entries.filter(([n]) => !isExcluded(n));
      if (!nonExcluded.length) continue;

      if (nonExcluded.length === 1) {
        const [matName, matQty] = nonExcluded[0];
        node.children.push(buildRecipeTree(matName, craftQty * matQty, itemMap, ownedMap, pool, next, deferred));
      } else {
        // Placeholder keeps the child's position; filled in once fixed needs are counted.
        const child = {};
        node.children.push(child);
        deferred.push({ child, options: nonExcluded, qty: craftQty, pool, ancestors: next });
      }
    }
  }

  if (isRoot) {
    while (deferred.length) {
      for (const { child, options, qty, pool, ancestors: anc } of deferred.splice(0)) {
        const [[chosenName, chosenQty], ...rest] = pickAlternative(options, pool);
        Object.assign(child, buildRecipeTree(chosenName, qty * chosenQty, itemMap, ownedMap, pool, anc, deferred));
        child.alternatives = rest.map(([n]) => n);
      }
    }
  }

  return node;
}

export function flattenToLeaves(name, qty, itemMap, ownedMap, accumulator = new Map(), ancestors = new Set(), remaining = null, deferred = null) {
  if (!remaining) {
    remaining = new Map();
    for (const [k, v] of ownedMap) remaining.set(k, v);
  }
  const isRoot = !deferred;
  if (isRoot) deferred = [];

  walkLeaves(name, qty, itemMap, accumulator, ancestors, remaining, deferred);
  if (isRoot) drainDeferred(deferred, itemMap, remaining);
  return accumulator;
}

// Leaves needed per tracked item, sharing one bag across all of them. Alternatives
// wait until every tracked item's fixed ingredients have been counted.
export function flattenTracked(trackedItems, itemMap, ownedMap) {
  const remaining = new Map(ownedMap);
  const deferred = [];
  const perItem = new Map();
  for (const itemName of trackedItems) {
    const acc = new Map();
    perItem.set(itemName, acc);
    walkLeaves(itemName, 1, itemMap, acc, new Set(), remaining, deferred);
  }
  drainDeferred(deferred, itemMap, remaining);
  return perItem;
}

function drainDeferred(deferred, itemMap, remaining) {
  while (deferred.length) {
    for (const { options, qty, accumulator, ancestors } of deferred.splice(0)) {
      const [[chosenName, chosenQty]] = pickAlternative(options, remaining);
      walkLeaves(chosenName, qty * chosenQty, itemMap, accumulator, ancestors, remaining, deferred);
    }
  }
}

function walkLeaves(name, qty, itemMap, accumulator, ancestors, remaining, deferred) {
  const item = itemMap.get(name);
  const hasRecipe = item && item.recipe && item.recipe.length > 0;

  const available = remaining.get(name) || 0;
  const consumed = Math.min(available, qty);
  remaining.set(name, available - consumed);
  const stillNeeded = qty - consumed;

  if (stillNeeded <= 0) return;

  if (!hasRecipe || ancestors.has(name)) {
    accumulator.set(name, (accumulator.get(name) || 0) + stillNeeded);
    return;
  }

  const hasNonExcludedIngredients = item.recipe.some(ing =>
    Object.keys(ing).some(n => !isExcluded(n))
  );

  if (!hasNonExcludedIngredients) {
    accumulator.set(name, (accumulator.get(name) || 0) + stillNeeded);
    return;
  }

  const next = new Set(ancestors);
  next.add(name);
  for (const ingredient of item.recipe) {
    const entries = Object.entries(ingredient);
    const nonExcluded = entries.filter(([n]) => !isExcluded(n));
    if (!nonExcluded.length) continue;

    if (nonExcluded.length === 1) {
      const [matName, matQty] = nonExcluded[0];
      walkLeaves(matName, stillNeeded * matQty, itemMap, accumulator, next, remaining, deferred);
    } else {
      deferred.push({ options: nonExcluded, qty: stillNeeded, accumulator, ancestors: next });
    }
  }
}

const EXCLUDED_MATERIALS = new Set([
  'Prius Silver Coin',
  'Prius Gold Coin',
]);

export function isExcluded(name) {
  return EXCLUDED_MATERIALS.has(name) || name.includes('Soulstone') || name.includes('Token');
}

export function buildComprehensiveData(trackedItems, itemMap, ownedMap, bossData) {
  const bossMap = new Map();
  if (bossData) {
    for (const boss of bossData) bossMap.set(boss.name, boss);
  }

  const totals = new Map();
  const usedFor = new Map();
  for (const [itemName, leaves] of flattenTracked(trackedItems, itemMap, ownedMap)) {
    for (const [matName, needed] of leaves) {
      if (isExcluded(matName)) continue;
      totals.set(matName, (totals.get(matName) || 0) + needed);
      if (!usedFor.has(matName)) usedFor.set(matName, []);
      if (matName !== itemName) usedFor.get(matName).push(itemName);
    }
  }

  const groups = {};
  for (const [matName, needed] of totals) {
    const mat = itemMap.get(matName);
    const droppedBy = mat ? (mat.dropped_by || []) : [];
    const entry = { name: matName, needed, item: mat || null, usedFor: usedFor.get(matName) || [] };

    if (droppedBy.length === 0) {
      if (!groups['Craftable']) groups['Craftable'] = { boss: null, materials: [] };
      groups['Craftable'].materials.push(entry);
    } else {
      for (const bossName of droppedBy) {
        if (!groups[bossName]) groups[bossName] = { boss: bossMap.get(bossName) || null, materials: [] };
        groups[bossName].materials.push(entry);
      }
    }
  }

  // Within each boss, most-needed materials first.
  for (const g of Object.values(groups)) {
    g.materials.sort((a, b) => b.needed - a.needed || a.name.localeCompare(b.name));
  }

  const bossOrder = new Map();
  if (bossData) {
    bossData.forEach((b, i) => bossOrder.set(b.name, i));
  }

  const sorted = Object.entries(groups).sort((a, b) => {
    const idxA = bossOrder.has(a[0]) ? bossOrder.get(a[0]) : -1;
    const idxB = bossOrder.has(b[0]) ? bossOrder.get(b[0]) : -1;
    return idxB - idxA;
  });

  return Object.fromEntries(sorted);
}
