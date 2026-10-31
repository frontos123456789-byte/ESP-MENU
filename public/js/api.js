import { state } from './store.js';

export class ApiError extends Error {
  constructor(message, { status = 0, code = '' } = {}) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function authHeaders(extra = {}) {
  const k = state.settings.keys;
  const h = { ...extra };
  if (k.openrouter.trim()) h['x-openrouter-key'] = k.openrouter.trim();
  if (k.access.trim()) h['x-access-code'] = k.access.trim();
  return h;
}

export async function getJson(url, headers = {}, signal) {
  let r;
  try {
    r = await fetch(url, { headers: authHeaders(headers), signal });
  } catch (e) {
    if (e.name === 'AbortError') throw e;
    throw new ApiError('Нет связи с сервером', { code: 'network' });
  }
  let j = {};
  try { j = await r.json(); } catch { /* пустой ответ */ }
  if (!r.ok) throw new ApiError(j.error || `Ошибка ${r.status}`, { status: r.status, code: j.code || '' });
  return j;
}

export async function postJson(url, body, headers = {}) {
  let r;
  try {
    r = await fetch(url, { method: 'POST', headers: authHeaders({ 'Content-Type': 'application/json', ...headers }), body: JSON.stringify(body) });
  } catch {
    throw new ApiError('Нет связи с сервером', { code: 'network' });
  }
  let j = {};
  try { j = await r.json(); } catch { /* пустой ответ */ }
  if (!r.ok) throw new ApiError(j.error || `Ошибка ${r.status}`, { status: r.status, code: j.code || '' });
  return j;
}

export function loadModels() {
  return getJson('/api/models');
}

// Читает SSE от /api/chat и отдаёт куски текста в onDelta.
export async function streamChat({ model, messages, signal, onDelta, stop }) {
  let r;
  try {
    r = await fetch('/api/chat', {
      method: 'POST',
      signal,
      headers: authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ model, messages, temperature: state.settings.temperature, stop }),
    });
  } catch (e) {
    if (e.name === 'AbortError') throw e;
    throw new ApiError('Нет связи с сервером', { code: 'network' });
  }
  if (!r.ok) {
    let j = {};
    try { j = await r.json(); } catch { /* не JSON */ }
    throw new ApiError(j.error || `Ошибка ${r.status}`, { status: r.status, code: j.code || '' });
  }

  const reader = r.body.getReader();
  const dec = new TextDecoder();
  let buf = '';
  let got = false;
  let finish = '';
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    let nl;
    while ((nl = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, nl).trim();
      buf = buf.slice(nl + 1);
      if (!line.startsWith('data:')) continue;
      const data = line.slice(5).trim();
      if (data === '[DONE]') {
        if (!got) throw new ApiError('Модель вернула пустой ответ', { code: 'empty' });
        return { finish };
      }
      let j;
      try { j = JSON.parse(data); } catch { continue; }
      if (j.error) throw new ApiError(j.error.message || 'Ошибка модели', { code: 'stream' });
      if (j.choices?.[0]?.finish_reason) finish = j.choices[0].finish_reason;
      const piece = j.choices?.[0]?.delta?.content;
      if (piece) {
        got = true;
        onDelta(piece);
      }
    }
  }
  if (!got) throw new ApiError('Модель вернула пустой ответ', { code: 'empty' });
  return { finish };
}

// Человеческое объяснение ошибки + что с этим делать.
export function explain(err) {
  const m = err.message || 'Что-то пошло не так';
  switch (err.code) {
    case 'nokey':
      return { text: 'Нужен ключ OpenRouter. Он бесплатный: создай на openrouter.ai/keys и вставь в настройках.', fix: 'access' };
    case 'badkey':
      return { text: 'OpenRouter не принял ключ. Проверь, что он вставлен целиком.', fix: 'access' };
    case 'access':
      return { text: 'Сайт закрыт кодом доступа. Введи его в настройках.', fix: 'access' };
    case 'credits':
      return { text: 'На ключе не хватает кредитов для этой модели. Выбери бесплатную.', fix: 'model' };
    case 'notfree':
      return { text: 'С общим ключом работают только бесплатные модели. Выбери одну с пометкой :free.', fix: 'model' };
    case 'ratelimit':
      return { text: 'Бесплатная модель упёрлась в лимит. Выбери другую или подожди минуту.', fix: 'model' };
    case 'network':
      return { text: 'Нет связи с сервером. Проверь интернет и попробуй ещё раз.', fix: '' };
    case 'empty':
      return { text: 'Модель ничего не ответила. Бывает у бесплатных. Попробуй другую.', fix: 'model' };
  }
  if (/data policy|privacy/i.test(m)) {
    return { text: 'OpenRouter не пускает к бесплатным моделям из-за настроек приватности. В аккаунте OpenRouter, раздел Privacy, разреши бесплатные модели.', fix: '' };
  }
  return { text: m, fix: err.status >= 500 || err.status === 429 ? 'model' : '' };
}

export function isRetryable(err) {
  if (['nokey', 'badkey', 'access', 'notfree', 'credits', 'network'].includes(err.code)) return false;
  if (/agentic|harness|not available|unavailable|no endpoints/i.test(err.message || '')) return true;
  return ['ratelimit', 'upstream', 'empty', 'stream'].includes(err.code) || [400, 403, 404, 408, 422, 429, 502, 503, 504].includes(err.status);
}
