'use strict';

const { send, fail, readJson, requireAccess, handler } = require('./_lib');

const BASE = () => (process.env.OPENROUTER_BASE_URL || 'https://openrouter.ai/api/v1').replace(/\/+$/, '');

function isFreeModel(id) {
  return /:free$/.test(id) || id === 'openrouter/free';
}

module.exports = handler(async (req, res) => {
  if (req.method !== 'POST') throw fail(405, 'Только POST');
  requireAccess(req);

  const body = await readJson(req);
  const model = typeof body.model === 'string' ? body.model.trim() : '';
  const messages = Array.isArray(body.messages) ? body.messages : null;
  if (!model || model.length > 120) throw fail(400, 'Не выбрана модель');
  if (!messages || !messages.length) throw fail(400, 'Пустой диалог');

  const userKey = String(req.headers['x-openrouter-key'] || '').trim();
  const key = userKey || process.env.OPENROUTER_API_KEY || '';
  if (!key) {
    throw fail(400, 'Нет ключа OpenRouter. Вставь свой в Настройки → Доступ или задай OPENROUTER_API_KEY на сервере.', 'nokey');
  }
  // Серверный ключ — деньги владельца сайта: только бесплатные модели.
  if (!userKey && !isFreeModel(model)) {
    throw fail(403, 'С общим ключом доступны только бесплатные модели (:free).', 'notfree');
  }

  const clean = messages
    .filter((m) => m && typeof m.content === 'string' && ['system', 'user', 'assistant'].includes(m.role))
    .map((m) => ({ role: m.role, content: m.content }));
  if (!clean.length) throw fail(400, 'Пустой диалог');

  const payload = { model, messages: clean, stream: true };
  const t = Number(body.temperature);
  if (Number.isFinite(t) && t >= 0 && t <= 2) payload.temperature = t;
  if (Array.isArray(body.stop)) {
    const stop = body.stop.filter((x) => typeof x === 'string' && x && x.length <= 40).slice(0, 4);
    if (stop.length) payload.stop = stop;
  }
  const mt = Number(body.max_tokens);
  if (Number.isFinite(mt) && mt > 0 && mt <= 32000) payload.max_tokens = Math.floor(mt);

  const controller = new AbortController();
  res.on('close', () => {
    if (!res.writableEnded) controller.abort();
  });

  let upstream;
  try {
    upstream = await fetch(`${BASE()}/chat/completions`, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': process.env.SITE_URL || 'https://pult.vercel.app',
        'X-Title': 'Pult',
      },
      body: JSON.stringify(payload),
    });
  } catch (err) {
    if (controller.signal.aborted) return;
    throw fail(502, 'Не достучался до OpenRouter: ' + (err.cause?.code || err.message), 'upstream');
  }

  if (!upstream.ok) {
    const raw = await upstream.text().catch(() => '');
    let msg = raw.slice(0, 300);
    try {
      const j = JSON.parse(raw);
      msg = j.error?.message || j.message || msg;
      const detail = j.error?.metadata?.raw;
      if (detail && typeof detail === 'string') msg += ' — ' + detail.slice(0, 160);
    } catch { /* оставляем сырой текст */ }
    const status = upstream.status;
    const code = status === 401 ? 'badkey' : status === 429 ? 'ratelimit' : status === 402 ? 'credits' : 'upstream';
    const out = [401, 402, 404, 408, 429].includes(status) ? status : 502;
    return send(res, out, { error: msg || `OpenRouter ответил ${status}`, code, upstreamStatus: status });
  }

  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('X-Accel-Buffering', 'no');
  res.setHeader('Connection', 'keep-alive');
  if (typeof res.flushHeaders === 'function') res.flushHeaders();

  try {
    const reader = upstream.body.getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!res.write(Buffer.from(value))) {
        await new Promise((r) => res.once('drain', r));
      }
    }
  } catch (err) {
    if (!controller.signal.aborted) {
      res.write(`data: ${JSON.stringify({ error: { message: 'Поток оборвался: ' + err.message } })}\n\n`);
    }
  }
  res.end();
});
