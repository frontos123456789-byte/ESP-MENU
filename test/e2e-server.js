'use strict';

// Стенд для браузерной проверки: приложение + мок OpenRouter/GitHub/Vercel на одном процессе.
const http = require('http');

const last = { chat: null, count: 0 };

const mock = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  let raw = '';
  req.on('data', (c) => (raw += c));
  req.on('end', () => {
    const json = (code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
    const p = url.pathname;
    if (p === '/__last') return json(200, last);
    if (p === '/or/models') {
      return json(200, { data: [
        { id: 'q/qwen3-coder:free', name: 'Qwen3 Coder (free)', context_length: 262144, pricing: { prompt: '0', completion: '0' }, architecture: { output_modalities: ['text'], input_modalities: ['text'] } },
        { id: 'm/llama-3.3-70b-instruct:free', name: 'Llama 3.3 70B Instruct (free)', context_length: 131072, pricing: { prompt: '0', completion: '0' }, architecture: { output_modalities: ['text'], input_modalities: ['text'] } },
        { id: 'g/gemma-3-27b-it:free', name: 'Gemma 3 27B (free)', context_length: 96000, pricing: { prompt: '0', completion: '0' }, architecture: { output_modalities: ['text'], input_modalities: ['text', 'image'] } },
      ] });
    }
    if (p === '/or/chat/completions') {
      const body = JSON.parse(raw);
      last.chat = body;
      last.count++;
      if (body.model.includes('coder')) return json(429, { error: { message: 'Provider returned error: rate limited' } });
      const reply = 'Вот решение, **коротко**:\n\n```ts\nexport const sum = (a: number, b: number) => a + b;\n```\n\n- первое\n- второе\n\n| режим | цвет |\n|---|---|\n| Chat | розовый |\n';
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      let i = 0;
      const step = () => {
        if (i >= reply.length) { res.write('data: [DONE]\n\n'); return res.end(); }
        res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: reply.slice(i, i + 6) } }] })}\n\n`);
        i += 6;
        setTimeout(step, 12);
      };
      return step();
    }
    if (p === '/gh/user/repos') return json(200, [{ full_name: 'me/app', private: true, description: 'Мой сайт', language: 'TypeScript', pushed_at: '2026-10-20', default_branch: 'main' }]);
    if (p === '/gh/repos/me/app') return json(200, { default_branch: 'main' });
    if (p === '/gh/repos/me/app/git/trees/main') return json(200, { tree: [{ type: 'blob', path: 'src/index.ts', size: 900 }, { type: 'blob', path: 'README.md', size: 300 }] });
    if (p === '/gh/repos/me/app/contents/src/index.ts') { res.writeHead(200, { 'Content-Type': 'text/plain' }); return res.end('export const secretMarker = 42;'); }
    if (p === '/vc/v9/projects') return json(200, { projects: [{ id: 'prj_1', name: 'my-site', framework: 'nextjs', updatedAt: Date.now() - 3600e3, link: { org: 'me', repo: 'app' } }] });
    if (p === '/vc/v6/deployments') return json(200, { deployments: [{ uid: 'dpl_abc123', url: 'my-site.vercel.app', readyState: 'ERROR', target: 'production', created: Date.now() - 600e3, meta: { githubCommitMessage: 'fix build', githubCommitRef: 'main' } }, { uid: 'dpl_def456', url: 'my-site-x.vercel.app', readyState: 'READY', target: 'preview', created: Date.now() - 9000e3, meta: {} }] });
    if (p.startsWith('/vc/v3/deployments/')) return json(200, [{ text: 'Error: Cannot find module "left-pad"' }, { text: 'Running build' }]);
    json(404, { error: 'nope' });
  });
});

mock.listen(0, '127.0.0.1', () => {
  const port = mock.address().port;
  process.env.OPENROUTER_BASE_URL = `http://127.0.0.1:${port}/or`;
  process.env.GITHUB_API_URL = `http://127.0.0.1:${port}/gh`;
  process.env.VERCEL_API_URL = `http://127.0.0.1:${port}/vc`;
  if (process.env.E2E_KEY !== '0') process.env.OPENROUTER_API_KEY = 'server-key';
  const app = require('../server').createServer();
  app.listen(Number(process.env.PORT) || 4173, '127.0.0.1', () => console.log('ready', mock.address().port));
  // отдаём мок-журнал и через порт приложения
  const orig = app.listeners('request')[0];
  app.removeAllListeners('request');
  app.on('request', (req, res) => {
    if (req.url === '/__last') return http.get(`http://127.0.0.1:${port}/__last`, (r) => r.pipe(res));
    orig(req, res);
  });
});
