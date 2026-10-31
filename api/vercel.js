'use strict';

const { send, fail, readJson, requireAccess, query, handler, cut, cleanFiles } = require('./_lib');

const API = () => (process.env.VERCEL_API_URL || 'https://api.vercel.com').replace(/\/+$/, '');

async function vc(path, token, team) {
  const u = new URL(API() + path);
  if (team) u.searchParams.set('teamId', team);
  const r = await fetch(u, {
    headers: { Authorization: `Bearer ${token}`, 'User-Agent': 'pult-app' },
    signal: AbortSignal.timeout(15000),
  });
  if (!r.ok) {
    if (r.status === 401 || r.status === 403) throw fail(401, 'Vercel не принял токен или нет доступа к этой команде.', 'badtoken');
    if (r.status === 404) throw fail(404, 'Не найдено. Проверь проект и Team ID.');
    if (r.status === 429) throw fail(429, 'Vercel ограничил запросы, попробуй позже.', 'vc_limit');
    throw fail(502, `Vercel ответил ${r.status}`);
  }
  return r;
}

function id(v, label) {
  if (typeof v !== 'string' || !/^[\w.:-]{3,120}$/.test(v)) throw fail(400, `Некорректный ${label}`);
  return v;
}

module.exports = handler(async (req, res) => {
  requireAccess(req);
  const token = String(req.headers['x-vercel-token'] || '').trim();
  if (!token) throw fail(400, 'Нет токена Vercel. Добавь его в Коннекторы.', 'notoken');
  const teamRaw = String(req.headers['x-vercel-team'] || '').trim();
  const team = teamRaw ? id(teamRaw, 'Team ID') : '';

  const q = query(req);
  const op = q.get('op');

  if (op === 'projects') {
    const j = await (await vc('/v9/projects?limit=60', token, team)).json();
    return send(res, 200, {
      projects: (j.projects || []).map((p) => ({
        id: p.id,
        name: p.name,
        framework: p.framework || '',
        updatedAt: p.updatedAt,
        repo: p.link?.repo ? `${p.link.org || ''}/${p.link.repo}`.replace(/^\//, '') : '',
      })),
    });
  }

  if (op === 'deployments') {
    const projectId = id(q.get('project'), 'проект');
    const j = await (await vc(`/v6/deployments?projectId=${encodeURIComponent(projectId)}&limit=12`, token, team)).json();
    return send(res, 200, {
      deployments: (j.deployments || []).map((d) => ({
        id: d.uid,
        url: d.url,
        state: d.readyState || d.state || '',
        target: d.target || 'preview',
        createdAt: d.createdAt || d.created,
        message: d.meta?.githubCommitMessage || d.meta?.gitlabCommitMessage || '',
        branch: d.meta?.githubCommitRef || '',
      })),
    });
  }

  if (op === 'logs') {
    const dep = id(q.get('deployment'), 'деплой');
    const r = await vc(`/v3/deployments/${encodeURIComponent(dep)}/events?direction=backward&limit=200`, token, team);
    const raw = await r.text();
    let events = [];
    try {
      const j = JSON.parse(raw);
      events = Array.isArray(j) ? j : j.events || [];
    } catch {
      events = raw.split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
    }
    const lines = events
      .map((e) => e.text ?? e.payload?.text ?? '')
      .filter(Boolean)
      .reverse();
    const c = cut(lines.join('\n'), 30_000);
    return send(res, 200, { log: c.text, lines: lines.length, truncated: c.truncated });
  }

  if (op === 'deploy') {
    if (req.method !== 'POST') throw fail(405, 'Только POST');
    const body = await readJson(req);
    const name = String(body.name || '').toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60);
    if (name.length < 2) throw fail(400, 'Нужно имя проекта латиницей (минимум 2 символа)');
    const files = cleanFiles(body.files);
    const u = new URL(API() + '/v13/deployments');
    if (team) u.searchParams.set('teamId', team);
    u.searchParams.set('skipAutoDetectionConfirmation', '1');
    const r = await fetch(u, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', 'User-Agent': 'pult-app' },
      body: JSON.stringify({
        name,
        target: 'production',
        files: files.map((f) => ({ file: f.path, data: f.data, encoding: 'utf-8' })),
        projectSettings: { framework: null },
      }),
      signal: AbortSignal.timeout(40000),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) {
      if (r.status === 401 || r.status === 403) throw fail(401, 'Vercel не принял токен или нет прав на деплой.', 'badtoken');
      if (r.status === 429) throw fail(429, 'Vercel ограничил запросы, попробуй позже.', 'vc_limit');
      throw fail(r.status === 400 || r.status === 409 || r.status === 422 ? 400 : 502, `Vercel: ${j.error?.message || r.status}`);
    }
    return send(res, 200, {
      id: j.id,
      state: j.readyState || j.status || '',
      url: j.url ? `https://${j.url}` : '',
      productionUrl: `https://${j.name || name}.vercel.app`,
    });
  }

  throw fail(400, 'Неизвестная операция');
});
