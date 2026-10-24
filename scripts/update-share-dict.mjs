// Keeps public/data/share-dict.json in step with the item list and hero roster:  npm run share-dict
// Build Planner share links refer to heroes and items by their position in this file, so it is
// append-only: new equipment and heroes go on the end, nothing is ever removed or reordered.
// (Items missing from the list still work in links, they just take more characters.)
import fs from 'fs';
import { ROSTER } from '../src/constants.js';

const FILE = 'public/data/share-dict.json';
const EQUIP = /Weapon|Headwear|Armor|Wings|Accessory/i;

const dict = fs.existsSync(FILE) ? JSON.parse(fs.readFileSync(FILE, 'utf8')) : { classes: [], items: [] };
const items = JSON.parse(fs.readFileSync('public/data/items.json', 'utf8'));

const newClasses = Object.values(ROSTER).flat().filter(c => !dict.classes.includes(c)).sort();
const known = new Set(dict.items);
const newItems = items.filter(i => i.id && EQUIP.test(i.type || '') && !known.has(i.id)).map(i => i.id).sort();

dict.classes.push(...newClasses);
dict.items.push(...newItems);
fs.writeFileSync(FILE, JSON.stringify(dict) + '\n');
console.log(`${FILE}: +${newClasses.length} heroes, +${newItems.length} items (${dict.classes.length} heroes, ${dict.items.length} items)`);
