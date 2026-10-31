'use strict';

const crypto = require('crypto');

function send(res, status, body, headers) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  if (headers) for (const [k, v] of Object.entries(headers)) res.setHeader(k, v);
  res.end(JSON.stringify(body));
}

function fail(status, message, code) {
  const e = new Error(message);
  e.status = status;
  if (code) e.code = code;
  return e;
}

async function readJson(req) {
  if (req.body !== undefined && req.body !== null) {
    if (typeof req.body === 'object' && !Buffer.isBuffer(req.body)) return req.body;
    const raw = Buffer.isBuffer(req.body) ? req.body.toString('utf8') : String(req.body);
    return raw ? safeParse(raw) : {};
  }
  const chunks = [];
  let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > 4_000_000) throw fail(413, 'Слишком большой запрос');
    chunks.push(c);
  }
  const raw = Buffer.concat(chunks).toString('utf8');
  return raw ? safeParse(raw) : {};
}

function safeParse(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    throw fail(400, 'Некорректный JSON в запросе');
  }
}

function sameString(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  if (x.length !== y.length) return false;
  return crypto.timingSafeEqual(x, y);
}

// Если на сервере задан ACCESS_CODE, без него закрываем чат и коннекторы.
function requireAccess(req) {
  const need = process.env.ACCESS_CODE;
  if (!need) return;
  const got = req.headers['x-access-code'];
  if (!got || !sameString(got, need)) {
    throw fail(401, 'Нужен код доступа. Введи его в Настройки → Доступ.', 'access');
  }
}

function query(req) {
  return new URL(req.url, 'http://local').searchParams;
}

// Обёртка: ловит ошибки и отдаёт их JSON-ом.
function handler(fn) {
  return async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      const status = err.status || 500;
      if (res.headersSent) {
        try { res.end(); } catch { /* уже закрыто */ }
        return;
      }
      send(res, status, { error: err.message || 'Ошибка сервера', code: err.code || undefined });
    }
  };
}

function cut(text, max) {
  if (text.length <= max) return { text, truncated: false };
  return { text: text.slice(0, max), truncated: true };
}

// Файлы проекта из браузера: [{ path, data }] без путей-ловушек и секретов.
function cleanFiles(list, { max = 300 } = {}) {
  if (!Array.isArray(list) || !list.length) throw fail(400, 'Нет файлов для отправки');
  if (list.length > max) throw fail(400, `Слишком много файлов (больше ${max})`);
  const out = [];
  const seen = new Set();
  for (const f of list) {
    const path = typeof f?.path === 'string' ? f.path.replace(/\\/g, '/').replace(/^\.?\/+/, '') : '';
    if (!path || path.length > 300 || path.split('/').some((x) => x === '' || x === '.' || x === '..' || x === '.git')) throw fail(400, `Некорректный путь: ${String(f?.path).slice(0, 80)}`);
    if (/(^|\/)(\.env(\..*)?|[^/]*\.pem|id_rsa[^/]*)$/i.test(path)) throw fail(400, `Секретный файл не отправляю: ${path}`);
    if (typeof f.data !== 'string') throw fail(400, `У файла ${path} нет содержимого`);
    if (seen.has(path)) continue;
    seen.add(path);
    out.push({ path, data: f.data });
  }
  return out;
}

module.exports = { send, fail, readJson, requireAccess, query, handler, cut, cleanFiles };
