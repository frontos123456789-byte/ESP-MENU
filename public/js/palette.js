// Командная палитра (Ctrl+K): быстрый доступ ко всему без мыши.

import { el } from './ui.js';

let items = [];
let shown = [];
let sel = 0;

function score(label, q) {
  if (!q) return 1;
  const s = label.toLowerCase();
  const direct = s.indexOf(q);
  if (direct >= 0) return 1000 - direct;
  let i = 0;
  let gaps = 0;
  for (const ch of q) {
    const j = s.indexOf(ch, i);
    if (j < 0) return 0;
    gaps += j - i;
    i = j + 1;
  }
  return Math.max(1, 500 - gaps);
}

function draw() {
  const list = document.getElementById('paletteList');
  list.replaceChildren(
    ...(shown.length
      ? shown.map((c, i) =>
          el('button', { class: 'pitem', type: 'button', role: 'option', 'aria-selected': String(i === sel), onclick: () => run(c), onmousemove: () => { if (sel !== i) { sel = i; draw(); } } },
            el('span', {}, c.label),
            c.hint ? el('small', {}, c.hint) : null))
      : [el('p', { class: 'help', style: 'padding:12px' }, 'Ничего не нашлось')])
  );
  list.querySelector('[aria-selected="true"]')?.scrollIntoView({ block: 'nearest' });
}

function filter(q) {
  const query = q.trim().toLowerCase();
  shown = items
    .map((c) => ({ c, s: score(`${c.label} ${c.hint || ''}`, query) }))
    .filter((x) => x.s > 0)
    .sort((a, b) => b.s - a.s)
    .map((x) => x.c);
  sel = 0;
  draw();
}

function run(c) {
  document.getElementById('palette').close();
  setTimeout(() => c.run(), 0);
}

export function openPalette(commands) {
  items = commands.filter((c) => !c.when || c.when());
  const dlg = document.getElementById('palette');
  const input = document.getElementById('paletteInput');
  input.value = '';
  filter('');
  if (!dlg.open) dlg.showModal();
  input.focus();
}

export function initPalette() {
  const input = document.getElementById('paletteInput');
  input.addEventListener('input', () => filter(input.value));
  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); sel = Math.min(shown.length - 1, sel + 1); draw(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); sel = Math.max(0, sel - 1); draw(); }
    else if (e.key === 'Enter') { e.preventDefault(); if (shown[sel]) run(shown[sel]); }
  });
}
