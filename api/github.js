'use strict';

const { send, fail, readJson, requireAccess, query, handler, cut, cleanFiles } = require('./_lib');

const API = () => (process.env.GITHUB_API_URL || 'https://api.github.com').replace(/\/+$/, '');
const MAX_FILE = 60_000;
const SKIP_EXT = /\.(png|jpe?g|gif|webp|ico|svg|pdf|zip|gz|tgz|rar|7z|mp3|mp4|mov|webm|woff2?|ttf|otf|eot|exe|dll|so|dylib|bin|wasm|lock|map|min\.js)$/i;
const SKIP_DIR = /(^|\/)(node_modules|\.git|\.next|dist|build|coverage|vendor|__pycache__)(\/|$)/;

async function gh(path, token, accept) {
  const r = await fetch(`${API()}${path}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: accept || 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'pult-app',
    },
    signal: AbortSignal.timeout(15000),
  });
  if (!r.ok) {
    if (r.status === 401) throw fail(401, 'GitHub не принял токен. Проверь, что он верный и не истёк.', 'badtoken');
    if (r.status === 403 || r.status === 429) throw fail(429, 'GitHub ограничил запросы или у токена нет прав. Попробуй позже.', 'gh_limit');
    if (r.status === 404) throw fail(404, 'Не найдено. Проверь репозиторий и права токена.');
    throw fail(502, `GitHub ответил ${r.status}`);
  }
  return r;
}

async function ghw(method, path, token, body) {
  const r = await fetch(`${API()}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'Content-Type': 'application/json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'pult-app',
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(20000),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) {
    if (r.status === 401) throw fail(401, 'GitHub не принял токен.', 'badtoken');
    if (r.status === 403 || r.status === 404) throw fail(403, 'У токена нет прав на запись в этот репозиторий (нужен доступ Contents: write).', 'gh_write');
    throw Object.assign(fail(r.status === 422 ? 422 : 502, `GitHub: ${j.message || r.status}`), { upstream: r.status });
  }
  return j;
}

function parseRepo(v) {
  if (typeof v !== 'string' || !/^[\w.-]+\/[\w.-]+$/.test(v)) throw fail(400, 'Некорректное имя репозитория');
  return v;
}

function encPath(p) {
  if (typeof p !== 'string' || !p || p.includes('..') || p.startsWith('/')) throw fail(400, 'Некорректный путь');
  return p.split('/').map(encodeURIComponent).join('/');
}

module.exports = handler(async (req, res) => {
  requireAccess(req);
  const token = String(req.headers['x-github-token'] || '').trim();
  if (!token) throw fail(400, 'Нет токена GitHub. Добавь его в Коннекторы.', 'notoken');

  const q = query(req);
  const op = q.get('op');

  if (op === 'commit') {
    if (req.method !== 'POST') throw fail(405, 'Только POST');
    const body = await readJson(req);
    const repo = parseRepo(body.repo);
    const files = cleanFiles(body.files);
    const message = String(body.message || 'Обновление из Пульта').slice(0, 200);
    const info = await (await gh(`/repos/${repo}`, token)).json();
    const base = info.default_branch || 'main';
    let branch = String(body.branch || '').trim();
    if (branch && !/^[\w./-]{1,80}$/.test(branch)) throw fail(400, 'Некорректное имя ветки');
    if (!branch) branch = `pult-${new Date().toISOString().slice(0, 10)}-${Math.random().toString(36).slice(2, 6)}`;

    let head = null;
    try { head = (await ghw('GET', `/repos/${repo}/git/ref/heads/${branch}`, token)).object.sha; } catch { /* ветки ещё нет */ }
    if (!head) {
      const baseSha = (await ghw('GET', `/repos/${repo}/git/ref/heads/${base}`, token)).object.sha;
      await ghw('POST', `/repos/${repo}/git/refs`, token, { ref: `refs/heads/${branch}`, sha: baseSha });
      head = baseSha;
    }
    const baseTree = (await ghw('GET', `/repos/${repo}/git/commits/${head}`, token)).tree.sha;
    const tree = await ghw('POST', `/repos/${repo}/git/trees`, token, {
      base_tree: baseTree,
      tree: files.map((f) => ({ path: f.path, mode: '100644', type: 'blob', content: f.data })),
    });
    const commit = await ghw('POST', `/repos/${repo}/git/commits`, token, { message, tree: tree.sha, parents: [head] });
    await ghw('PATCH', `/repos/${repo}/git/refs/heads/${branch}`, token, { sha: commit.sha });
    return send(res, 200, { branch, base, sha: commit.sha, url: `https://github.com/${repo}/tree/${branch}`, compare: `https://github.com/${repo}/compare/${base}...${branch}`, files: files.length });
  }

  if (op === 'repos') {
    const r = await gh('/user/repos?per_page=100&sort=pushed&affiliation=owner,collaborator,organization_member', token);
    const j = await r.json();
    return send(res, 200, {
      repos: j.map((x) => ({
        full_name: x.full_name,
        private: x.private,
        description: x.description || '',
        language: x.language || '',
        pushed_at: x.pushed_at,
        default_branch: x.default_branch,
      })),
    });
  }

  const repo = parseRepo(q.get('repo'));

  if (op === 'tree') {
    let ref = q.get('ref');
    if (!ref) {
      const meta = await (await gh(`/repos/${repo}`, token)).json();
      ref = meta.default_branch;
    }
    const r = await gh(`/repos/${repo}/git/trees/${encodeURIComponent(ref)}?recursive=1`, token);
    const j = await r.json();
    const files = (j.tree || [])
      .filter((n) => n.type === 'blob' && n.size <= 200_000 && !SKIP_EXT.test(n.path) && !SKIP_DIR.test(n.path))
      .slice(0, 4000)
      .map((n) => ({ path: n.path, size: n.size }));
    return send(res, 200, { ref, files, truncated: Boolean(j.truncated) });
  }

  if (op === 'file') {
    const path = encPath(q.get('path'));
    const ref = q.get('ref');
    const r = await gh(`/repos/${repo}/contents/${path}${ref ? `?ref=${encodeURIComponent(ref)}` : ''}`, token, 'application/vnd.github.raw+json');
    const raw = await r.text();
    if (raw.includes('\u0000')) throw fail(415, 'Это бинарный файл, в контекст не добавить.');
    const c = cut(raw, MAX_FILE);
    return send(res, 200, { path: q.get('path'), content: c.text, truncated: c.truncated, size: raw.length });
  }

  if (op === 'commits') {
    const r = await gh(`/repos/${repo}/commits?per_page=20`, token);
    const j = await r.json();
    return send(res, 200, {
      commits: j.map((c) => ({
        sha: c.sha.slice(0, 7),
        message: String(c.commit.message || '').split('\n')[0],
        author: c.commit.author?.name || '',
        date: c.commit.author?.date || '',
      })),
    });
  }

  if (op === 'issues') {
    const r = await gh(`/repos/${repo}/issues?state=open&per_page=25`, token);
    const j = await r.json();
    return send(res, 200, {
      issues: j.map((i) => ({
        number: i.number,
        title: i.title,
        pr: Boolean(i.pull_request),
        author: i.user?.login || '',
        body: String(i.body || '').slice(0, 1200),
      })),
    });
  }

  throw fail(400, 'Неизвестная операция');
});
