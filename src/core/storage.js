// Settings + save game persistence (localStorage, guarded for private modes).

const SETTINGS_KEY = 'abyssal.settings.v1';
const SAVE_KEY = 'abyssal.save.v1';

export const DEFAULT_SETTINGS = {
  sensitivity: 1.0,
  invertY: false,
  fov: 75,
  master: 0.8,
  music: 0.5,
  sfx: 0.8,
  ambience: 0.8,
  quality: 'high', // low | medium | high
  subtitles: true,
  hints: true,
  headBob: true,
};

function safeGet(key) {
  try { return window.localStorage.getItem(key); } catch { return null; }
}
function safeSet(key, value) {
  try { window.localStorage.setItem(key, value); return true; } catch { return false; }
}
function safeRemove(key) {
  try { window.localStorage.removeItem(key); } catch { /* ignore */ }
}

export function loadSettings() {
  const raw = safeGet(SETTINGS_KEY);
  if (!raw) return { ...DEFAULT_SETTINGS };
  try { return { ...DEFAULT_SETTINGS, ...JSON.parse(raw) }; } catch { return { ...DEFAULT_SETTINGS }; }
}

export function saveSettings(s) { safeSet(SETTINGS_KEY, JSON.stringify(s)); }

export function hasSave() { return !!safeGet(SAVE_KEY); }

export function readSave() {
  const raw = safeGet(SAVE_KEY);
  if (!raw) return null;
  try {
    const data = JSON.parse(raw);
    if (!data || data.version !== 1) return null;
    return data;
  } catch { return null; }
}

export function writeSave(data) { return safeSet(SAVE_KEY, JSON.stringify({ ...data, version: 1, savedAt: Date.now() })); }

export function deleteSave() { safeRemove(SAVE_KEY); }
