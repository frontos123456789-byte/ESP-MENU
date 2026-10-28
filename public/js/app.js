import {
  state, saveSettings, saveChats, MODES, setMode, chatsFor, getChat, createChat, deleteChat, systemPrompt, rankModels, uid,
} from './store.js';
import { renderMarkdown, titleFrom } from './md.js';
import { el, icon, ICONS, toast, copyText } from './ui.js';
import { loadModels, streamChat, explain, isRetryable } from './api.js';
import { applyAppearance } from './appearance.js';
import { openSettings } from './settings.js';
import { openConnectors } from './connectors.js';

const $ = (id) => document.getElementById(id);
const HISTORY_BUDGET = 60000; // символов контекста; старые реплики отбрасываются
const MAX_ATTACH = 8;

let models = [];
let serverInfo = { serverKey: false, gated: false, fallback: false };
let running = null; // { controller, chatId, msgId }
const pending = []; // вложения, ещё не отправленные

const activeChat = () => (state.activeId ? getChat(state.activeId) : null);
const fineCursor = () => matchMedia('(pointer: fine)').matches;

/* ================= рендер ================= */

function renderModes() {
  $('modes').replaceChildren(
    ...Object.values(MODES).map((m) =>
      el(
        'button',
        { class: 'mode', role: 'tab', type: 'button', dataset: { m: m.id }, 'aria-selected': String(state.mode === m.id), onclick: () => switchMode(m.id) },
        icon(ICONS[m.id]),
        el('span', {}, el('b', {}, m.label), el('small', {}, m.hint))
      )
    )
  );
}

function renderChatList() {
  const list = chatsFor(state.mode);
  $('chatList').replaceChildren(
    ...(list.length
      ? list.map((c) =>
          el(
            'div',
            { class: 'chat-item', 'aria-current': String(c.id === state.activeId) },
            el('button', { class: 'chat-open', type: 'button', title: c.title, onclick: () => openChat(c.id) }, c.title),
            el('button', { class: 'chat-x', type: 'button', 'aria-label': `Удалить чат «${c.title}»`, onclick: () => removeChat(c.id) }, icon(ICONS.close))
          )
        )
      : [el('p', { class: 'chat-empty' }, `Чаты режима ${MODES[state.mode].label} появятся здесь`)])
  );
}

function renderTitle() {
  $('chatTitle').textContent = activeChat()?.title || 'Новый чат';
}

function currentModel() {
  return rankModels(state.mode, models)[0] || null;
}

function renderModelBtn() {
  const m = currentModel();
  const chosen = state.settings.models[state.mode];
  $('modelName').textContent = m ? (chosen && chosen === m.id ? m.name : `Авто · ${m.name}`) : 'Модель не выбрана';
}

function updateComposer() {
  $('input').placeholder = MODES[state.mode].placeholder;
  const send = state.settings.enterToSend && fineCursor();
  $('sendHint').textContent = send ? 'Enter — отправить, Shift+Enter — перенос' : fineCursor() ? 'Ctrl+Enter — отправить' : '';
}

function setSendState() {
  const b = $('sendBtn');
  b.textContent = running ? 'Стоп' : 'Отправить';
  b.dataset.state = running ? 'stop' : 'idle';
}

function renderChips() {
  $('chips').replaceChildren(
    ...pending.map((a, i) =>
      el(
        'span',
        { class: 'chip', title: a.name },
        el('span', {}, shortName(a.name)),
        a.truncated ? el('em', {}, 'обрезан') : null,
        el('button', { class: 'chip-x', type: 'button', 'aria-label': 'Убрать вложение', onclick: () => { pending.splice(i, 1); renderChips(); } }, icon(ICONS.close))
      )
    )
  );
}

function shortName(name) {
  const last = name.split('/').pop() || name;
  return last.length > 30 ? last.slice(0, 28) + '…' : last;
}

function setupNote() {
  if (serverInfo.gated && !state.settings.keys.access.trim()) {
    return el(
      'div', { class: 'setup-note' },
      el('p', {}, 'Этот сайт закрыт кодом доступа. Введи его один раз, и он запомнится в браузере.'),
      el('p', {}, el('button', { class: 'btn primary', type: 'button', onclick: () => openSettings(settingsCtx, 'access') }, 'Ввести код'))
    );
  }
  if (!serverInfo.serverKey && !state.settings.keys.openrouter.trim()) {
    return el(
      'div', { class: 'setup-note' },
      el('p', {}, 'Чтобы отвечать бесплатно, Пульту нужен ключ OpenRouter. Он бесплатный и создаётся за минуту.'),
      el('p', {}, el('button', { class: 'btn primary', type: 'button', onclick: () => openSettings(settingsCtx, 'access') }, 'Вставить ключ'))
    );
  }
  return null;
}

function emptyState() {
  const m = MODES[state.mode];
  const box = el('div', { class: 'empty' }, el('h2', { class: 'mode-word' }, m.label), el('p', { class: 'empty-lead' }, `${m.hint}. Бесплатные модели, твои промты, твой дизайн.`));
  const note = setupNote();
  if (note) box.append(note);
  box.append(
    el(
      'div', { class: 'starters' },
      ...m.starters.map((s) => el('button', { class: 'starter', type: 'button', onclick: () => { closeRail(); send(s); } }, s))
    )
  );
  if (state.mode === 'code') {
    box.append(el('p', { class: 'help', style: 'margin-top:18px' }, el('button', { class: 'link-btn', type: 'button', onclick: () => openConnectors(connectorCtx) }, 'Добавить файлы из GitHub или лог сборки из Vercel')));
  }
  return box;
}

function errNote(err) {
  const x = explain(err);
  const box = el('div', { class: 'err-note' }, el('p', {}, x.text));
  if (x.fix === 'access') box.append(el('p', {}, el('button', { class: 'link-btn', type: 'button', onclick: () => openSettings(settingsCtx, 'access') }, 'Открыть настройки доступа')));
  if (x.fix === 'model') box.append(el('p', {}, el('button', { class: 'link-btn', type: 'button', onclick: openModelDialog }, 'Выбрать другую модель')));
  return box;
}

function msgEl(m, chat) {
  if (m.role === 'user') {
    const node = el('article', { class: 'msg user', dataset: { id: m.id } }, el('div', { class: 'bubble' }, m.text || '(без текста)'));
    if (m.atts?.length) node.append(el('div', { class: 'msg-atts' }, ...m.atts.map((a) => el('span', { class: 'chip-ro', title: a.name }, shortName(a.name)))));
    return node;
  }
  const live = running && running.msgId === m.id;
  const node = el('article', { class: 'msg assistant' + (live ? ' streaming' : ''), dataset: { id: m.id } });
  node.append(el('div', { class: 'meta' }, el('span', { class: 'who' }, m.model || 'Модель'), m.note ? el('span', { class: 'note' }, m.note) : null));
  const prose = el('div', { class: 'prose' });
  prose.innerHTML = renderMarkdown(m.text || '');
  node.append(prose);
  if (m.error) node.append(errNote(m.error));
  if (!live) {
    const last = chat.messages[chat.messages.length - 1] === m;
    node.append(
      el(
        'div', { class: 'actions' },
        m.text ? el('button', { class: 'act', type: 'button', dataset: { act: 'copy' } }, 'Копировать') : null,
        last ? el('button', { class: 'act', type: 'button', dataset: { act: 'retry' } }, 'Ещё раз') : null
      )
    );
  }
  return node;
}

function renderThread() {
  const chat = activeChat();
  const t = $('thread');
  t.replaceChildren();
  if (!chat || !chat.messages.length) {
    t.append(emptyState());
    $('threadWrap').scrollTop = 0;
    return;
  }
  for (const m of chat.messages) t.append(msgEl(m, chat));
  const w = $('threadWrap');
  w.scrollTop = w.scrollHeight;
}

function renderAll() {
  applyAppearance();
  renderModes();
  renderChatList();
  renderTitle();
  renderModelBtn();
  renderThread();
  renderChips();
  updateComposer();
  setSendState();
}

/* ================= стриминг ================= */

let paintQueued = false;
function paintStream(msg) {
  if (paintQueued) return;
  paintQueued = true;
  requestAnimationFrame(() => {
    paintQueued = false;
    const prose = $('thread').querySelector(`[data-id="${msg.id}"] .prose`);
    if (!prose) return;
    const w = $('threadWrap');
    const stick = w.scrollHeight - w.scrollTop - w.clientHeight < 160;
    prose.innerHTML = renderMarkdown(msg.text);
    if (stick) w.scrollTop = w.scrollHeight;
  });
}

function replaceMsg(msg, chat) {
  if (state.activeId !== chat.id) return;
  const node = $('thread').querySelector(`[data-id="${msg.id}"]`);
  if (!node) return;
  if (chat.messages.includes(msg)) node.replaceWith(msgEl(msg, chat));
  else node.remove();
}

function toContent(m) {
  if (m.role !== 'user' || !m.atts?.length) return m.text;
  const files = m.atts
    .map((a) => `<file name="${a.name.replace(/"/g, "'")}"${a.truncated ? ' truncated="true"' : ''}>\n${a.body}\n</file>`)
    .join('\n\n');
  return `${files}\n\n${m.text || 'Посмотри вложения.'}`;
}

function buildMessages(chat, endIdx) {
  const sys = systemPrompt(chat.mode);
  const hist = chat.messages
    .slice(0, endIdx)
    .filter((m) => m.role === 'user' || m.text.trim())
    .map((m) => ({ role: m.role, content: toContent(m) }));
  let total = sys.length;
  const kept = [];
  for (let i = hist.length - 1; i >= 0; i--) {
    const len = hist[i].content.length;
    if (kept.length && total + len > HISTORY_BUDGET) break;
    kept.unshift(hist[i]);
    total += len;
  }
  while (kept.length > 1 && kept[0].role === 'assistant') kept.shift();
  return [{ role: 'system', content: sys }, ...kept];
}

async function complete(chat) {
  const msg = { id: uid(), role: 'assistant', text: '', model: '', ts: Date.now() };
  chat.messages.push(msg);
  chat.updated = Date.now();
  const controller = new AbortController();
  running = { controller, chatId: chat.id, msgId: msg.id };
  saveChats(true);
  renderChatList();
  renderTitle();
  renderThread();
  setSendState();

  const history = buildMessages(chat, chat.messages.length - 1);
  const ranked = rankModels(chat.mode, models);
  const tries = ranked.length
    ? ranked.slice(0, state.settings.autoSwitch ? 4 : 1)
    : [{ id: state.settings.models[chat.mode] || 'openrouter/free', name: 'Авто' }];

  let lastErr = null;
  for (let i = 0; i < tries.length; i++) {
    const m = tries[i];
    msg.model = m.name;
    msg.text = '';
    msg.error = null;
    msg.note = i ? 'другая модель после сбоя' : '';
    replaceMsg(msg, chat);
    try {
      await streamChat({ model: m.id, messages: history, signal: controller.signal, onDelta: (d) => { msg.text += d; paintStream(msg); } });
      lastErr = null;
      break;
    } catch (e) {
      if (e.name === 'AbortError') {
        lastErr = null;
        if (msg.text) msg.note = msg.note ? `${msg.note} · остановлено` : 'остановлено';
        break;
      }
      lastErr = e;
      if (msg.text || !isRetryable(e) || i === tries.length - 1) break;
    }
  }
  if (lastErr) msg.error = { message: lastErr.message, code: lastErr.code, status: lastErr.status };
  if (!msg.text && !msg.error) chat.messages = chat.messages.filter((x) => x !== msg);

  running = null;
  chat.updated = Date.now();
  saveChats(true);
  replaceMsg(msg, chat);
  setSendState();
  renderChatList();
}

function stopRun() {
  if (running) running.controller.abort();
}

async function send(raw) {
  const text = String(raw || '').trim();
  if (running || (!text && !pending.length)) return;
  let chat = activeChat();
  if (!chat) {
    chat = createChat(state.mode);
    state.activeId = chat.id;
  }
  const atts = pending.splice(0).map((a) => ({ name: a.name, body: a.body, truncated: a.truncated }));
  chat.messages.push({ id: uid(), role: 'user', text, atts, ts: Date.now() });
  if (chat.messages.length === 1) chat.title = titleFrom(text || atts[0]?.name || '');
  $('input').value = '';
  autosize();
  renderChips();
  await complete(chat);
}

function retry() {
  if (running) return;
  const chat = activeChat();
  if (!chat) return;
  if (chat.messages[chat.messages.length - 1]?.role === 'assistant') chat.messages.pop();
  if (!chat.messages.length) return;
  complete(chat);
}

/* ================= навигация ================= */

function closeRail() {
  $('shell').dataset.rail = '';
}

function switchMode(id) {
  if (id === state.mode) {
    closeRail();
    return newChat();
  }
  stopRun();
  setMode(id);
  applyAppearance();
  renderModes();
  renderChatList();
  renderTitle();
  renderModelBtn();
  renderThread();
  updateComposer();
}

function newChat() {
  stopRun();
  state.activeId = null;
  renderChatList();
  renderTitle();
  renderThread();
  closeRail();
  if (fineCursor()) $('input').focus();
}

function openChat(id) {
  stopRun();
  state.activeId = id;
  renderChatList();
  renderTitle();
  renderThread();
  closeRail();
}

function removeChat(id) {
  const c = getChat(id);
  if (!c || !confirm(`Удалить чат «${c.title}»?`)) return;
  if (state.activeId === id) {
    stopRun();
    state.activeId = null;
  }
  deleteChat(id);
  renderChatList();
  renderTitle();
  renderThread();
}

/* ================= модели ================= */

function ctxLabel(n) {
  return n >= 1000 ? `${Math.round(n / 1000)}K` : '';
}

function drawModels(q = '') {
  const chosen = state.settings.models[state.mode];
  const list = $('modelList');
  const query = q.toLowerCase();
  const rows = models.filter((m) => m.name.toLowerCase().includes(query) || m.id.toLowerCase().includes(query));
  const pick = (id) => {
    state.settings.models[state.mode] = id;
    saveSettings();
    renderModelBtn();
    $('modelDialog').close();
  };
  const items = [];
  if (!query || 'авто'.includes(query)) {
    items.push(
      el('button', { class: 'pick', type: 'button', role: 'option', 'aria-selected': String(!chosen), onclick: () => pick('') },
        el('span', { class: 'pick-main' }, el('b', {}, 'Авто'), el('span', { class: 'tag' }, 'рекомендую')),
        el('small', {}, `Подберу подходящую для ${MODES[state.mode].label} и переключусь при сбое`))
    );
  }
  for (const m of rows) {
    items.push(
      el('button', { class: 'pick', type: 'button', role: 'option', 'aria-selected': String(chosen === m.id), onclick: () => pick(m.id) },
        el('span', { class: 'pick-main' }, el('b', {}, m.name), el('span', { class: 'tag' }, [ctxLabel(m.context), m.vision ? 'фото' : ''].filter(Boolean).join(' · ') || 'текст')),
        el('small', {}, m.id))
    );
  }
  if (!items.length) items.push(el('p', { class: 'help' }, 'Ничего не нашлось'));
  list.replaceChildren(...items);
}

function openModelDialog() {
  const dlg = $('modelDialog');
  $('modelSearch').value = '';
  $('modelNote').textContent = serverInfo.fallback
    ? 'Свежий список не загрузился, показан запасной. Часть моделей может не отвечать.'
    : `Бесплатных моделей: ${models.length}. Список подтягивается у OpenRouter сам.`;
  drawModels();
  if (!dlg.open) dlg.showModal();
}

/* ================= вложения ================= */

function attach(att) {
  if (pending.length >= MAX_ATTACH) return toast(`Не больше ${MAX_ATTACH} вложений в одном сообщении`);
  const total = pending.reduce((n, a) => n + a.body.length, 0) + att.body.length;
  if (total > 150000) return toast('Во вложениях слишком много текста, убери что-нибудь');
  pending.push({ name: att.name, body: att.body, truncated: Boolean(att.truncated) });
  renderChips();
  toast(`Добавлено: ${shortName(att.name)}`);
}

async function attachFiles(files) {
  for (const f of files) {
    if (f.size > 1_000_000) { toast(`${f.name}: больше 1 МБ, не беру`); continue; }
    let text;
    try { text = await f.text(); } catch { toast(`${f.name}: не удалось прочитать`); continue; }
    if (text.includes('\u0000')) { toast(`${f.name}: похоже на бинарный файл`); continue; }
    const cut = text.length > 60000;
    attach({ name: f.name, body: cut ? text.slice(0, 60000) : text, truncated: cut });
  }
}

/* ================= события ================= */

function autosize() {
  const i = $('input');
  i.style.height = 'auto';
  i.style.height = Math.min(i.scrollHeight, 220) + 'px';
}

const connectorCtx = { attach };
const settingsCtx = {
  models: () => models,
  refresh(full) {
    applyAppearance();
    renderModelBtn();
    updateComposer();
    if (full) renderAll();
    else if (!activeChat()?.messages.length) renderThread();
  },
};

function bind() {
  $('composer').addEventListener('submit', (e) => {
    e.preventDefault();
    if (running) return stopRun();
    send($('input').value);
  });
  $('input').addEventListener('input', autosize);
  $('input').addEventListener('keydown', (e) => {
    if (e.key !== 'Enter' || e.isComposing) return;
    const wants = e.ctrlKey || e.metaKey || (state.settings.enterToSend && fineCursor() && !e.shiftKey);
    if (wants) {
      e.preventDefault();
      $('composer').requestSubmit();
    }
  });

  $('newChat').addEventListener('click', newChat);
  $('menuBtn').addEventListener('click', () => { $('shell').dataset.rail = 'open'; });
  $('scrim').addEventListener('click', closeRail);
  $('openSettings').addEventListener('click', () => { closeRail(); openSettings(settingsCtx); });
  $('openConnectors').addEventListener('click', () => { closeRail(); openConnectors(connectorCtx); });
  $('ctxBtn').addEventListener('click', () => openConnectors(connectorCtx));
  $('attachBtn').addEventListener('click', () => $('fileInput').click());
  $('fileInput').addEventListener('change', async (e) => {
    await attachFiles([...e.target.files]);
    e.target.value = '';
  });
  $('modelBtn').addEventListener('click', openModelDialog);
  $('modelSearch').addEventListener('input', (e) => drawModels(e.target.value.trim()));

  $('chatTitle').title = 'Нажми, чтобы переименовать чат';
  $('chatTitle').addEventListener('click', () => {
    const c = activeChat();
    if (!c) return;
    const t = prompt('Название чата', c.title);
    if (t && t.trim()) {
      c.title = t.trim().slice(0, 80);
      saveChats(true);
      renderChatList();
      renderTitle();
    }
  });

  const comp = $('composer');
  comp.addEventListener('dragover', (e) => { if (e.dataTransfer?.types?.includes('Files')) e.preventDefault(); });
  comp.addEventListener('drop', (e) => {
    if (!e.dataTransfer?.files?.length) return;
    e.preventDefault();
    attachFiles([...e.dataTransfer.files]);
  });

  $('thread').addEventListener('click', async (e) => {
    const copyBtn = e.target.closest('[data-copy]');
    if (copyBtn) {
      const code = copyBtn.closest('.code')?.querySelector('code')?.textContent || '';
      const ok = await copyText(code);
      copyBtn.textContent = ok ? 'Скопировано' : 'Не вышло';
      setTimeout(() => { copyBtn.textContent = 'Копировать'; }, 1300);
      return;
    }
    const act = e.target.closest('[data-act]');
    if (!act) return;
    if (act.dataset.act === 'retry') return retry();
    if (act.dataset.act === 'copy') {
      const id = act.closest('.msg')?.dataset.id;
      const m = activeChat()?.messages.find((x) => x.id === id);
      if (m && (await copyText(m.text))) toast('Ответ скопирован');
    }
  });

  for (const dlg of document.querySelectorAll('dialog')) {
    dlg.addEventListener('click', (e) => {
      if (e.target === dlg || e.target.closest('[data-close]')) dlg.close();
    });
  }
  matchMedia('(pointer: fine)').addEventListener?.('change', updateComposer);
}

async function init() {
  bind();
  renderAll();
  try {
    const j = await loadModels();
    models = j.models || [];
    serverInfo = { serverKey: Boolean(j.serverKey), gated: Boolean(j.gated), fallback: Boolean(j.fallback) };
  } catch {
    models = [];
    toast('Не загрузился список моделей, попробую запасной вариант при отправке');
  }
  renderModelBtn();
  if (!activeChat()?.messages.length) renderThread();
}

init();
