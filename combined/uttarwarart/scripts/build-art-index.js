#!/usr/bin/env node
/**
 * Scans output_defaults for folders with manifest.json and writes data/art-index.json
 * so the portfolio can discover all pieces. Run from repo root or via run-web.sh.
 */

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..');
const OUTPUT_DEFAULTS = path.join(REPO_ROOT, 'output_defaults');
const OUT_FILE = path.join(REPO_ROOT, 'data', 'art-index.json');

if (!fs.existsSync(OUTPUT_DEFAULTS)) {
  console.error('output_defaults not found at', OUTPUT_DEFAULTS);
  process.exit(1);
}

const dirs = fs.readdirSync(OUTPUT_DEFAULTS, { withFileTypes: true })
  .filter(d => d.isDirectory())
  .map(d => d.name);

// Iconic foods (UK, India, SF) assigned to each artwork in order
const ARTWORK_FOODS = [
  'Gulab jamun', 'Jalebi', 'Pani puri', 'Masala chai', 'High tea',
  'CTM', 'Full English', 'Bread pudding', 'Clam chowder', 'Irish coffee',
];

const index = [];
for (const folder of dirs) {
  const manifestPath = path.join(OUTPUT_DEFAULTS, folder, 'manifest.json');
  if (!fs.existsSync(manifestPath)) continue;
  try {
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    const food = ARTWORK_FOODS[index.length] || '';
    index.push({
      folder,
      source_filename: manifest.source_filename || folder,
      ...(food && { food }),
      composite_width_px: manifest.composite_width_px,
      composite_height_px: manifest.composite_height_px,
      sections: (manifest.sections || []).map(s => ({
        index: s.index,
        filename: s.filename,
        bounds_px: s.bounds_px,
        width_px: s.width_px,
        height_px: s.height_px,
      })),
    });
  } catch (e) {
    console.warn('Skip', folder, e.message);
  }
}

// Multi-section (multi-canvas) first, then single-section paintings at the end
index.sort((a, b) => {
  const aMulti = a.sections.length > 1 ? 0 : 1;
  const bMulti = b.sections.length > 1 ? 0 : 1;
  return aMulti - bMulti;
});

fs.mkdirSync(path.dirname(OUT_FILE), { recursive: true });
fs.writeFileSync(OUT_FILE, JSON.stringify(index, null, 2), 'utf8');
console.log('Wrote', index.length, 'pieces to', OUT_FILE);
