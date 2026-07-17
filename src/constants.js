export const ROSTER = {
  STR: ['Berserker','Blaster','Crusader','Dark Knight','Fighter','Knight','Lancer','Lightseeker','Merchant','Paladin','Sword Saint'],
  AGI: ['Assassin','Bow Master','Gunner','Hermit','Martial Artist','Phantom Blade','Reaper','Shooter','Sniper','Sword Enchanter','Swordsman','Thunderer','Trickster'],
  INT: ['Alchemist','Arcane Mage','Blood Weaver','Elementalist','Fire Mage','Lightning Mage','Priest','Shrine Priestess','Soul Weaver','Warlock','Water Mage','Wind Mage','Witch']
};

export const COLS = ['weapon','helm','body','wings','accessory'];
export const LABELS = { weapon:'Weapon', helm:'Helm', body:'Body Armor', wings:'Wings', accessory:'Accessory' };
export const ICONS_PATH = 'twicons/';
export const STORAGE_KEY = 'twrpg_v7';
export const DEFAULT_ROWS = ['Early','SD','Tower','Aga','Duke','Gaia','AC','Styrix','Kam'];

export function classIconPath(name) { return ICONS_PATH + name.replace(/\s+/g,'') + 'Icon.jpg'; }
export function buildFileName(name) { return name.replace(/\s+/g,'_') + '.json'; }
export function buildFileNameForCreator(className, creator) {
  return className.replace(/\s+/g,'_') + '.' + creator.replace(/\s+/g,'_') + '.json';
}
