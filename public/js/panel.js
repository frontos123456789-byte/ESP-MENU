// Правая панель проекта: файлы, превью, консоль, правки. Панели создаются один раз и только
// скрываются, поэтому запущенное превью не перезапускается при переключении вкладок.

import * as W from './workspace.js';
import * as S from './sandbox.js';
import { el, toast, copyText, formatSize, ago, debounce } from './ui.js';
import { highlight, langOf } from './syntax.js';
import { diffLines, diffStats, collapse } from './diff.js';
import { state } from './store.js';
import { postJson } from './api.js';

const PK = 'pult.panel.v1';
const TABS = [
  ['files', 'Файлы'],
  ['preview', 'Превью'],
  ['console', 'Консоль'],
  ['changes', 'Правки'],
];

const ps = {
  open: false,
  tab: 'files',
  width: 520,
  file: null, // открытый файл в просмотре
  edit: false,
  collapsed: new Set(),
  expanded: new Set(), // раскрытые диффы в «Правках»
  device: 'wide',
  previewPath: null,
  previewKind: null, // 'file' | 'snippet'
  snippet: null,
  lastRun: null,
  lastDoc: '',
  unreadErr: 0,
  seenErr: 0,
  published: null, // { label, url, extra }
};
try { Object.assign(ps, JSON.parse(localStorage.getItem(PK) || '{}'), { file: null, edit: false }); } catch { /* по умолчанию */ }
const persist = () => {
  try { localStorage.setItem(PK, JSON.stringify({ open: ps.open, tab: ps.tab, width: ps.width, device: ps.device })); } catch { /* нет хранилища */ }
};

let root;
let panes = {};
let tabsEl;
let ctx = {};

const $ = (id) => document.getElementById(id);

/* ================= дифф ================= */

export function renderDiff(ops, { context = 3, limit = 400 } = {}) {
  const rows = collapse(ops, context);
  const box = el('div', { class: 'diff', role: 'table' });
  let shown = 0;
  for (const r of rows) {
    if (shown++ >= limit) {
      box.append(el('div', { class: 'dl gap' }, el('span', { class: 'dc' }, `…ещё строки, показаны первые ${limit}`)));
      break;
    }
    if (r.t === '…') {
      box.append(el('div', { class: 'dl gap' }, el('span', { class: 'dc' }, `… ${r.skipped} строк без изменений`)));
      continue;
    }
    box.append(
      el('div', { class: `dl ${r.t === '+' ? 'add' : r.t === '-' ? 'del' : 'ctx'}` },
        el('span', { class: 'dn' }, r.n1),
        el('span', { class: 'dn' }, r.n2),
        el('span', { class: 'dt' }, r.t === ' ' ? '' : r.t),
        el('span', { class: 'dc' }, r.s || ' '))
    );
  }
  return box;
}

export const diffOf = (before, after) => diffLines(before ?? '', after ?? '');

/* ================= каркас ================= */

export function initPanel(context) {
  ctx = context || {};
  root = $('panel');
  tabsEl = $('ptabs');
  for (const [id] of TABS) {
    const pane = el('section', { class: 'pane', id: `pane-${id}`, role: 'tabpanel', hidden: true });
    panes[id] = pane;
    $('pbody').append(pane);
  }
  buildPreviewPane();
  buildConsolePane();
  $('panelClose').addEventListener('click', () => setOpen(false));

  const handle = $('panelResize');
  handle.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    handle.setPointerCapture(e.pointerId);
    const move = (ev) => {
      ps.width = Math.max(340, Math.min(Math.round(window.innerWidth * 0.7), window.innerWidth - ev.clientX));
      applyWidth();
    };
    const up = () => {
      handle.removeEventListener('pointermove', move);
      handle.removeEventListener('pointerup', up);
      persist();
    };
    handle.addEventListener('pointermove', move);
    handle.addEventListener('pointerup', up);
  });

  W.onChange((ev) => {
    if (ev.type === 'history') renderChanges();
    renderFiles();
    if (ev.type === 'file' && ps.previewKind === 'file' && ev.path && isPreviewDep(ev.path)) reloadSoon();
    if (ev.type === 'kind') resetPreview();
    if (ev.type === 'kind' || ev.type === 'index') fillPreviewSelect();
    ctx.onWorkspace?.(ev);
  });
  S.onLog(renderConsole);

  applyWidth();
  setOpen(ps.open, true);
  renderTabs();
  renderFiles();
  renderChanges();
  fillPreviewSelect();
}

function applyWidth() {
  document.documentElement.style.setProperty('--panel-w', `${ps.width}px`);
}

export const isOpen = () => ps.open;

export function setOpen(v, silent) {
  ps.open = Boolean(v);
  $('shell').dataset.panel = ps.open ? 'open' : '';
  root.setAttribute('aria-hidden', String(!ps.open));
  if (!silent) persist();
  ctx.onToggle?.(ps.open);
}

export function togglePanel() {
  setOpen(!ps.open);
}

export function openPanel(tab) {
  if (tab) setTab(tab);
  if (!ps.open) setOpen(true);
}

function setTab(t) {
  ps.tab = t;
  if (t === 'console') {
    ps.seenErr = S.logs.filter((l) => l.level === 'error').length;
    ps.unreadErr = 0;
  }
  renderTabs();
  persist();
}

function renderTabs() {
  tabsEl.replaceChildren(
    ...TABS.map(([id, label]) => {
      const badge = id === 'console' && ps.unreadErr ? el('i', { class: 'badge' }, String(ps.unreadErr)) : id === 'changes' && W.ws.history.some((h) => !h.undone) ? el('i', { class: 'dot' }) : null;
      return el('button', { class: 'ptab', type: 'button', role: 'tab', dataset: { tab: id }, 'aria-selected': String(ps.tab === id), onclick: () => setTab(id) }, label, badge);
    })
  );
  for (const [id] of TABS) panes[id].hidden = id !== ps.tab;
}

/* ================= файлы ================= */

function buildTree() {
  const root = { dirs: new Map(), files: [] };
  for (const f of W.ws.index) {
    const parts = f.path.split('/');
    let node = root;
    for (let i = 0; i < parts.length - 1; i++) {
      if (!node.dirs.has(parts[i])) node.dirs.set(parts[i], { dirs: new Map(), files: [], path: parts.slice(0, i + 1).join('/') });
      node = node.dirs.get(parts[i]);
    }
    node.files.push({ ...f, name: parts[parts.length - 1] });
  }
  return root;
}

function treeRows(node, depth, out) {
  for (const [name, d] of [...node.dirs.entries()].sort((a, b) => a[0].localeCompare(b[0], 'ru'))) {
    const closed = ps.collapsed.has(d.path);
    out.push(
      el('button', { class: 'trow dir', type: 'button', style: `--d:${depth}`, 'aria-expanded': String(!closed), onclick: () => { closed ? ps.collapsed.delete(d.path) : ps.collapsed.add(d.path); renderFiles(); } },
        el('span', { class: 'caret' }, closed ? '▸' : '▾'), el('span', { class: 'nm' }, name))
    );
    if (!closed) treeRows(d, depth + 1, out);
  }
  for (const f of node.files.sort((a, b) => a.name.localeCompare(b.name, 'ru'))) {
    out.push(
      el('button', { class: 'trow file' + (f.bin ? ' bin' : ''), type: 'button', style: `--d:${depth}`, title: f.path, dataset: { path: f.path }, onclick: () => openFile(f.path) },
        el('span', { class: 'caret' }, ''), el('span', { class: 'nm' }, f.name), el('small', {}, formatSize(f.size)))
    );
  }
}

function projectBar() {
  const ws = W.ws;
  const fileIn = el('input', { type: 'file', multiple: true, hidden: true });
  fileIn.addEventListener('change', async () => {
    const r = await W.importFiles([...fileIn.files]);
    toast(`Добавлено файлов: ${r.n}${r.skipped ? `, пропущено: ${r.skipped}` : ''}`);
    fileIn.value = '';
  });
  const btns = [];
  btns.push(el('button', { class: 'pbtn', type: 'button', onclick: newFile }, '+ Файл'));
  btns.push(el('button', { class: 'pbtn', type: 'button', onclick: () => fileIn.click() }, 'Загрузить'));
  btns.push(el('button', { class: 'pbtn', type: 'button', onclick: downloadZip, disabled: !ws.index.length }, 'ZIP'));
  btns.push(el('button', { class: 'pbtn', type: 'button', onclick: publishVercel, disabled: !ws.index.length, title: 'Выложить проект сайтом на Vercel' }, 'Опубликовать'));
  btns.push(el('button', { class: 'pbtn', type: 'button', onclick: pushGithub, disabled: !ws.index.length, title: 'Закоммитить проект в ветку репозитория GitHub' }, 'В GitHub'));
  if (ws.kind === 'fs') {
    btns.push(el('button', { class: 'pbtn', type: 'button', onclick: () => W.rescan().then(() => toast('Список обновлён')) }, 'Обновить'));
    btns.push(el('button', { class: 'pbtn', type: 'button', onclick: () => W.useVirtual() }, 'К песочнице'));
  } else {
    if (W.hasFsApi) btns.push(el('button', { class: 'pbtn accent', type: 'button', onclick: pickFolder }, 'Открыть папку'));
    if (ws.index.length) btns.push(el('button', { class: 'pbtn danger', type: 'button', onclick: clearSandbox }, 'Очистить'));
  }
  const badge = ws.kind === 'fs' ? 'папка на компьютере' : 'в браузере';
  const box = el('div', { class: 'pbar' },
    el('div', { class: 'proj' }, el('b', {}, ws.name), el('span', { class: `src ${ws.kind}` }, badge)),
    el('div', { class: 'pbtns' }, ...btns, fileIn)
  );
  const notes = [];
  if (ws.pending) {
    notes.push(el('p', { class: 'pnote' }, `Раньше была открыта папка «${ws.pending.name}». `,
      el('button', { class: 'link-btn', type: 'button', onclick: async () => { try { if (!(await W.resumePending())) toast('Доступ не выдан'); } catch (e) { toast(e.message || 'Не вышло'); } } }, 'Подключить снова')));
  }
  if (ps.published) {
    notes.push(el('p', { class: 'pnote ok' }, `${ps.published.label}: `, el('a', { href: ps.published.url, target: '_blank', rel: 'noopener noreferrer' }, ps.published.url), ps.published.extra ? el('span', {}, ` · ${ps.published.extra}`) : null));
  }
  if (!W.hasFsApi) notes.push(el('p', { class: 'pnote' }, 'Работа с настоящей папкой доступна в Chrome и Edge на компьютере. Здесь работает песочница: файлы хранятся в браузере.'));
  if (ws.kind === 'virtual' && !ws.persistent) notes.push(el('p', { class: 'pnote' }, 'Хранилище браузера недоступно: файлы песочницы пропадут при перезагрузке. Скачай ZIP, если они нужны.'));
  return el('div', {}, box, ...notes);
}

export function renderFiles() {
  if (!panes.files) return;
  const pane = panes.files;
  pane.replaceChildren();
  if (ps.file) return renderViewer(pane);
  pane.append(projectBar());
  if (!W.ws.index.length) {
    pane.append(
      el('div', { class: 'pempty' },
        el('p', {}, W.ws.kind === 'fs' ? 'В этой папке пока нет файлов.' : 'Проект пуст.'),
        el('p', { class: 'help' }, 'Попроси агента в режиме Code что-нибудь написать, и файлы появятся здесь. Можно загрузить свои или открыть папку с компьютера.'))
    );
    return;
  }
  const rows = [];
  treeRows(buildTree(), 0, rows);
  pane.append(el('div', { class: 'tree', role: 'tree' }, ...rows));
}

async function openFile(path) {
  ps.file = path;
  ps.edit = false;
  setTab('files');
  renderFiles();
}

export function focusChange(id) {
  ps.expanded.add(id);
  openPanel('changes');
  renderChanges();
}

export const previewing = () => ps.previewKind === 'file' ? ps.previewPath : null;

export function showFile(path) {
  openPanel('files');
  return openFile(path);
}

async function renderViewer(pane) {
  const path = ps.file;
  const back = el('button', { class: 'pbtn', type: 'button', onclick: () => { ps.file = null; ps.edit = false; renderFiles(); } }, '‹ Файлы');
  const head = el('div', { class: 'vhead' }, back, el('span', { class: 'vpath', title: path }, path));
  pane.append(head);
  const entry = W.ws.index.find((f) => f.path === path);
  if (!entry) {
    pane.append(el('p', { class: 'pnote' }, 'Файл удалён или переименован.'));
    return;
  }
  if (entry.bin) {
    pane.append(el('p', { class: 'pnote' }, `Бинарный файл, ${formatSize(entry.size)}. Показать его здесь нельзя.`));
    return;
  }
  let text;
  try { text = await W.readText(path, 1_500_000); } catch (e) {
    pane.append(el('p', { class: 'pnote' }, e.message));
    return;
  }
  if (ps.file !== path) return;

  const acts = el('div', { class: 'vacts' });
  const isHtml = /\.html?$/i.test(path);
  acts.append(el('button', { class: 'pbtn', type: 'button', onclick: async () => toast((await copyText(text)) ? 'Скопировано' : 'Не вышло') }, 'Копировать'));
  if (isHtml) acts.append(el('button', { class: 'pbtn accent', type: 'button', onclick: () => previewFile(path) }, 'Превью'));
  acts.append(el('button', { class: 'pbtn', type: 'button', onclick: () => { ps.edit = !ps.edit; renderFiles(); } }, ps.edit ? 'Отмена' : 'Править'));
  acts.append(el('button', { class: 'pbtn danger', type: 'button', onclick: async () => {
    if (!confirm(`Удалить ${path}?`)) return;
    const before = text;
    await W.removePath(path);
    W.recordChange(`Удалён ${path}`, [{ path, before, after: null }]);
    ps.file = null;
    renderFiles();
  } }, 'Удалить'));
  pane.append(acts);

  if (ps.edit) {
    const ta = el('textarea', { class: 'editor', spellcheck: 'false', 'aria-label': `Содержимое ${path}` });
    ta.value = text;
    const save = async () => {
      if (ta.value === text) { ps.edit = false; return renderFiles(); }
      try {
        await W.writeText(path, ta.value);
        W.recordChange(`Правка вручную ${path}`, [{ path, before: text, after: ta.value }]);
        toast('Сохранено');
        ps.edit = false;
        renderFiles();
      } catch (e) { toast(e.message || 'Не сохранилось'); }
    };
    ta.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') { e.preventDefault(); save(); }
      if (e.key === 'Tab') {
        e.preventDefault();
        const s = ta.selectionStart;
        ta.setRangeText('  ', s, ta.selectionEnd, 'end');
      }
    });
    pane.append(ta, el('div', { class: 'vacts' }, el('button', { class: 'pbtn accent', type: 'button', onclick: save }, 'Сохранить (Ctrl+S)')));
    return;
  }
  const lines = text.split('\n').length;
  const gutter = el('div', { class: 'gutter', 'aria-hidden': 'true' }, Array.from({ length: lines }, (_, i) => i + 1).join('\n'));
  const code = el('code', {});
  code.innerHTML = highlight(text, langOf(path));
  pane.append(el('div', { class: 'viewer' }, gutter, el('pre', {}, code)));
}

async function newFile() {
  const name = prompt('Имя файла, например index.html или src/app.js');
  if (!name || !name.trim()) return;
  try {
    const p = await W.writeText(name.trim(), '');
    W.recordChange(`Создан ${p}`, [{ path: p, before: null, after: '' }]);
    ps.file = p;
    ps.edit = true;
    setTab('files');
    renderFiles();
  } catch (e) { toast(e.message || 'Не получилось создать файл'); }
}

async function pickFolder() {
  try { await W.pickFolder(); toast(`Подключена папка «${W.ws.name}»`); } catch (e) {
    if (e.name !== 'AbortError') toast(e.message || 'Не получилось открыть папку');
  }
}

async function clearSandbox() {
  if (!confirm('Удалить все файлы песочницы?')) return;
  await W.clearVirtual();
  ps.file = null;
  renderFiles();
}

const latinName = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 50);

function needToken(kind) {
  const t = state.settings.connectors[kind]?.token?.trim();
  if (!t) {
    toast(`Сначала добавь токен ${kind === 'vercel' ? 'Vercel' : 'GitHub'} в Коннекторах`);
    ctx.openConnectors?.();
    return null;
  }
  return t;
}

async function publishVercel() {
  const token = needToken('vercel');
  if (!token) return;
  const name = prompt('Имя проекта на Vercel (латиница, цифры, дефис)', latinName(W.ws.name) || 'pult-app');
  if (!name || !name.trim()) return;
  try {
    const { files, skipped } = await W.collectText();
    toast(`Публикую ${files.length} файл.${skipped ? `, бинарных пропущено: ${skipped}` : ''}…`);
    const c = state.settings.connectors.vercel;
    const h = { 'x-vercel-token': token };
    if (c.team) h['x-vercel-team'] = c.team;
    const j = await postJson('/api/vercel?op=deploy', { name: name.trim(), files }, h);
    ps.published = { label: 'Опубликовано на Vercel', url: j.productionUrl || j.url, extra: 'сайт откроется через 10–20 секунд' };
    renderFiles();
    toast('Отправил на Vercel');
  } catch (e) { toast(e.message || 'Не получилось опубликовать'); }
}

async function pushGithub() {
  const token = needToken('github');
  if (!token) return;
  let last = '';
  try { last = localStorage.getItem('pult.ghrepo') || ''; } catch { /* нет хранилища */ }
  const repo = prompt('Репозиторий GitHub, например frontos/my-app', last);
  if (!repo || !repo.trim()) return;
  const branch = prompt('Ветка (пусто: создам новую pult-…, основную ветку не трогаю)', '');
  if (branch === null) return;
  try {
    const { files } = await W.collectText();
    toast(`Отправляю ${files.length} файл. в GitHub…`);
    const j = await postJson('/api/github?op=commit', { repo: repo.trim(), branch: branch.trim(), message: `Из Пульта: ${W.ws.name}`, files }, { 'x-github-token': token });
    try { localStorage.setItem('pult.ghrepo', repo.trim()); } catch { /* не страшно */ }
    ps.published = { label: `Закоммичено в ветку ${j.branch}`, url: j.compare || j.url, extra: `${j.files} файл.` };
    renderFiles();
    toast('Готово, ветка в GitHub');
  } catch (e) { toast(e.message || 'Не получилось отправить в GitHub'); }
}

async function downloadZip() {
  try {
    const bytes = await W.zipProject();
    download(new Blob([bytes], { type: 'application/zip' }), `${W.ws.name.replace(/[^\w.-]+/g, '_') || 'project'}.zip`);
  } catch (e) { toast(e.message || 'Не получилось собрать ZIP'); }
}

function download(blob, name) {
  const a = el('a', { href: URL.createObjectURL(blob), download: name });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}

/* ================= превью ================= */

let frame;
let selectEl;
let emptyEl;
let holder;
let devBtn;

function buildPreviewPane() {
  const pane = panes.preview;
  selectEl = el('select', { class: 'psel', 'aria-label': 'Файл для превью' });
  selectEl.addEventListener('change', () => selectEl.value && previewFile(selectEl.value));
  devBtn = el('button', { class: 'pbtn', type: 'button', onclick: () => { ps.device = ps.device === 'wide' ? 'phone' : 'wide'; applyDevice(); persist(); } }, '');
  const bar = el('div', { class: 'pbar tight' },
    selectEl,
    el('div', { class: 'pbtns' },
      el('button', { class: 'pbtn', type: 'button', onclick: () => reloadPreview(), title: 'Перезапустить' }, '⟳'),
      devBtn,
      el('button', { class: 'pbtn', type: 'button', onclick: () => frame.requestFullscreen?.().catch(() => toast('Не удалось открыть на весь экран')) }, 'На весь экран'),
      el('button', { class: 'pbtn', type: 'button', onclick: downloadPreview }, 'Скачать .html'))
  );
  frame = el('iframe', {
    class: 'pframe', title: 'Превью',
    sandbox: 'allow-scripts allow-modals allow-forms allow-pointer-lock allow-popups',
    allow: 'autoplay; fullscreen; gamepad; clipboard-write',
    allowfullscreen: true,
  });
  frame.hidden = true;
  emptyEl = el('div', { class: 'pempty' },
    el('p', {}, 'Здесь появится страница из проекта.'),
    el('p', { class: 'help' }, 'Агент открывает превью сам. Или нажми «Превью» у html-блока в чате либо у файла в проекте.'));
  holder = el('div', { class: 'pholder' }, frame, emptyEl);
  pane.append(bar, holder);
  applyDevice();
}

function resetPreview() {
  ps.previewKind = null;
  ps.previewPath = null;
  ps.snippet = null;
  ps.lastDoc = '';
  ps.file = null;
  if (frame) {
    frame.srcdoc = '';
    frame.hidden = true;
    emptyEl.hidden = false;
  }
}

function applyDevice() {
  holder.dataset.device = ps.device;
  devBtn.textContent = ps.device === 'wide' ? 'Телефон' : 'Широкий';
}

function fillPreviewSelect() {
  if (!selectEl) return;
  const htmls = W.ws.index.filter((f) => /\.html?$/i.test(f.path));
  selectEl.replaceChildren(el('option', { value: '' }, ps.previewKind === 'snippet' ? 'Фрагмент из чата' : htmls.length ? 'Выбери файл…' : 'Нет html-файлов'), ...htmls.map((f) => el('option', { value: f.path }, f.path)));
  selectEl.value = ps.previewKind === 'file' && htmls.some((f) => f.path === ps.previewPath) ? ps.previewPath : '';
}

async function showDoc(doc, id) {
  ps.lastDoc = doc;
  ps.lastRun = id;
  frame.hidden = false;
  emptyEl.hidden = true;
  frame.srcdoc = doc;
  return id;
}

export async function previewFile(path) {
  openPanel('preview');
  const id = S.newRun('preview');
  try {
    const doc = await S.docFromProject(path, id);
    ps.previewKind = 'file';
    ps.previewPath = path;
    ps.snippet = null;
    fillPreviewSelect();
    await showDoc(doc, id);
  } catch (e) {
    S.pushLog(id, 'error', `Не удалось собрать страницу: ${e.message}`, 'preview');
    toast(e.message || 'Не получилось открыть превью');
  }
  return id;
}

export async function previewSnippet(code, lang) {
  openPanel('preview');
  const id = S.newRun('preview');
  ps.previewKind = 'snippet';
  ps.snippet = { code, lang };
  ps.previewPath = null;
  fillPreviewSelect();
  await showDoc(S.docFromSnippet(code, lang, id), id);
  return id;
}

export async function reloadPreview() {
  if (ps.previewKind === 'file' && ps.previewPath && W.exists(ps.previewPath)) return previewFile(ps.previewPath);
  if (ps.previewKind === 'snippet' && ps.snippet) return previewSnippet(ps.snippet.code, ps.snippet.lang);
  toast('Нечего перезапускать');
  return null;
}

const reloadSoon = debounce(() => {
  if (ps.previewKind === 'file' && ps.previewPath && W.exists(ps.previewPath)) previewFile(ps.previewPath);
}, 350);

function isPreviewDep(path) {
  return /\.(html?|css|js|mjs|svg|json)$/i.test(path);
}

// Для инструмента агента: открыть страницу, подождать, вернуть консоль.
export async function checkPreview(path, settle = 2500) {
  const id = await previewFile(path);
  await new Promise((r) => setTimeout(r, settle));
  return { logs: S.logsOf(id).map((l) => ({ level: l.level, text: l.text })) };
}

function downloadPreview() {
  if (!ps.lastDoc) return toast('Сначала открой превью');
  // убираем служебный скрипт консоли из скачиваемой копии
  const clean = ps.lastDoc.replace(/<script>\(function\(\)\{var id=[\s\S]*?<\/script>/, '');
  download(new Blob([clean], { type: 'text/html' }), (ps.previewPath || 'preview').replace(/[^\w.-]+/g, '_').replace(/(\.html?)?$/, '.html'));
}

/* ================= консоль ================= */

let consoleList;

function buildConsolePane() {
  consoleList = el('div', { class: 'clist', role: 'log', 'aria-live': 'off' });
  panes.console.append(
    el('div', { class: 'pbar tight' }, el('span', { class: 'help' }, 'Вывод страницы и кода, который запускает агент'),
      el('div', { class: 'pbtns' }, el('button', { class: 'pbtn', type: 'button', onclick: () => S.clearLogs() }, 'Очистить'))),
    consoleList
  );
  renderConsole();
}

function renderConsole() {
  if (!consoleList) return;
  const errs = S.logs.filter((l) => l.level === 'error').length;
  if (errs < ps.seenErr) ps.seenErr = errs;
  if (ps.tab !== 'console') {
    const unread = Math.min(99, errs - ps.seenErr);
    if (unread !== ps.unreadErr) {
      ps.unreadErr = unread;
      renderTabs();
    }
  } else ps.seenErr = errs;
  const stick = consoleList.scrollHeight - consoleList.scrollTop - consoleList.clientHeight < 40;
  if (!S.logs.length) {
    consoleList.replaceChildren(el('p', { class: 'pnote' }, 'Пока пусто.'));
    return;
  }
  consoleList.replaceChildren(
    ...S.logs.slice(-300).map((l) => el('div', { class: `crow ${l.level}` }, el('span', { class: 'lv' }, l.src === 'run' ? 'код' : l.level), el('pre', {}, l.text)))
  );
  if (stick) consoleList.scrollTop = consoleList.scrollHeight;
}

/* ================= правки ================= */

function renderChanges() {
  const pane = panes.changes;
  if (!pane) return;
  const list = W.ws.history;
  renderTabs();
  if (!list.length) {
    pane.replaceChildren(el('div', { class: 'pempty' }, el('p', {}, 'Правок пока нет.'), el('p', { class: 'help' }, 'Каждое изменение файлов, своё или агента, записывается сюда с диффом. Любое можно откатить.')));
    return;
  }
  pane.replaceChildren(
    ...list.map((h) => {
      const c = h.changes[0];
      const st = diffStats(diffOf(c?.before, c?.after));
      const open = ps.expanded.has(h.id);
      return el('div', { class: 'chg' + (h.undone ? ' undone' : '') },
        el('div', { class: 'chg-head' },
          el('button', { class: 'chg-main', type: 'button', onclick: () => { open ? ps.expanded.delete(h.id) : ps.expanded.add(h.id); renderChanges(); }, 'aria-expanded': String(open) },
            el('span', { class: 'caret' }, open ? '▾' : '▸'), el('span', { class: 'chg-label' }, h.label), el('small', {}, ago(h.ts))),
          el('span', { class: 'stat' }, el('b', { class: 'plus' }, `+${st.add}`), ' ', el('b', { class: 'minus' }, `−${st.del}`)),
          el('button', { class: 'pbtn', type: 'button', disabled: h.undone, onclick: async () => { try { await W.undoEntry(h.id); toast('Откатил'); } catch (e) { toast(e.message || 'Не вышло откатить'); } } }, h.undone ? 'Откачено' : 'Откатить')),
        open && c ? renderDiff(diffOf(c.before, c.after)) : null);
    })
  );
}

