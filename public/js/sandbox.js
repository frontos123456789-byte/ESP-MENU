// Песочница для кода, который пишет модель. Всё выполняется в iframe БЕЗ allow-same-origin:
// у страницы нет доступа ни к ключам, ни к localStorage Пульта, ни к его DOM.
// Консоль и ошибки уходят наружу через postMessage.

import * as W from './workspace.js';

const MAX_LOGS = 600;
export const logs = []; // { id, level, text, ts, src }
const subs = new Set();
const active = new Map(); // id -> src ('preview' | 'run')

export function onLog(fn) {
  subs.add(fn);
  return () => subs.delete(fn);
}
const notify = () => { for (const fn of subs) fn(); };

export function clearLogs() {
  logs.length = 0;
  notify();
}

let counter = 0;
export function newRun(src = 'preview') {
  const id = `r${Date.now().toString(36)}${++counter}`;
  active.set(id, src);
  if (active.size > 40) active.delete(active.keys().next().value);
  return id;
}

export function logsOf(id) {
  return logs.filter((l) => l.id === id);
}

export function pushLog(id, level, text, src) {
  logs.push({ id, level, text: String(text).slice(0, 2000), ts: Date.now(), src: src || active.get(id) || 'preview' });
  if (logs.length > MAX_LOGS) logs.splice(0, logs.length - MAX_LOGS);
  notify();
}

if (typeof window !== 'undefined') {
  window.addEventListener('message', (e) => {
    const d = e.data;
    if (!d || d.__pult !== 1 || !active.has(d.id)) return;
    if (d.done) return doneHooks.get(d.id)?.();
    pushLog(d.id, d.level, d.text);
  });
}
const doneHooks = new Map();

function captureScript(id) {
  return (
    `<script>(function(){var id=${JSON.stringify(id)};` +
    `function s(a){try{if(typeof a==='string')return a;if(a instanceof Error)return a.stack||a.message;` +
    `return JSON.stringify(a,function(k,v){return typeof v==='function'?'[function]':v})}catch(e){return String(a)}}` +
    `function send(l,args){try{parent.postMessage({__pult:1,id:id,level:l,text:args.map(s).join(' ')},'*')}catch(e){}}` +
    `['log','info','warn','error','debug'].forEach(function(l){var o=console[l];console[l]=function(){send(l,[].slice.call(arguments));try{o.apply(console,arguments)}catch(e){}}});` +
    `addEventListener('error',function(e){send('error',[(e.message||'Ошибка')+(e.filename&&e.lineno?' (строка '+e.lineno+')':'')])});` +
    `addEventListener('unhandledrejection',function(e){send('error',['Promise: '+s(e.reason)])});})();<\/script>`
  );
}

function injectHead(html, snippet) {
  const doctype = html.match(/^\s*<!doctype[^>]*>/i);
  if (/<head[^>]*>/i.test(html)) return html.replace(/<head[^>]*>/i, (m) => m + snippet);
  if (doctype) return html.slice(0, doctype[0].length) + snippet + html.slice(doctype[0].length);
  return snippet + html;
}

/* ---------- сборка html из файлов проекта в один документ ---------- */

function b64(bytes) {
  let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}
const utf8 = (s) => new TextEncoder().encode(s);

const MIME = {
  png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', webp: 'image/webp', svg: 'image/svg+xml', ico: 'image/x-icon',
  avif: 'image/avif', mp3: 'audio/mpeg', wav: 'audio/wav', ogg: 'audio/ogg', mp4: 'video/mp4', webm: 'video/webm',
  woff: 'font/woff', woff2: 'font/woff2', ttf: 'font/ttf', otf: 'font/otf', json: 'application/json', txt: 'text/plain', css: 'text/css', js: 'text/javascript',
};
const extOf = (p) => p.split('.').pop().toLowerCase();

function resolve(baseDir, spec) {
  const clean = spec.split(/[?#]/)[0];
  const parts = (clean.startsWith('/') ? [] : baseDir.split('/').filter(Boolean)).concat(clean.split('/'));
  const out = [];
  for (const p of parts) {
    if (!p || p === '.') continue;
    if (p === '..') out.pop();
    else out.push(p);
  }
  return out.join('/');
}
const isExternal = (s) => /^(?:[a-z][a-z0-9+.-]*:|\/\/|#)/i.test(s);
const dirOf = (p) => (p.includes('/') ? p.slice(0, p.lastIndexOf('/') + 1) : '');

async function replaceAsync(str, re, fn) {
  const jobs = [];
  str.replace(re, (...a) => {
    jobs.push(fn(...a));
    return '';
  });
  const res = await Promise.all(jobs);
  let i = 0;
  return str.replace(re, () => res[i++]);
}

async function build(entry, id) {
  const budget = { left: 10_000_000 };
  const memo = new Map();

  const dataUrl = async (path) => {
    if (memo.has('d:' + path)) return memo.get('d:' + path);
    const bytes = await W.readBytes(path);
    budget.left -= bytes.length;
    if (budget.left < 0) throw new Error('слишком много ресурсов');
    const url = `data:${MIME[extOf(path)] || 'application/octet-stream'};base64,${b64(bytes)}`;
    memo.set('d:' + path, url);
    return url;
  };

  const findModule = (path) => [path, `${path}.js`, `${path}/index.js`].find((p) => W.exists(p));

  const moduleUrl = async (path, stack) => {
    if (memo.has('m:' + path)) return memo.get('m:' + path);
    let src = await W.readText(path);
    src = await replaceAsync(src, /(\bfrom\s*|\bimport\s*\(?\s*)(['"])((?:\.{1,2}\/|\/)[^'"\n]+)\2/g, async (m, pre, q, spec) => {
      const target = findModule(resolve(dirOf(path), spec));
      if (!target || stack.includes(target)) return m;
      return `${pre}${q}${await moduleUrl(target, [...stack, path])}${q}`;
    });
    budget.left -= src.length;
    const url = `data:text/javascript;base64,${b64(utf8(src))}`;
    memo.set('m:' + path, url);
    return url;
  };

  const css = async (text, base) =>
    replaceAsync(text, /url\(\s*(['"]?)([^'")]+)\1\s*\)/g, async (m, q, spec) => {
      if (isExternal(spec)) return m;
      const p = resolve(base, spec);
      if (!W.exists(p)) return m;
      try { return `url("${await dataUrl(p)}")`; } catch { return m; }
    });

  const html = await W.readText(entry);
  const base = dirOf(entry);
  let out = html;

  out = await replaceAsync(out, /<link\b[^>]*>/gi, async (tag) => {
    if (!/rel\s*=\s*["']?stylesheet/i.test(tag)) return tag;
    const href = tag.match(/href\s*=\s*["']([^"']+)["']/i)?.[1];
    if (!href || isExternal(href)) return tag;
    const p = resolve(base, href);
    if (!W.exists(p)) return tag;
    try { return `<style>/* ${p} */\n${await css(await W.readText(p), dirOf(p))}\n</style>`; } catch { return tag; }
  });

  out = await replaceAsync(out, /<script\b([^>]*)\bsrc\s*=\s*["']([^"']+)["']([^>]*)>\s*<\/script>/gi, async (tag, a1, src, a2) => {
    if (isExternal(src)) return tag;
    const p = resolve(base, src);
    if (!W.exists(p)) return tag;
    const attrs = `${a1} ${a2}`.replace(/\s+/g, ' ').trim();
    try {
      const code = await W.readText(p);
      if (/type\s*=\s*["']module/i.test(attrs)) {
        const url = await moduleUrl(p, []);
        // инлайн-модуль, который импортирует собранный data-url
        return `<script type="module">import ${JSON.stringify(url)};<\/script>`;
      }
      return `<script ${attrs}>/* ${p} */\n${code.replace(/<\/script/gi, '<\\/script')}\n<\/script>`;
    } catch { return tag; }
  });

  out = await replaceAsync(out, /<script\b([^>]*)type\s*=\s*["']module["']([^>]*)>([\s\S]*?)<\/script>/gi, async (tag, a1, a2, code) => {
    if (/\bsrc\s*=/.test(a1 + a2) || !/(\bfrom\s*|\bimport\s*\(?\s*)['"](?:\.{1,2}\/|\/)/.test(code)) return tag;
    let res = code;
    res = await replaceAsync(res, /(\bfrom\s*|\bimport\s*\(?\s*)(['"])((?:\.{1,2}\/|\/)[^'"\n]+)\2/g, async (m, pre, q, spec) => {
      const target = findModule(resolve(base, spec));
      if (!target) return m;
      try { return `${pre}${q}${await moduleUrl(target, [])}${q}`; } catch { return m; }
    });
    return `<script${a1}type="module"${a2}>${res}<\/script>`;
  });

  out = await replaceAsync(out, /<style\b[^>]*>([\s\S]*?)<\/style>/gi, async (tag, body) => (/url\(/.test(body) ? tag.replace(body, await css(body, base)) : tag));

  out = await replaceAsync(out, /\b(src|poster|href)\s*=\s*(["'])([^"']+)\2/gi, async (m, attr, q, spec) => {
    if (isExternal(spec)) return m;
    const ext = extOf(spec.split(/[?#]/)[0]);
    if (!MIME[ext] || ext === 'js' || ext === 'css') return m;
    const p = resolve(base, spec);
    if (!W.exists(p)) return m;
    try { return `${attr}=${q}${await dataUrl(p)}${q}`; } catch { return m; }
  });

  return injectHead(out, captureScript(id));
}

// Готовый документ для iframe.srcdoc: файл проекта целиком.
export async function docFromProject(path, id) {
  return build(W.normPath(path), id);
}

// Документ из фрагмента (кнопка «Превью» у блока кода в чате).
export function docFromSnippet(code, lang, id) {
  let html = code;
  if (lang === 'svg' || /^\s*<svg[\s>]/i.test(code)) {
    html = `<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;height:100%;display:grid;place-items:center;background:#fff}svg{max-width:100%;max-height:100vh}</style></head><body>${code}</body></html>`;
  } else if (!/<html|<!doctype/i.test(code)) {
    html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body>${code}</body></html>`;
  }
  return injectHead(html, captureScript(id));
}

/* ---------- фоновый запуск JS ---------- */

export function runJs(code, timeout = 5000) {
  return new Promise((resolve) => {
    const id = newRun('run');
    const frame = document.createElement('iframe');
    frame.setAttribute('sandbox', 'allow-scripts');
    frame.setAttribute('aria-hidden', 'true');
    frame.style.cssText = 'position:fixed;width:0;height:0;border:0;opacity:0;pointer-events:none';
    let finished = false;
    const finish = (timedOut) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      doneHooks.delete(id);
      const mine = logsOf(id);
      frame.remove();
      resolve({ logs: mine.map((l) => ({ level: l.level, text: l.text })), timedOut });
    };
    const timer = setTimeout(() => finish(true), timeout);
    doneHooks.set(id, () => setTimeout(() => finish(false), 250));
    const body = String(code).replace(/<\/script/gi, '<\\/script');
    frame.srcdoc =
      `<!doctype html><html><body>${captureScript(id)}<script>` +
      `window.addEventListener('error',function(){setTimeout(function(){parent.postMessage({__pult:1,id:${JSON.stringify(id)},done:1},'*')},60)});` +
      `(async function(){try{\n${body}\n}catch(e){console.error(e&&e.stack||String(e))}finally{parent.postMessage({__pult:1,id:${JSON.stringify(id)},done:1},'*')}})();<\/script></body></html>`;
    document.body.append(frame);
  });
}
