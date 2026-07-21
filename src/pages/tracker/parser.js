export function parseSaveFile(text) {
  const lines = [];
  const re = /call Preload\( "(.*)" \)/;
  for (const raw of text.split(/\r?\n/)) {
    const m = raw.match(re);
    if (m) lines.push(m[1]);
  }
  if (!lines.length) return null;

  const meta = { username: '', version: '', compatibleVersion: '', class: '', level: 0 };
  const sections = {};
  const loadCodes = [];
  let currentSection = null;

  const sectionRe = /^-{10}(.+)-{10}$/;
  const itemRe = /^(\d+)\.\s+(.+?)(?:\s+x(\d+))?$/;
  const metaMap = {
    'User Name': 'username',
    'Played Version': 'version',
    'Compatible Version': 'compatibleVersion',
    'Class': 'class',
    'Level': 'level',
  };

  for (const line of lines) {
    if (line === '---------------------------------------') continue;

    const secMatch = line.match(sectionRe);
    if (secMatch) {
      currentSection = secMatch[1].trim();
      if (!sections[currentSection]) sections[currentSection] = [];
      continue;
    }

    const codeMatch = line.match(/^Load Code \d+: (.+)$/);
    if (codeMatch) {
      loadCodes.push(codeMatch[1]);
      continue;
    }

    if (!currentSection) {
      for (const [prefix, key] of Object.entries(metaMap)) {
        if (line.startsWith(prefix + ': ')) {
          const val = line.slice(prefix.length + 2).trim();
          meta[key] = key === 'level' ? parseInt(val, 10) || 0 : val;
          break;
        }
      }
      continue;
    }

    const itemMatch = line.match(itemRe);
    if (itemMatch) {
      sections[currentSection].push({
        name: itemMatch[2].trim(),
        qty: parseInt(itemMatch[3], 10) || 1,
      });
    }
  }

  const inventory = {};
  for (const items of Object.values(sections)) {
    for (const { name, qty } of items) {
      inventory[name] = (inventory[name] || 0) + qty;
    }
  }

  return {
    ...meta,
    sections,
    loadCodes,
    inventory,
    uploadedAt: Date.now(),
  };
}
