// Minimal line icons (inline SVG) for items and map markers.

const P = {
  nodule: '<path d="M6 15l3-7 7-2 4 6-2 7-8 1z"/><path d="M9 8l3 5 6-1M12 13l-2 7"/>',
  crystal: '<path d="M12 3l3 6-3 12-3-12z"/><path d="M6 9l2 3-1 7-2-6zM18 9l-2 3 1 7 2-6z"/>',
  fiber: '<path d="M6 20c2-6 2-10 6-16M12 20c0-6 1-10 5-15M9 12c3-1 5 0 7 2"/>',
  shard: '<path d="M4 16l6-10 4 3-3 9z"/><path d="M14 9l6-3-2 8-5 2"/>',
  plate: '<rect x="4" y="7" width="16" height="10" rx="1"/><path d="M8 7v10M16 7v10"/>',
  glyph: '<circle cx="12" cy="12" r="7"/><path d="M12 5v4M12 15v4M7 12h3M14 12l4-3"/>',
  med: '<rect x="4" y="6" width="16" height="12" rx="2"/><path d="M12 9v6M9 12h6"/>',
  cell: '<rect x="6" y="5" width="12" height="15" rx="2"/><path d="M10 3h4M12 9l-2 4h4l-2 4"/>',
  key: '<circle cx="8" cy="12" r="4"/><path d="M12 12h9M18 12v3M21 12v2"/>',
  station: '<circle cx="12" cy="12" r="5"/><path d="M12 3v4M12 17v4M3 12h4M17 12h4"/>',
  ruin: '<path d="M5 20V8l7-4 7 4v12M9 20v-7h6v7"/>',
  biome: '<path d="M4 18c3-8 5-8 8 0M10 18c3-11 6-11 10 0"/>',
  cave: '<path d="M3 19c2-9 5-13 9-13s7 4 9 13M9 19c1-4 2-6 3-6s2 2 3 6"/>',
  lab: '<rect x="4" y="9" width="16" height="9"/><path d="M8 9V6h8v3M8 13h2M14 13h2"/>',
  mystery: '<path d="M9 9a3 3 0 1 1 4 3c-1 .5-1 1-1 2M12 17v.5"/>',
  wreck: '<path d="M3 15l4 3h10l4-6H3zM9 12V6l5 2-5 2"/>',
  signal: '<circle cx="12" cy="12" r="2"/><path d="M8 8a6 6 0 0 0 0 8M16 8a6 6 0 0 1 0 8M5 5a10 10 0 0 0 0 14M19 5a10 10 0 0 1 0 14"/>',
  abyss: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4"/><circle cx="12" cy="12" r="1"/>',
};

export function icon(name, color = 'currentColor', size = 28) {
  const body = P[name] || P.mystery;
  return `<svg class="ico" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
}

export function iconPath(name) { return P[name] || P.mystery; }
