import { state } from '../../state.js';
import { COLS, DEFAULT_ROWS } from '../../constants.js';
import { loadItems } from '../../data/items.js';
import { buildExportJson } from './exportImport.js';
import { fetchBuild } from './buildBrowser.js';

// Share links (#/?b=…) pack the build into bits, then base64url:
//   header   3 bits version · 7 bits hero · 4 bits item-number width · 6 bits phase count
//   per slot 1 bit "same as previous phase", else 1 bit filled → item, 1 bit alternate → item
//   item     number in data/share-dict.json (width bits), or 0 followed by the 24-bit item ID
//   then     phase names as UTF-8 joined by "\n" (left out when they are the defaults)
// share-dict.json is append-only, so old links keep working as items are added.
// An unedited community build shares as its short ?class=…&creator=… link instead.

const VERSION = 2;
const ID_CHARS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const idToInt = id => [...id].reduce((n, c) => n * 62 + ID_CHARS.indexOf(c), 0);
const intToId = n => Array.from({ length: 4 }, (_, i) => ID_CHARS[Math.floor(n / 62 ** (3 - i)) % 62]).join('');

const b64url = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64url = s => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));

let dictPromise = null;
function loadDict() {
  if (!dictPromise) {
    dictPromise = Promise.all([fetch('data/share-dict.json').then(r => r.json()), loadItems()]).then(([dict, items]) => {
      const nameById = new Map(items.filter(i => i.id).map(i => [i.id, i.name]));
      return {
        classes: dict.classes,
        items: dict.items,
        width: Math.max(1, Math.ceil(Math.log2(dict.items.length + 1))),
        numById: new Map(dict.items.map((id, i) => [id, i + 1])),
        idByName: new Map(items.filter(i => i.id).map(i => [i.name, i.id])),
        nameById,
      };
    });
  }
  return dictPromise;
}

class BitWriter {
  bits = [];
  put(value, width) { for (let i = width - 1; i >= 0; i--) this.bits.push(Math.floor(value / 2 ** i) % 2); }
  bytes() {
    const out = new Uint8Array(Math.ceil(this.bits.length / 8));
    this.bits.forEach((b, i) => { if (b) out[i >> 3] |= 0x80 >> (i & 7); });
    return out;
  }
}

class BitReader {
  pos = 0;
  constructor(bytes) { this.bytes = bytes; }
  get(width) {
    let v = 0;
    for (let i = 0; i < width; i++, this.pos++) {
      if (this.pos >= this.bytes.length * 8) throw new Error('short');
      v = v * 2 + ((this.bytes[this.pos >> 3] >> (7 - (this.pos & 7))) & 1);
    }
    return v;
  }
  rest() { return this.bytes.slice(Math.ceil(this.pos / 8)); }
}

// Phase names + item names per slot, for comparing a planner with a community build file.
const fingerprint = rows => JSON.stringify(rows.map(r => [r.name, ...COLS.map(c => {
  const v = r.slots?.[c];
  return (Array.isArray(v) ? v : v ? [v] : []).map(i => i?.name).filter(Boolean);
})]));

export async function buildShareUrl() {
  const base = `${location.origin}${location.pathname}#/?`;
  const data = buildExportJson();

  const cls = state.selectedClass, creator = state.selectedCreator;
  if (creator) {
    const file = await fetchBuild(cls, creator);
    if (file?.rows && fingerprint(file.rows) === fingerprint(data.rows)) return base + new URLSearchParams({ class: cls, creator });
  }

  const dict = await loadDict();
  const w = new BitWriter();
  w.put(VERSION, 3);
  w.put(Math.max(0, dict.classes.indexOf(cls)), 7);
  w.put(dict.width, 4);
  const rows = data.rows.slice(0, 63);
  w.put(rows.length, 6);
  const putItem = name => {
    const id = dict.idByName.get(name);
    const num = id && dict.numById.get(id);
    if (num) w.put(num, dict.width);
    else { w.put(0, dict.width); w.put(id ? idToInt(id) : 0, 24); }
  };
  const prev = COLS.map(() => '');
  for (const row of rows) {
    COLS.forEach((col, i) => {
      const names = (row.slots[col] || []).map(it => it.name).filter(n => dict.idByName.has(n)).slice(0, 2);
      const key = names.join('|');
      if (key === prev[i]) { w.put(1, 1); return; }
      prev[i] = key;
      w.put(0, 1);
      w.put(names.length ? 1 : 0, 1);
      if (!names.length) return;
      putItem(names[0]);
      w.put(names[1] ? 1 : 0, 1);
      if (names[1]) putItem(names[1]);
    });
  }
  const phaseNames = rows.map(r => r.name);
  const defaults = phaseNames.every((n, i) => n === DEFAULT_ROWS[i]);
  const tail = defaults ? new Uint8Array() : new TextEncoder().encode(phaseNames.join('\n'));
  const head = w.bytes();
  const all = new Uint8Array(head.length + tail.length);
  all.set(head); all.set(tail, head.length);
  return base + 'b=' + b64url(all);
}

// Turns a share code back into the export format importExportBuildData() accepts; null if it's broken.
export async function decodeShareCode(code) {
  try {
    const dict = await loadDict();
    const r = new BitReader(unb64url(code));
    if (r.get(3) !== VERSION) return null;
    const cls = dict.classes[r.get(7)];
    const width = r.get(4);
    const count = r.get(6);
    if (!cls) return null;
    const getItem = () => {
      const num = r.get(width);
      const id = num ? dict.items[num - 1] : intToId(r.get(24));
      const name = dict.nameById.get(id);
      return name ? { name, src: null } : null;
    };
    const prev = COLS.map(() => null);
    const rows = [];
    for (let n = 0; n < count; n++) {
      const slots = {};
      COLS.forEach((col, i) => {
        if (!r.get(1)) {
          prev[i] = null;
          if (r.get(1)) {
            const first = getItem();
            const alt = r.get(1) ? getItem() : null;
            prev[i] = [first, alt].filter(Boolean);
          }
        }
        slots[col] = prev[i]?.length ? prev[i] : null;
      });
      rows.push({ slots });
    }
    const text = new TextDecoder().decode(r.rest());
    const names = text ? text.split('\n') : DEFAULT_ROWS;
    rows.forEach((row, i) => { row.name = names[i] || `Phase ${i + 1}`; });
    return { class: cls, createdBy: '', rows };
  } catch {
    return null;
  }
}

