// Line icons for equipment slots — same stroke style as the nav icons.
const PATHS = {
  weapon:    '<path d="M14.5 17.5L3 6V3h3l11.5 11.5"/><path d="M13 19l6-6M16 16l4 4M19 21l2-2"/>',
  helm:      '<path d="M4 19v-6a8 8 0 0 1 16 0v6z"/><path d="M8 13h8M12 5v4"/>',
  body:      '<path d="M8 3L4 6v5l2 1v9h12v-9l2-1V6l-4-3"/><path d="M8 3a4 4 0 0 0 8 0M12 9v12"/>',
  wings:     '<path d="M12 8C10 5 6 4 2 5c1 5 4 9 10 11"/><path d="M12 8c2-3 6-4 10-3-1 5-4 9-10 11"/><path d="M12 8v12"/>',
  accessory: '<circle cx="12" cy="15" r="6"/><path d="M9 5l3-3 3 3-3 4z"/>',
  material:  '<path d="M6 3h12l4 6-10 12L2 9z"/><path d="M2 9h20M12 21L8 9l4-6 4 6z"/>',
  all:       '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
};

export function slotIcon(key, size = 18) {
  return `<svg class="slot-svg" viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${PATHS[key] || PATHS.all}</svg>`;
}
