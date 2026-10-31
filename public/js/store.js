// Хранилище: настройки и чаты лежат в localStorage браузера. Сервер ничего не хранит.

export const MODES = {
  chat: {
    id: 'chat',
    label: 'Chat',
    hint: 'Болтать и думать вслух',
    placeholder: 'О чём поговорим?',
    prompt:
      'Ты дружелюбный и умный собеседник. Отвечай на языке пользователя, по делу и без воды. ' +
      'Если вопрос неясен, задай один уточняющий вопрос. Форматирование используй умеренно.',
    starters: [
      'Объясни простыми словами, как работает блокчейн',
      'Помоги выбрать, чем заняться на выходных',
      'Придумай 5 названий для проекта про личные финансы',
    ],
    prefer: [/llama.*70b/i, /gemma/i, /mistral/i, /qwen/i, /deepseek/i],
  },
  code: {
    id: 'code',
    label: 'Code',
    hint: 'Код, баги, репозитории',
    placeholder: 'Опиши задачу: агент сам создаст и поправит файлы проекта',
    prompt:
      'Ты старший инженер-программист. Отвечай на языке пользователя. Сначала суть решения в 1–2 фразах, ' +
      'потом код в блоках с указанием языка, потом важные оговорки. Если в контексте есть файлы репозитория или логи, ' +
      'опирайся на них и называй файлы по именам. Не выдумывай API: если не уверен, так и скажи.',
    starters: [
      'Сделай игру «Змейка» на canvas с рекордом и звуком, всё в одном проекте',
      'Сделай кинематографичный трейлер несуществующей игры на минуту: мир, камера, свет, титры и звук рисуются и синтезируются кодом',
      'Сделай лендинг для кофейни: тёмная тема, анимации, адаптив',
    ],
    prefer: [/coder/i, /code/i, /deepseek/i, /qwen/i, /devstral/i, /llama.*70b/i],
  },
  work: {
    id: 'work',
    label: 'Work',
    hint: 'Письма, планы, документы',
    placeholder: 'Что нужно написать, разобрать или спланировать?',
    prompt:
      'Ты деловой ассистент: письма, документы, планы, конспекты, таблицы, анализ. Отвечай на языке пользователя, ' +
      'структурно и сжато. Не выдумывай факты и цифры, недостающее оставляй плейсхолдерами в [скобках]. ' +
      'Готовый текст давай одним вариантом, затем коротко: что можно поменять.',
    starters: [
      'Напиши вежливое письмо с просьбой перенести дедлайн',
      'Сделай план проекта на 4 недели из этих заметок',
      'Сократи этот текст вдвое и сохрани смысл',
    ],
    prefer: [/llama.*70b/i, /gemma/i, /qwen/i, /mistral/i, /deepseek/i],
  },
};

export const THEMES = [
  { id: 'ink', label: 'Чернила', swatch: ['#0d1220', '#182036', '#7cc4ff'] },
  { id: 'ice', label: 'Лёд', swatch: ['#f3f6fb', '#ffffff', '#2f6fed'] },
  { id: 'plum', label: 'Слива', swatch: ['#170f1c', '#291c32', '#e58bd0'] },
];

export const FONTS = [
  { id: 'onest', label: 'Onest', stack: '"Onest", system-ui, sans-serif', google: 'Onest:wght@400;500;600;700' },
  { id: 'manrope', label: 'Manrope', stack: '"Manrope", system-ui, sans-serif', google: 'Manrope:wght@400;500;600;700' },
  { id: 'golos', label: 'Golos Text', stack: '"Golos Text", system-ui, sans-serif', google: 'Golos+Text:wght@400;500;600;700' },
  { id: 'plex', label: 'IBM Plex Sans', stack: '"IBM Plex Sans", system-ui, sans-serif', google: 'IBM+Plex+Sans:wght@400;500;600' },
  { id: 'serif', label: 'Source Serif', stack: '"Source Serif 4", Georgia, serif', google: 'Source+Serif+4:wght@400;600;700' },
  { id: 'mono', label: 'JetBrains Mono', stack: '"JetBrains Mono", ui-monospace, monospace', google: 'JetBrains+Mono:wght@400;500;700' },
  { id: 'system', label: 'Системный', stack: 'system-ui, -apple-system, "Segoe UI", sans-serif', google: '' },
];

const DEFAULT_SETTINGS = {
  theme: 'ink',
  font: 'onest',
  fontSize: 15,
  accentMode: 'mode', // 'mode' — цвет зависит от режима, 'custom' — один свой цвет
  accentColor: '#7cc4ff',
  enterToSend: true,
  autoSwitch: true,
  temperature: 0.7,
  globalPrompt: '',
  prompts: { chat: '', code: '', work: '' },
  models: { chat: '', code: '', work: '' },
  keys: { openrouter: '', access: '' },
  connectors: { github: { token: '' }, vercel: { token: '', team: '' } },
  // Агент: 'smart' — спрашивать перед записью только в настоящую папку, 'ask' — всегда, 'auto' — никогда.
  agent: { on: true, confirm: 'smart', steps: 14, plan: false, rules: true },
};

const SK = 'pult.settings.v1';
const CK = 'pult.chats.v1';
const MK = 'pult.mode.v1';

function merge(base, extra) {
  if (!extra || typeof extra !== 'object') return structuredClone(base);
  const out = Array.isArray(base) ? [] : {};
  for (const k of Object.keys(base)) {
    const b = base[k];
    const e = extra[k];
    if (b && typeof b === 'object' && !Array.isArray(b)) out[k] = merge(b, e);
    else out[k] = e !== undefined && typeof e === typeof b ? e : b;
  }
  return out;
}

function read(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function write(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
    return true;
  } catch {
    return false;
  }
}

export const state = {
  settings: merge(DEFAULT_SETTINGS, read(SK, {})),
  chats: read(CK, []),
  mode: read(MK, 'chat'),
  activeId: null,
};
if (!MODES[state.mode]) state.mode = 'chat';

export function saveSettings() {
  write(SK, state.settings);
}

let chatTimer = null;
export function saveChats(now) {
  clearTimeout(chatTimer);
  const run = () => {
    if (!write(CK, state.chats)) {
      // Место кончилось: выкидываем самые старые чаты и пробуем ещё раз.
      state.chats.sort((a, b) => b.updated - a.updated);
      while (state.chats.length > 5 && !write(CK, state.chats)) state.chats.pop();
    }
  };
  if (now) run();
  else chatTimer = setTimeout(run, 400);
}

export function setMode(mode) {
  state.mode = mode;
  state.activeId = null;
  write(MK, mode);
}

export function uid() {
  return Math.random().toString(36).slice(2, 10) + Date.now().toString(36).slice(-4);
}

export function chatsFor(mode) {
  return state.chats.filter((c) => c.mode === mode).sort((a, b) => b.updated - a.updated);
}

export function getChat(id) {
  return state.chats.find((c) => c.id === id) || null;
}

export function createChat(mode) {
  const chat = { id: uid(), mode, title: 'Новый чат', created: Date.now(), updated: Date.now(), messages: [] };
  state.chats.push(chat);
  return chat;
}

export function deleteChat(id) {
  state.chats = state.chats.filter((c) => c.id !== id);
  saveChats(true);
}

export function systemPrompt(mode) {
  const s = state.settings;
  const own = s.prompts[mode].trim();
  const parts = [own || MODES[mode].prompt];
  if (s.globalPrompt.trim()) parts.push('Дополнительные инструкции пользователя:\n' + s.globalPrompt.trim());
  return parts.join('\n\n');
}

// Порядок моделей для режима: сначала выбранная вручную, дальше подходящие по имени, потом остальные.
export function rankModels(mode, models) {
  const chosen = state.settings.models[mode];
  const prefer = MODES[mode].prefer;
  const score = (m) => {
    const i = prefer.findIndex((re) => re.test(m.id) || re.test(m.name));
    return i === -1 ? prefer.length : i;
  };
  const rest = models.filter((m) => m.id !== chosen && !/inkling/i.test(m.id)).sort((a, b) => score(a) - score(b) || b.context - a.context);
  const pick = models.find((m) => m.id === chosen);
  return pick ? [pick, ...rest] : rest;
}

export function exportAll() {
  return JSON.stringify({ app: 'pult', version: 1, settings: { ...state.settings, keys: { openrouter: '', access: '' }, connectors: DEFAULT_SETTINGS.connectors }, chats: state.chats }, null, 2);
}

export function importAll(text) {
  const j = JSON.parse(text);
  if (j.app !== 'pult') throw new Error('Это не файл экспорта Пульта');
  if (Array.isArray(j.chats)) {
    const have = new Set(state.chats.map((c) => c.id));
    for (const c of j.chats) if (c && c.id && !have.has(c.id) && MODES[c.mode] && Array.isArray(c.messages)) state.chats.push(c);
  }
  if (j.settings) {
    const keep = { keys: state.settings.keys, connectors: state.settings.connectors };
    state.settings = { ...merge(DEFAULT_SETTINGS, j.settings), ...keep };
  }
  saveSettings();
  saveChats(true);
}

export function wipeAll() {
  for (const k of [SK, CK, MK]) localStorage.removeItem(k);
}
