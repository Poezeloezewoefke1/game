// Diver appearance: suit colours, pattern, visor, gloves, scanner finish,
// beam colour and callsign. Shared by the first-person arms, the scanner
// and the full diver model; persisted in localStorage.

const KEY = 'abyssal.look.v1';

export const LOOK_OPTIONS = {
  suit: { label: 'Suit', options: {
    bone: ['Bone', 0xd9d6cc], arctic: ['Arctic white', 0xeeeee8], graphite: ['Graphite', 0x3a3f45], navy: ['Abyss navy', 0x26344c],
    olive: ['Olive', 0x4d5a3c], crimson: ['Crimson', 0x7a2c2a], sand: ['Sand', 0xb9a47c], teal: ['Deep teal', 0x1f5258],
  } },
  accent: { label: 'Accent', options: {
    orange: ['Safety orange', 0xd8692a], yellow: ['Signal yellow', 0xe0b030], cyan: ['Cyan', 0x3cb8cc], red: ['Rescue red', 0xc0392a],
    lime: ['Lime', 0x86bd3e], violet: ['Violet', 0x8a5ad0], white: ['White', 0xe6e6e2], black: ['Black', 0x1c1f22],
  } },
  glove: { label: 'Gloves & boots', options: {
    graphite: ['Graphite', 0x3a3f45], black: ['Black', 0x17191c], tan: ['Tan leather', 0x8a6a48], orange: ['Orange', 0xd8692a], white: ['White', 0xdcdcd6],
  } },
  pattern: { label: 'Suit pattern', options: {
    plain: ['Plain', 0], bands: ['Limb bands', 0], panels: ['Shoulder panels', 0], hazard: ['Hazard cuffs', 0],
  } },
  visor: { label: 'Visor', options: {
    gold: ['Gold', 0xc8963c], smoke: ['Smoke', 0x1c242c], mirror: ['Mirror', 0xa8bccb], amber: ['Amber', 0xd0802c], teal: ['Teal', 0x2c8c90],
  } },
  scanner: { label: 'Scanner finish', options: {
    graphite: ['Graphite & orange', 0x23292f, 0xd8692a], polar: ['Polar white', 0xd8d8d0, 0x2c9cbc], gunmetal: ['Gunmetal & brass', 0x474d55, 0xc89a3c],
    field: ['Field olive', 0x3c4534, 0x15181a], crimson: ['Crimson', 0x6a2422, 0xd8d8d0],
  } },
  beam: { label: 'Scanner light', options: {
    cyan: ['Cyan', 0x5fe8ff], green: ['Green', 0x6cff9c], amber: ['Amber', 0xffb24a], violet: ['Violet', 0xb48cff], white: ['White', 0xe8f4ff],
  } },
};

export const DEFAULT_LOOK = { name: 'SPECIALIST', suit: 'bone', accent: 'orange', glove: 'graphite', pattern: 'bands', visor: 'gold', scanner: 'graphite', beam: 'cyan' };

export function sanitizeLook(l) {
  const out = { ...DEFAULT_LOOK };
  if (!l || typeof l !== 'object') return out;
  for (const k of Object.keys(LOOK_OPTIONS)) if (LOOK_OPTIONS[k].options[l[k]]) out[k] = l[k];
  if (typeof l.name === 'string') out.name = l.name.replace(/[^\w .\-']/g, '').slice(0, 14).toUpperCase() || DEFAULT_LOOK.name;
  return out;
}

export function loadLook() {
  try { return sanitizeLook(JSON.parse(window.localStorage.getItem(KEY))); } catch { return { ...DEFAULT_LOOK }; }
}

export function saveLook(l) {
  try { window.localStorage.setItem(KEY, JSON.stringify(sanitizeLook(l))); } catch { /* private mode */ }
}

/** Resolved colours for a look. */
export function lookColors(l) {
  const o = LOOK_OPTIONS;
  const sc = o.scanner.options[l.scanner];
  return {
    suit: o.suit.options[l.suit][1], accent: o.accent.options[l.accent][1], glove: o.glove.options[l.glove][1],
    visor: o.visor.options[l.visor][1], scanBody: sc[1], scanAccent: sc[2], beam: o.beam.options[l.beam][1], pattern: l.pattern,
  };
}

export function randomLook() {
  const pick = (k) => { const keys = Object.keys(LOOK_OPTIONS[k].options); return keys[Math.floor(Math.random() * keys.length)]; };
  const l = { name: DEFAULT_LOOK.name };
  for (const k of Object.keys(LOOK_OPTIONS)) l[k] = pick(k);
  return l;
}
