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

export function buildRecipeTree(name, neededQty, itemMap, ownedMap, visited = new Set()) {
  const item = itemMap.get(name);
  const ownedQty = ownedMap.get(name) || 0;
  const hasRecipe = item && item.recipe && item.recipe.length > 0;
  const isLeaf = !hasRecipe;

  const node = {
    name,
    neededQty,
    ownedQty,
    status: ownedQty >= neededQty ? 'have' : ownedQty > 0 ? 'partial' : 'none',
    isLeaf,
    droppedBy: item ? (item.dropped_by || []) : [],
    children: [],
  };

  if (!isLeaf && !visited.has(name)) {
    const next = new Set(visited);
    next.add(name);
    for (const ingredient of item.recipe) {
      const [matName, matQty] = Object.entries(ingredient)[0];
      const totalNeeded = neededQty * matQty;
      node.children.push(buildRecipeTree(matName, totalNeeded, itemMap, ownedMap, next));
    }
  }

  return node;
}

export function flattenToLeaves(name, qty, itemMap, accumulator = new Map(), visited = new Set()) {
  const item = itemMap.get(name);
  const hasRecipe = item && item.recipe && item.recipe.length > 0;

  if (!hasRecipe || visited.has(name)) {
    accumulator.set(name, (accumulator.get(name) || 0) + qty);
    return accumulator;
  }

  const next = new Set(visited);
  next.add(name);
  for (const ingredient of item.recipe) {
    const [matName, matQty] = Object.entries(ingredient)[0];
    flattenToLeaves(matName, qty * matQty, itemMap, accumulator, next);
  }
  return accumulator;
}

const EXCLUDED_MATERIALS = new Set([
  'Prius Silver Coin',
  'Prius Gold Coin',
]);

export function buildComprehensiveData(trackedItems, itemMap, ownedMap, bossData) {
  const bossMap = new Map();
  if (bossData) {
    for (const boss of bossData) bossMap.set(boss.name, boss);
  }

  const results = [];
  for (const itemName of trackedItems) {
    const leaves = flattenToLeaves(itemName, 1, itemMap);
    const materials = [];

    for (const [matName, needed] of leaves) {
      if (EXCLUDED_MATERIALS.has(matName)) continue;
      const mat = itemMap.get(matName);
      const droppedBy = mat ? (mat.dropped_by || []) : [];
      const owned = ownedMap.get(matName) || 0;
      const bosses = droppedBy.map(name => ({ name, boss: bossMap.get(name) || null }));
      materials.push({ name: matName, needed, owned, bosses, item: mat || null });
    }

    results.push({ itemName, materials });
  }

  return results;
}
