// Converts twicons/*.jpg → twicons/*.webp (same name, same dimensions).
// Only (re)builds a .webp when it is missing or older than its .jpg, so it's
// cheap to re-run after adding icons:  npm run icons
import fs from 'fs';
import path from 'path';
import sharp from 'sharp';

const DIR = 'twicons';
const QUALITY = 82;

const jpgs = fs.readdirSync(DIR).filter(f => f.toLowerCase().endsWith('.jpg'));
let converted = 0, skipped = 0, before = 0, after = 0;

for (const file of jpgs) {
  const src = path.join(DIR, file);
  const dest = src.replace(/\.jpg$/i, '.webp');
  const srcStat = fs.statSync(src);
  before += srcStat.size;
  if (fs.existsSync(dest) && fs.statSync(dest).mtimeMs >= srcStat.mtimeMs) {
    skipped++;
    after += fs.statSync(dest).size;
    continue;
  }
  await sharp(src).webp({ quality: QUALITY, effort: 6 }).toFile(dest);
  after += fs.statSync(dest).size;
  converted++;
}

const mb = n => (n / 1e6).toFixed(1) + ' MB';
console.log(`${converted} converted, ${skipped} up to date — ${mb(before)} JPEG → ${mb(after)} WebP`);
