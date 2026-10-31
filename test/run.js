'use strict';

// Проверка API без интернета: поднимаем мок OpenRouter/GitHub/Vercel и гоняем наши функции.
const http = require('http');
const assert = require('assert');

const results = [];
async function check(name, fn) {
  try {
    await fn();
    results.push(['ok', name]);
  } catch (e) {
    results.push(['FAIL', name + ' → ' + e.message]);
  }
}

function listen(server) {
  return new Promise((r) => server.listen(0, '127.0.0.1', () => r(server.address().port)));
}

(async () => {
  const seen = { auth: null, body: null, calls: [] };

  const mock = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    let raw = '';
    req.on('data', (c) => (raw += c));
    req.on('end', () => {
      const json = (code, obj) => {
        res.writeHead(code, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(obj));
      };
      if (url.pathname === '/or/models') {
        return json(200, {
          data: [
            { id: 'a/small:free', name: 'Small (free)', context_length: 8000, pricing: { prompt: '0', completion: '0' }, architecture: { output_modalities: ['text'], input_modalities: ['text'] } },
            { id: 'b/big:free', name: 'Big (free)', context_length: 200000, pricing: { prompt: '0', completion: '0' }, architecture: { output_modalities: ['text'], input_modalities: ['text', 'image'] } },
            { id: 'c/paid', name: 'Paid', context_length: 1000000, pricing: { prompt: '0.001', completion: '0.002' }, architecture: { output_modalities: ['text'] } },
            { id: 'thinkingmachines/inkling:free', name: 'Inkling (free)', context_length: 1048576, pricing: { prompt: '0', completion: '0' }, architecture: { output_modalities: ['text'], input_modalities: ['text'] } },
            { id: 'd/image:free', name: 'Img', context_length: 1, pricing: { prompt: '0', completion: '0' }, architecture: { output_modalities: ['image'] } },
          ],
        });
      }
      if (url.pathname === '/or/chat/completions') {
        seen.auth = req.headers.authorization;
        seen.body = JSON.parse(raw);
        if (seen.body.model === 'limit/me:free') return json(429, { error: { message: 'Rate limit' } });
        res.writeHead(200, { 'Content-Type': 'text/event-stream' });
        for (const t of ['При', 'вет', '!']) res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: t } }] })}\n\n`);
        res.write('data: [DONE]\n\n');
        return res.end();
      }
      if (url.pathname === '/gh/user/repos') {
        if (req.headers.authorization !== 'Bearer ghgood') return json(401, { message: 'Bad credentials' });
        return json(200, [{ full_name: 'me/app', private: true, description: 'd', language: 'JS', pushed_at: '2026-01-01', default_branch: 'main' }]);
      }
      if (url.pathname === '/gh/repos/me/app') return json(200, { default_branch: 'main' });
      if (url.pathname === '/gh/repos/me/app/git/trees/main') {
        return json(200, { tree: [
          { type: 'blob', path: 'src/index.js', size: 100 },
          { type: 'blob', path: 'logo.png', size: 100 },
          { type: 'blob', path: 'node_modules/x/y.js', size: 100 },
          { type: 'blob', path: 'big.js', size: 900000 },
          { type: 'tree', path: 'src', size: 0 },
        ] });
      }
      if (url.pathname === '/gh/repos/me/app/contents/src/index.js') {
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        return res.end('console.log("hi")');
      }
      if (url.pathname === '/gh/repos/me/app/commits') {
        return json(200, [{ sha: 'abcdef123456', commit: { message: 'fix: bug\n\nbody', author: { name: 'Me', date: '2026-01-02' } } }]);
      }
      if (url.pathname.startsWith('/gh/repos/me/app/git/') || url.pathname === '/vc/v13/deployments') {
        const b = raw ? JSON.parse(raw) : null;
        seen.calls.push(`${req.method} ${url.pathname}`);
        seen.last = b;
        if (url.pathname === '/vc/v13/deployments') {
          seen.deploy = { auth: req.headers.authorization, team: url.searchParams.get('teamId'), body: b };
          return json(200, { id: 'dpl_new', name: b.name, url: `${b.name}-abc.vercel.app`, readyState: 'QUEUED' });
        }
        if (url.pathname === '/gh/repos/me/app/git/ref/heads/main') return json(200, { object: { sha: 'base1' } });
        if (url.pathname.startsWith('/gh/repos/me/app/git/ref/heads/')) return json(404, { message: 'Not Found' });
        if (url.pathname === '/gh/repos/me/app/git/refs' && req.method === 'POST') return json(201, { ref: b.ref });
        if (url.pathname === '/gh/repos/me/app/git/commits/base1') return json(200, { tree: { sha: 'tree1' } });
        if (url.pathname === '/gh/repos/me/app/git/trees') { seen.tree = b; return json(201, { sha: 'tree2' }); }
        if (url.pathname === '/gh/repos/me/app/git/commits' && req.method === 'POST') { seen.commit = b; return json(201, { sha: 'commit9' }); }
        if (url.pathname.startsWith('/gh/repos/me/app/git/refs/heads/') && req.method === 'PATCH') return json(200, { object: { sha: b.sha } });
      }
      if (url.pathname === '/vc/v9/projects') {
        if (req.headers.authorization !== 'Bearer vcgood') return json(403, { error: { code: 'forbidden' } });
        return json(200, { projects: [{ id: 'prj_1', name: 'site', framework: 'nextjs', updatedAt: 1, link: { org: 'me', repo: 'site' } }] });
      }
      if (url.pathname === '/vc/v6/deployments') {
        seen.team = url.searchParams.get('teamId');
        return json(200, { deployments: [{ uid: 'dpl_1', url: 'site.vercel.app', readyState: 'ERROR', target: 'production', created: 5, meta: { githubCommitMessage: 'boom', githubCommitRef: 'main' } }] });
      }
      if (url.pathname === '/vc/v3/deployments/dpl_1/events') {
        return json(200, [{ text: 'line 2' }, { text: 'line 1' }]);
      }
      json(404, { error: 'nope' });
    });
  });
  const mockPort = await listen(mock);

  process.env.OPENROUTER_BASE_URL = `http://127.0.0.1:${mockPort}/or`;
  process.env.GITHUB_API_URL = `http://127.0.0.1:${mockPort}/gh`;
  process.env.VERCEL_API_URL = `http://127.0.0.1:${mockPort}/vc`;
  process.env.OPENROUTER_API_KEY = 'server-key';
  delete process.env.ACCESS_CODE;

  const { createServer } = require('../server');
  const app = createServer();
  const port = await listen(app);
  const base = `http://127.0.0.1:${port}`;
  const post = (body, headers) =>
    fetch(base + '/api/chat', { method: 'POST', headers: { 'Content-Type': 'application/json', ...(headers || {}) }, body: JSON.stringify(body) });
  const msgs = [{ role: 'user', content: 'привет' }];

  await check('models: только бесплатные текстовые, по контексту', async () => {
    const j = await (await fetch(base + '/api/models')).json();
    assert.deepStrictEqual(j.models.map((m) => m.id), ['b/big:free', 'a/small:free'], 'Inkling и платные не должны попадать');
    assert.strictEqual(j.models[0].name, 'Big');
    assert.strictEqual(j.models[0].vision, true);
    assert.strictEqual(j.fallback, false);
  });

  await check('models: запасной список, если OpenRouter недоступен', async () => {
    const old = process.env.OPENROUTER_BASE_URL;
    process.env.OPENROUTER_BASE_URL = 'http://127.0.0.1:1/or';
    const j = await (await fetch(base + '/api/models')).json();
    process.env.OPENROUTER_BASE_URL = old;
    assert.strictEqual(j.fallback, true);
    assert.ok(j.models.length >= 3);
  });

  await check('chat: стрим проходит насквозь с серверным ключом', async () => {
    const r = await post({ model: 'b/big:free', messages: msgs, temperature: 0.5 });
    assert.strictEqual(r.status, 200);
    assert.match(r.headers.get('content-type'), /event-stream/);
    const text = await r.text();
    const out = text.split('\n').filter((l) => l.startsWith('data: {')).map((l) => JSON.parse(l.slice(6)).choices[0].delta.content).join('');
    assert.strictEqual(out, 'Привет!');
    assert.strictEqual(seen.auth, 'Bearer server-key');
    assert.strictEqual(seen.body.stream, true);
    assert.strictEqual(seen.body.temperature, 0.5);
  });

  await check('chat: stop-последовательности доходят до модели (не больше четырёх)', async () => {
    const r = await post({ model: 'b/big:free', messages: msgs, stop: ['<tool_result', '', 7, 'a', 'b', 'c', 'd'] });
    await r.text();
    assert.deepStrictEqual(seen.body.stop, ['<tool_result', 'a', 'b', 'c']);
  });

  await check('chat: серверный ключ не пускает платные модели', async () => {
    const r = await post({ model: 'c/paid', messages: msgs });
    assert.strictEqual(r.status, 403);
    assert.strictEqual((await r.json()).code, 'notfree');
  });

  await check('chat: свой ключ пользователя работает с любой моделью', async () => {
    const r = await post({ model: 'c/paid', messages: msgs }, { 'x-openrouter-key': 'user-key' });
    assert.strictEqual(r.status, 200);
    await r.text();
    assert.strictEqual(seen.auth, 'Bearer user-key');
  });

  await check('chat: 429 апстрима превращается в понятный ответ', async () => {
    const r = await post({ model: 'limit/me:free', messages: msgs });
    assert.strictEqual(r.status, 429);
    const j = await r.json();
    assert.strictEqual(j.code, 'ratelimit');
    assert.match(j.error, /Rate limit/);
  });

  await check('chat: валидация входа', async () => {
    assert.strictEqual((await post({ model: '', messages: msgs })).status, 400);
    assert.strictEqual((await post({ model: 'x:free', messages: [] })).status, 400);
    assert.strictEqual((await fetch(base + '/api/chat')).status, 405);
  });

  await check('chat: без ключа вообще — код nokey', async () => {
    const old = process.env.OPENROUTER_API_KEY;
    delete process.env.OPENROUTER_API_KEY;
    const r = await post({ model: 'x:free', messages: msgs });
    process.env.OPENROUTER_API_KEY = old;
    assert.strictEqual(r.status, 400);
    assert.strictEqual((await r.json()).code, 'nokey');
  });

  await check('доступ: ACCESS_CODE закрывает чат и коннекторы', async () => {
    process.env.ACCESS_CODE = 'sesame';
    const bad = await post({ model: 'x:free', messages: msgs });
    const bad2 = await fetch(base + '/api/github?op=repos', { headers: { 'x-github-token': 'ghgood' } });
    const good = await post({ model: 'x:free', messages: msgs }, { 'x-access-code': 'sesame' });
    await good.text();
    delete process.env.ACCESS_CODE;
    assert.strictEqual(bad.status, 401);
    assert.strictEqual(bad2.status, 401);
    assert.strictEqual(good.status, 200);
  });

  await check('github: репозитории, дерево без мусора, файл, коммиты', async () => {
    const h = { 'x-github-token': 'ghgood' };
    const repos = await (await fetch(base + '/api/github?op=repos', { headers: h })).json();
    assert.strictEqual(repos.repos[0].full_name, 'me/app');
    const tree = await (await fetch(base + '/api/github?op=tree&repo=me/app', { headers: h })).json();
    assert.deepStrictEqual(tree.files.map((f) => f.path), ['src/index.js']);
    assert.strictEqual(tree.ref, 'main');
    const file = await (await fetch(base + '/api/github?op=file&repo=me/app&path=src/index.js', { headers: h })).json();
    assert.strictEqual(file.content, 'console.log("hi")');
    const commits = await (await fetch(base + '/api/github?op=commits&repo=me/app', { headers: h })).json();
    assert.deepStrictEqual(commits.commits[0], { sha: 'abcdef1', message: 'fix: bug', author: 'Me', date: '2026-01-02' });
  });

  await check('github: плохой токен, нет токена, подлый путь', async () => {
    const bad = await fetch(base + '/api/github?op=repos', { headers: { 'x-github-token': 'nope' } });
    assert.strictEqual(bad.status, 401);
    assert.strictEqual((await bad.json()).code, 'badtoken');
    assert.strictEqual((await fetch(base + '/api/github?op=repos')).status, 400);
    const h = { 'x-github-token': 'ghgood' };
    assert.strictEqual((await fetch(base + '/api/github?op=file&repo=me/app&path=../../etc/passwd', { headers: h })).status, 400);
    assert.strictEqual((await fetch(base + '/api/github?op=tree&repo=me/app;rm', { headers: h })).status, 400);
  });

  await check('vercel: проекты, деплои с team, лог в правильном порядке', async () => {
    const h = { 'x-vercel-token': 'vcgood', 'x-vercel-team': 'team_abc' };
    const p = await (await fetch(base + '/api/vercel?op=projects', { headers: h })).json();
    assert.strictEqual(p.projects[0].repo, 'me/site');
    const d = await (await fetch(base + '/api/vercel?op=deployments&project=prj_1', { headers: h })).json();
    assert.strictEqual(d.deployments[0].state, 'ERROR');
    assert.strictEqual(seen.team, 'team_abc');
    const l = await (await fetch(base + '/api/vercel?op=logs&deployment=dpl_1', { headers: h })).json();
    assert.strictEqual(l.log, 'line 1\nline 2');
  });

  await check('vercel: плохой токен и странный id', async () => {
    const bad = await fetch(base + '/api/vercel?op=projects', { headers: { 'x-vercel-token': 'nope' } });
    assert.strictEqual(bad.status, 401);
    const h = { 'x-vercel-token': 'vcgood' };
    assert.strictEqual((await fetch(base + '/api/vercel?op=logs&deployment=a/../b', { headers: h })).status, 400);
  });

  await check('vercel: деплой проекта из браузера', async () => {
    const h = { 'x-vercel-token': 'vcgood', 'x-vercel-team': 'team_abc', 'Content-Type': 'application/json' };
    const r = await fetch(base + '/api/vercel?op=deploy', { method: 'POST', headers: h, body: JSON.stringify({ name: 'Мой Трейлер 2', files: [{ path: 'index.html', data: '<h1>hi</h1>' }, { path: 'app/main.js', data: 'x' }] }) });
    assert.strictEqual(r.status, 400, 'имя без латиницы даёт пустое имя');
    const ok = await fetch(base + '/api/vercel?op=deploy', { method: 'POST', headers: h, body: JSON.stringify({ name: 'My Trailer 2', files: [{ path: 'index.html', data: '<h1>hi</h1>' }, { path: 'app/main.js', data: 'x' }] }) });
    assert.strictEqual(ok.status, 200);
    const j = await ok.json();
    assert.strictEqual(j.productionUrl, 'https://my-trailer-2.vercel.app');
    assert.strictEqual(seen.deploy.team, 'team_abc');
    assert.deepStrictEqual(seen.deploy.body.files.map((f) => f.file), ['index.html', 'app/main.js']);
    assert.strictEqual(seen.deploy.body.target, 'production');
    assert.strictEqual(seen.deploy.body.projectSettings.framework, null);
  });

  await check('vercel/github: опасные файлы и пути не уходят наружу', async () => {
    const h = { 'x-vercel-token': 'vcgood', 'Content-Type': 'application/json' };
    const bad = (files) => fetch(base + '/api/vercel?op=deploy', { method: 'POST', headers: h, body: JSON.stringify({ name: 'x', files }) });
    assert.strictEqual((await bad([{ path: '../x', data: '1' }])).status, 400);
    assert.strictEqual((await bad([{ path: '.env', data: 'K=1' }])).status, 400);
    assert.strictEqual((await bad([{ path: 'a/.git/config', data: '1' }])).status, 400);
    assert.strictEqual((await bad([])).status, 400);
    assert.strictEqual((await fetch(base + '/api/vercel?op=deploy', { headers: { 'x-vercel-token': 'vcgood' } })).status, 405);
  });

  await check('github: коммит проекта в новую ветку через git data API', async () => {
    seen.calls.length = 0;
    const h = { 'x-github-token': 'ghgood', 'Content-Type': 'application/json' };
    const r = await fetch(base + '/api/github?op=commit', { method: 'POST', headers: h, body: JSON.stringify({ repo: 'me/app', branch: 'feat-x', message: 'Из Пульта', files: [{ path: 'index.html', data: '<h1>1</h1>' }] }) });
    assert.strictEqual(r.status, 200, await r.clone().text());
    const j = await r.json();
    assert.strictEqual(j.branch, 'feat-x');
    assert.strictEqual(j.sha, 'commit9');
    assert.match(j.compare, /compare\/main\.\.\.feat-x$/);
    assert.deepStrictEqual(seen.tree.tree[0], { path: 'index.html', mode: '100644', type: 'blob', content: '<h1>1</h1>' });
    assert.strictEqual(seen.tree.base_tree, 'tree1');
    assert.strictEqual(seen.commit.message, 'Из Пульта');
    assert.deepStrictEqual(seen.commit.parents, ['base1']);
    assert.ok(seen.calls.includes('PATCH /gh/repos/me/app/git/refs/heads/feat-x'));
    const badRepo = await fetch(base + '/api/github?op=commit', { method: 'POST', headers: h, body: JSON.stringify({ repo: 'me/app;x', files: [{ path: 'a', data: '1' }] }) });
    assert.strictEqual(badRepo.status, 400);
  });

  await check('статика: index отдаётся (если уже собран), служебные api недоступны', async () => {
    assert.strictEqual((await fetch(base + '/api/_lib')).status, 404);
    assert.strictEqual((await fetch(base + '/../package.json')).status, 404);
  });

  app.close();
  mock.close();
  let bad = 0;
  for (const [s, n] of results) {
    console.log(`${s === 'ok' ? '✓' : '✗'} ${n}`);
    if (s !== 'ok') bad++;
  }
  console.log(bad ? `\n${bad} из ${results.length} упало` : `\nВсе ${results.length} проверок прошли`);
  process.exit(bad ? 1 : 0);
})();
