import { state, FONTS } from './store.js';

const loaded = new Set();

export function loadFont(font) {
  if (!font || !font.google || loaded.has(font.id)) return;
  loaded.add(font.id);
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = `https://fonts.googleapis.com/css2?family=${font.google}&display=swap`;
  document.head.append(link);
}

function parseColor(value) {
  const v = value.trim();
  let m = v.match(/^#([\da-f]{3}|[\da-f]{6})$/i);
  if (m) {
    let h = m[1];
    if (h.length === 3) h = [...h].map((c) => c + c).join('');
    return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
  }
  m = v.match(/rgba?\((\d+)[,\s]+(\d+)[,\s]+(\d+)/);
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
}

// Тёмный или светлый текст на акцентной кнопке, по яркости цвета.
export function inkFor(color) {
  const rgb = parseColor(color);
  if (!rgb) return '#0b0f1a';
  const lin = rgb.map((c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  const L = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
  return L > 0.3 ? '#0b0f1a' : '#ffffff';
}

export function applyAppearance() {
  const s = state.settings;
  const h = document.documentElement;
  h.dataset.theme = s.theme;
  h.dataset.mode = state.mode;
  if (s.accentMode === 'custom') {
    h.dataset.accent = 'custom';
    h.style.setProperty('--accent', s.accentColor);
  } else {
    h.dataset.accent = 'mode';
    h.style.removeProperty('--accent');
  }
  const font = FONTS.find((f) => f.id === s.font) || FONTS[0];
  loadFont(font);
  h.style.setProperty('--font', font.stack);
  h.style.setProperty('--fs', `${s.fontSize}px`);
  const accent = getComputedStyle(h).getPropertyValue('--accent');
  h.style.setProperty('--on-accent', inkFor(accent));
}
