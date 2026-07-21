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

export function buildRecipeTree(name, neededQty, itemMap, ownedMap, remaining = null, ancestors = new Set()) {
  if (!remaining) {
    remaining = new Map();
    for (const [k, v] of ownedMap) remaining.set(k, v);
  }

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
    droprate: item ? (item.droprate || 0) : 0,
    children: [],
  };

  if (!isLeaf && !ancestors.has(name)) {
    const next = new Set(ancestors);
    next.add(name);
    for (const ingredient of item.recipe) {
      const entries = Object.entries(ingredient);
      const nonExcluded = entries.filter(([n]) => !isExcluded(n));
      if (!nonExcluded.length) continue;

      if (nonExcluded.length === 1) {
        const [matName, matQty] = nonExcluded[0];
        node.children.push(buildRecipeTree(matName, neededQty * matQty, itemMap, ownedMap, remaining, next));
      } else {
        const sorted = [...nonExcluded].sort((a, b) => (remaining.get(b[0]) || 0) - (remaining.get(a[0]) || 0));
        const [chosenName, chosenQty] = sorted[0];
        const alternatives = sorted.slice(1).map(([n]) => n);
        const child = buildRecipeTree(chosenName, neededQty * chosenQty, itemMap, ownedMap, remaining, next);
        child.alternatives = alternatives;
        node.children.push(child);
      }
    }
  }

  return node;
}

export function flattenToLeaves(name, qty, itemMap, ownedMap, accumulator = new Map(), ancestors = new Set(), remaining = null) {
  if (!remaining) {
    remaining = new Map();
    for (const [k, v] of ownedMap) remaining.set(k, v);
  }

  const item = itemMap.get(name);
  const hasRecipe = item && item.recipe && item.recipe.length > 0;

  const available = remaining.get(name) || 0;
  const consumed = Math.min(available, qty);
  remaining.set(name, available - consumed);
  const stillNeeded = qty - consumed;

  if (stillNeeded <= 0) return accumulator;

  if (!hasRecipe || ancestors.has(name)) {
    accumulator.set(name, (accumulator.get(name) || 0) + stillNeeded);
    return accumulator;
  }

  const hasNonExcludedIngredients = item.recipe.some(ing =>
    Object.keys(ing).some(n => !isExcluded(n))
  );

  if (!hasNonExcludedIngredients) {
    accumulator.set(name, (accumulator.get(name) || 0) + stillNeeded);
    return accumulator;
  }

  const next = new Set(ancestors);
  next.add(name);
  for (const ingredient of item.recipe) {
    const entries = Object.entries(ingredient);
    const nonExcluded = entries.filter(([n]) => !isExcluded(n));
    if (!nonExcluded.length) continue;

    if (nonExcluded.length === 1) {
      const [matName, matQty] = nonExcluded[0];
      flattenToLeaves(matName, stillNeeded * matQty, itemMap, ownedMap, accumulator, next, remaining);
    } else {
      const sorted = [...nonExcluded].sort((a, b) => (remaining.get(b[0]) || 0) - (remaining.get(a[0]) || 0));
      const [chosenName, chosenQty] = sorted[0];
      flattenToLeaves(chosenName, stillNeeded * chosenQty, itemMap, ownedMap, accumulator, next, remaining);
    }
  }
  return accumulator;
}

const EXCLUDED_MATERIALS = new Set([
  'Prius Silver Coin',
  'Prius Gold Coin',
]);

function isExcluded(name) {
  return EXCLUDED_MATERIALS.has(name) || name.includes('Soulstone') || name.includes('Token');
}

export function buildComprehensiveData(trackedItems, itemMap, ownedMap, bossData) {
  const bossMap = new Map();
  if (bossData) {
    for (const boss of bossData) bossMap.set(boss.name, boss);
  }

  const totals = new Map();
  const sharedRemaining = new Map();
  for (const [k, v] of ownedMap) sharedRemaining.set(k, v);
  for (const itemName of trackedItems) {
    const leaves = flattenToLeaves(itemName, 1, itemMap, ownedMap, new Map(), new Set(), sharedRemaining);
    for (const [matName, needed] of leaves) {
      if (isExcluded(matName)) continue;
      totals.set(matName, (totals.get(matName) || 0) + needed);
    }
  }

  const groups = {};
  for (const [matName, needed] of totals) {
    const mat = itemMap.get(matName);
    const droppedBy = mat ? (mat.dropped_by || []) : [];
    const entry = { name: matName, needed, item: mat || null };

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

  return groups;
}
