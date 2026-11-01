// Рабочая область проекта. Два источника файлов:
//  - virtual: «Песочница» в браузере (IndexedDB), работает везде;
//  - fs: настоящая папка на компьютере через File System Access API (Chrome, Edge).
// Сервер файлов не видит: всё читается и пишется прямо из браузера.

import { makeZip } from './zip.js';

const IGNORE_DIRS = new Set(['node_modules', 'dist', 'build', 'out', 'coverage', '__pycache__', 'venv', 'target', 'vendor']);
const BIN_EXT = new Set('png jpg jpeg gif webp ico bmp avif pdf zip gz tar 7z rar mp3 wav ogg flac mp4 webm mov woff woff2 ttf otf eot exe dll so class jar wasm bin psd'.split(' '));
// Файлы с секретами: агент их не читает и не пишет, в публикацию они не уходят.
const SECRET_FILE = /^(\.env(?:\.(?!(?:example|sample|template)$).*)?|.*\.(?:pem|key|p12|pfx|keystore|jks)|id_(?:rsa|dsa|ecdsa|ed25519).*|\.npmrc|\.netrc|\.pypirc|\.htpasswd|credentials(?:\..*)?|secrets?\.(?:json|ya?ml|toml)|service[-_]?account.*\.json)$/i;
const SECRET_DIR = /^(\.ssh|\.aws|\.gnupg|\.kube)$/i;
const MAX_FILES = 3000;
const MAX_READ = 1_000_000;

export const hasFsApi = typeof window !== 'undefined' && typeof window.showDirectoryPicker === 'function';

export const ws = {
  kind: 'virtual', // 'virtual' | 'fs'
  name: 'Песочница',
  handle: null,
  pending: null, // сохранённая папка, ждёт подтверждения доступа
  index: [], // [{ path, size, bin }]
  persistent: false,
  history: [],
  ready: false,
};

const vfiles = new Map(); // path -> string (только virtual)
const listeners = new Set();
export function onChange(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
function emit(ev) {
  for (const fn of listeners) {
    try { fn(ev); } catch { /* слушатель не должен ломать работу */ }
  }
}

export const isBinaryName = (p) => BIN_EXT.has(String(p).split('.').pop().toLowerCase());
export function isSecret(p) {
  const parts = String(p).replace(/\\/g, '/').split('/');
  return SECRET_FILE.test(parts[parts.length - 1]) || parts.slice(0, -1).some((x) => SECRET_DIR.test(x));
}

export function normPath(p) {
  let s = String(p ?? '').replace(/\\/g, '/').trim();
  s = s.replace(/^(\.\/)+/, '').replace(/^\/+/, '');
  if (!s) throw new Error('Пустой путь');
  if (s.length > 300) throw new Error('Слишком длинный путь');
  const parts = s.split('/');
  if (parts.some((x) => x === '' || x === '.' || x === '..')) throw new Error(`Недопустимый путь: ${p}`);
  if (parts.some((x) => x.toLowerCase() === '.git')) throw new Error('Папку .git трогать нельзя');
  return parts.join('/');
}

/* ---------- IndexedDB (только для песочницы и запомненной папки) ---------- */

let dbp = null;
function db() {
  if (dbp) return dbp;
  dbp = new Promise((resolve, reject) => {
    if (typeof indexedDB === 'undefined') return reject(new Error('no idb'));
    const r = indexedDB.open('pult-ws', 1);
    r.onupgradeneeded = () => {
      r.result.createObjectStore('files');
      r.result.createObjectStore('kv');
    };
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
    r.onblocked = () => reject(new Error('blocked'));
  });
  return dbp;
}
async function idb(store, mode, fn) {
  const d = await db();
  return new Promise((resolve, reject) => {
    const t = d.transaction(store, mode);
    const st = t.objectStore(store);
    const req = fn(st);
    t.oncomplete = () => resolve(req && 'result' in req ? req.result : undefined);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  });
}
const safe = async (fn) => {
  try { return await fn(); } catch { return undefined; }
};

/* ---------- индекс ---------- */

function sortIndex() {
  ws.index.sort((a, b) => a.path.localeCompare(b.path, 'ru'));
}
function upsert(path, size) {
  const e = ws.index.find((x) => x.path === path);
  if (e) e.size = size;
  else {
    ws.index.push({ path, size, bin: isBinaryName(path) });
    sortIndex();
  }
}
function dropIndex(path) {
  ws.index = ws.index.filter((x) => x.path !== path);
}
const byteLen = (s) => new TextEncoder().encode(s).length;

function rebuildVirtualIndex() {
  ws.index = [...vfiles.entries()].map(([path, text]) => ({ path, size: byteLen(text), bin: false }));
  sortIndex();
}

async function scanDir(dir, prefix, out) {
  for await (const [name, h] of dir.entries()) {
    if (out.length >= MAX_FILES) return;
    if (h.kind === 'directory') {
      if (IGNORE_DIRS.has(name) || (name.startsWith('.') && name !== '.github')) continue;
      await scanDir(h, `${prefix}${name}/`, out);
    } else {
      const path = prefix + name;
      if (isSecret(path)) continue;
      let size = 0;
      try { size = (await h.getFile()).size; } catch { /* нет доступа к размеру */ }
      out.push({ path, size, bin: isBinaryName(name) });
    }
  }
}

export async function rescan() {
  if (ws.kind === 'fs') {
    const out = [];
    await scanDir(ws.handle, '', out);
    ws.index = out;
    sortIndex();
  } else rebuildVirtualIndex();
  emit({ type: 'index' });
}

/* ---------- запуск и переключение источника ---------- */

export async function initWorkspace() {
  const stored = await safe(() => idb('files', 'readonly', (s) => s.getAll()));
  const keys = await safe(() => idb('files', 'readonly', (s) => s.getAllKeys()));
  ws.persistent = Array.isArray(stored);
  if (ws.persistent) keys.forEach((k, i) => vfiles.set(k, stored[i]));
  rebuildVirtualIndex();

  const h = await safe(() => idb('kv', 'readonly', (s) => s.get('handle')));
  if (h && hasFsApi) {
    let perm = 'prompt';
    try { perm = (await h.queryPermission?.({ mode: 'readwrite' })) || 'prompt'; } catch { /* оставим prompt */ }
    if (perm === 'granted') await attachHandle(h, { remember: false });
    else ws.pending = h;
  }
  ws.ready = true;
  emit({ type: 'kind' });
}

export async function attachHandle(handle, { remember = true } = {}) {
  ws.kind = 'fs';
  ws.handle = handle;
  ws.name = handle.name || 'Папка';
  ws.pending = null;
  ws.history = [];
  if (remember) await safe(() => idb('kv', 'readwrite', (s) => s.put(handle, 'handle')));
  await rescan();
  emit({ type: 'kind' });
}

export async function pickFolder() {
  const h = await window.showDirectoryPicker({ mode: 'readwrite' });
  await attachHandle(h);
}

export async function resumePending() {
  const h = ws.pending;
  if (!h) return false;
  const perm = await h.requestPermission({ mode: 'readwrite' });
  if (perm !== 'granted') return false;
  await attachHandle(h);
  return true;
}

export async function useVirtual() {
  ws.kind = 'virtual';
  ws.handle = null;
  ws.name = 'Песочница';
  ws.history = [];
  await safe(() => idb('kv', 'readwrite', (s) => s.delete('handle')));
  rebuildVirtualIndex();
  emit({ type: 'kind' });
}

/* ---------- файлы ---------- */

async function fsFile(path, create) {
  const parts = path.split('/');
  let dir = ws.handle;
  for (const d of parts.slice(0, -1)) dir = await dir.getDirectoryHandle(d, { create });
  return dir.getFileHandle(parts[parts.length - 1], { create });
}

export function exists(path) {
  return ws.index.some((x) => x.path === path);
}

export async function readText(rawPath, max = MAX_READ) {
  const path = normPath(rawPath);
  if (isSecret(path)) throw new Error('Файл с секретами, его читать нельзя');
  if (isBinaryName(path)) throw new Error('Бинарный файл');
  if (ws.kind === 'virtual') {
    if (!vfiles.has(path)) throw new Error(`Файла нет: ${path}`);
    return vfiles.get(path);
  }
  let file;
  try { file = await (await fsFile(path, false)).getFile(); } catch { throw new Error(`Файла нет: ${path}`); }
  if (file.size > max) throw new Error(`Файл слишком большой (${Math.round(file.size / 1024)} КБ)`);
  return file.text();
}

// Читает с диска. null: файла точно нет. Бросает ошибку, если файл есть, но прочитать нельзя.
export async function peekText(rawPath, max = MAX_READ) {
  const path = normPath(rawPath);
  if (isSecret(path)) throw new Error('Файл с секретами');
  if (isBinaryName(path)) throw new Error('Бинарный файл');
  if (ws.kind === 'virtual') return vfiles.has(path) ? vfiles.get(path) : null;
  let fh;
  try { fh = await fsFile(path, false); } catch (e) {
    if (e && e.name === 'NotFoundError') return null;
    throw e;
  }
  const file = await fh.getFile();
  if (file.size > max) throw new Error(`Файл слишком большой (${Math.round(file.size / 1024)} КБ)`);
  return file.text();
}

export async function readBytes(rawPath, max = 2_000_000) {
  const path = normPath(rawPath);
  if (isSecret(path)) throw new Error('Файл с секретами');
  if (ws.kind === 'virtual') {
    if (!vfiles.has(path)) throw new Error(`Файла нет: ${path}`);
    return new TextEncoder().encode(vfiles.get(path));
  }
  const file = await (await fsFile(path, false)).getFile();
  if (file.size > max) throw new Error('Файл слишком большой');
  return new Uint8Array(await file.arrayBuffer());
}

export async function writeText(rawPath, text) {
  const path = normPath(rawPath);
  if (isSecret(path)) throw new Error('Файлы с секретами создавать и менять нельзя');
  if (isBinaryName(path)) throw new Error('Бинарные файлы писать нельзя');
  const data = String(text);
  if (data.length > 2_000_000) throw new Error('Файл больше 2 МБ');
  if (ws.kind === 'virtual') {
    vfiles.set(path, data);
    if (ws.persistent) await safe(() => idb('files', 'readwrite', (s) => s.put(data, path)));
  } else {
    const fh = await fsFile(path, true);
    const w = await fh.createWritable();
    await w.write(data);
    await w.close();
  }
  upsert(path, byteLen(data));
  emit({ type: 'file', path });
  return path;
}

export async function removePath(rawPath) {
  const path = normPath(rawPath);
  if (ws.kind === 'virtual') {
    if (!vfiles.has(path)) throw new Error(`Файла нет: ${path}`);
    vfiles.delete(path);
    if (ws.persistent) await safe(() => idb('files', 'readwrite', (s) => s.delete(path)));
  } else {
    const parts = path.split('/');
    let dir = ws.handle;
    try {
      for (const d of parts.slice(0, -1)) dir = await dir.getDirectoryHandle(d);
      await dir.removeEntry(parts[parts.length - 1]);
    } catch {
      throw new Error(`Файла нет: ${path}`);
    }
  }
  dropIndex(path);
  emit({ type: 'file', path });
}

export async function clearVirtual() {
  vfiles.clear();
  if (ws.persistent) await safe(() => idb('files', 'readwrite', (s) => s.clear()));
  rebuildVirtualIndex();
  ws.history = [];
  emit({ type: 'index' });
}

/* ---------- обзор для агента ---------- */

export function treeText(limit = 150, prefix = '') {
  const pre = prefix ? normPath(prefix.replace(/\/+$/, '')) + '/' : '';
  const rows = ws.index.filter((x) => x.path.startsWith(pre));
  const shown = rows.slice(0, limit).map((x) => `${x.path}${x.bin ? ' (бинарный)' : ''} · ${x.size} Б`);
  if (rows.length > limit) shown.push(`…и ещё ${rows.length - limit} файлов`);
  return shown.join('\n');
}

export async function searchText(query, { max = 60, regex = false } = {}) {
  let re;
  if (regex && (query.length > 200 || /\\\d|\([^)]*[+*][^)]*\)\s*[+*{]/.test(query))) {
    throw new Error('Слишком сложное регулярное выражение (вложенные повторы или обратные ссылки). Упрости или ищи обычным текстом.');
  }
  try {
    re = regex ? new RegExp(query, 'i') : new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
  } catch {
    throw new Error('Некорректное регулярное выражение');
  }
  const hits = [];
  let budget = 4_000_000;
  const deadline = Date.now() + 2500;
  for (const f of ws.index) {
    if (f.bin || f.size > 300_000 || budget <= 0 || Date.now() > deadline) continue;
    let text;
    try { text = await readText(f.path, 300_000); } catch { continue; }
    budget -= text.length;
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (re.test(lines[i].slice(0, 400))) {
        hits.push(`${f.path}:${i + 1}: ${lines[i].trim().slice(0, 160)}`);
        if (hits.length >= max) return { hits, more: true };
      }
    }
  }
  return { hits, more: false };
}

export async function importFiles(fileList) {
  let n = 0;
  let skipped = 0;
  const changes = [];
  for (const f of fileList) {
    const name = f.webkitRelativePath || f.name;
    if (isBinaryName(name) || f.size > 1_000_000 || isSecret(name)) {
      skipped++;
      continue;
    }
    try {
      const text = await f.text();
      if (text.includes('\u0000')) { skipped++; continue; }
      const path = normPath(name);
      let before = null;
      try { before = await peekText(path); } catch { before = null; }
      await writeText(path, text);
      changes.push({ path, before, after: text });
      n++;
    } catch {
      skipped++;
    }
  }
  if (changes.length) recordChange(changes.length === 1 ? `Загружен ${changes[0].path}` : `Загружено файлов: ${changes.length}`, changes);
  return { n, skipped };
}

// Текстовые файлы проекта для отправки на сервер (публикация, коммит). Бинарные пропускаются.
export async function collectText(maxTotal = 3_500_000) {
  const files = [];
  let total = 0;
  let skipped = 0;
  for (const f of ws.index) {
    if (f.bin || isSecret(f.path)) { skipped++; continue; }
    let text;
    try { text = await readText(f.path, 1_000_000); } catch { skipped++; continue; }
    total += byteLen(text);
    if (total > maxTotal) throw new Error('Проект больше 3,5 МБ текста, отправить целиком не получится');
    files.push({ path: f.path, data: text });
  }
  return { files, skipped };
}

export async function zipProject() {
  const files = [];
  let total = 0;
  for (const f of ws.index) {
    if (total > 30_000_000) break;
    try {
      const data = f.bin ? await readBytes(f.path, 5_000_000) : await readText(f.path, 2_000_000);
      files.push({ path: f.path, data });
      total += f.size;
    } catch { /* пропускаем нечитаемое */ }
  }
  return makeZip(files);
}

/* ---------- история правок и откат ---------- */

let seq = 0;
export function recordChange(label, changes) {
  const entry = { id: `c${Date.now().toString(36)}${++seq}`, ts: Date.now(), label, changes, undone: false };
  ws.history.unshift(entry);
  if (ws.history.length > 80) ws.history.length = 80;
  emit({ type: 'history', id: entry.id });
  return entry;
}

// Откат одной записи журнала. Если файл с тех пор менялся (после этой правки), без force откат
// не делаем: иначе молча потеряем чужую работу.
export async function undoEntry(id, { force = false } = {}) {
  const e = ws.history.find((x) => x.id === id);
  if (!e || e.undone) return false;
  if (!force) {
    const conflicts = [];
    for (const c of e.changes) {
      let cur;
      try { cur = await peekText(c.path); } catch { cur = undefined; }
      if (cur !== c.after && !(cur === null && c.after === null)) conflicts.push(c.path);
    }
    if (conflicts.length) {
      throw Object.assign(new Error(`После этой правки файл менялся: ${conflicts.slice(0, 3).join(', ')}${conflicts.length > 3 ? '…' : ''}. Откат затрёт новые изменения.`), { code: 'CONFLICT' });
    }
  }
  for (const c of [...e.changes].reverse()) {
    if (c.before === null) {
      if (exists(c.path)) await removePath(c.path);
    } else await writeText(c.path, c.before);
  }
  e.undone = true;
  emit({ type: 'history', id });
  return true;
}

// Откат с вопросом при конфликте. Возвращает true, если откатили.
export async function undoWithConfirm(id, ask) {
  try {
    return await undoEntry(id);
  } catch (err) {
    if (err.code === 'CONFLICT' && (await ask(`${err.message} Откатить всё равно?`))) return undoEntry(id, { force: true });
    if (err.code === 'CONFLICT') return false;
    throw err;
  }
}
