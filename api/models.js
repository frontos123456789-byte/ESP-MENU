'use strict';

const { send, handler } = require('./_lib');

const BASE = () => (process.env.OPENROUTER_BASE_URL || 'https://openrouter.ai/api/v1').replace(/\/+$/, '');

// Запасной список, если OpenRouter не ответил. Живой список всегда приоритетнее.
const FALLBACK = [
  { id: 'openrouter/free', name: 'Авто (любая бесплатная)', context: 128000 },
  { id: 'meta-llama/llama-3.3-70b-instruct:free', name: 'Llama 3.3 70B', context: 131072 },
  { id: 'qwen/qwen3-coder:free', name: 'Qwen3 Coder', context: 262144 },
  { id: 'deepseek/deepseek-r1:free', name: 'DeepSeek R1', context: 163840 },
  { id: 'google/gemma-3-27b-it:free', name: 'Gemma 3 27B', context: 131072 },
];

// Только настоящие бесплатные чат-модели: id с :free (или роутер), нулевая цена,
// без служебных (модерация, музыка, эмбеддинги), которые нулевую цену имеют, но чатом не являются.
const NOT_CHAT = /content-safety|guard|moderation|lyria|embed|rerank/i;

function isFree(m) {
  const p = m.pricing || {};
  const zero = (v) => v === 0 || v === '0' || Number(v) === 0;
  const freeId = /:free$/.test(m.id) || m.id === 'openrouter/free';
  return freeId && !NOT_CHAT.test(m.id) && zero(p.prompt) && zero(p.completion) && p.prompt !== undefined;
}

function textOutput(m) {
  const out = m.architecture?.output_modalities;
  if (Array.isArray(out)) return out.includes('text');
  const mod = m.architecture?.modality;
  return typeof mod === 'string' ? mod.endsWith('->text') || mod.endsWith('->text+image') : true;
}

module.exports = handler(async (req, res) => {
  let models = null;
  try {
    const r = await fetch(`${BASE()}/models`, { signal: AbortSignal.timeout(8000) });
    if (r.ok) {
      const j = await r.json();
      const list = Array.isArray(j.data) ? j.data : [];
      models = list
        .filter((m) => m && typeof m.id === 'string' && isFree(m) && textOutput(m))
        .map((m) => ({
          id: m.id,
          name: String(m.name || m.id).replace(/\s*\(free\)\s*$/i, ''),
          context: Number(m.context_length) || 0,
          vision: Array.isArray(m.architecture?.input_modalities) && m.architecture.input_modalities.includes('image'),
        }))
        .sort((a, b) => b.context - a.context);
    }
  } catch { /* уйдём в запасной список */ }

  const ok = Array.isArray(models) && models.length > 0;
  send(
    res,
    200,
    {
      models: ok ? models : FALLBACK,
      fallback: !ok,
      serverKey: Boolean(process.env.OPENROUTER_API_KEY),
      gated: Boolean(process.env.ACCESS_CODE),
    },
    { 'Cache-Control': ok ? 'public, s-maxage=600, stale-while-revalidate=3600' : 'no-store' }
  );
});
