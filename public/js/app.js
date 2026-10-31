import {
  state, saveSettings, saveChats, MODES, THEMES, setMode, chatsFor, getChat, createChat, deleteChat, systemPrompt, rankModels, uid,
} from './store.js';
import { renderMarkdown, titleFrom } from './md.js';
import { el, icon, ICONS, toast, copyText } from './ui.js';
import { loadModels, streamChat, explain, isRetryable } from './api.js';
import { applyAppearance } from './appearance.js';
import { openSettings } from './settings.js';
import { openConnectors } from './connectors.js';
import * as W from './workspace.js';
import * as S from './sandbox.js';
import * as P from './panel.js';
import { openPalette, initPalette } from './palette.js';
import {
  agentSystem, loadRules, parseCalls, stripCalls, liveTool, cutHallucination, execTool, resultBlock,
  compactAssistant, compactResult, TOOL_LABELS, MAX_CALLS_PER_TURN,
} from './agent.js';

const $ = (id) => document.getElementById(id);
const HISTORY_BUDGET = 60000; // символов контекста; старые реплики отбрасываются
const MAX_ATTACH = 8;
const KEEP_FULL = 8; // сколько последних реплик агента не сжимать

let models = [];
let serverInfo = { serverKey: false, gated: false, fallback: false };
let running = null; // { controller, chatId, msgId, phase }
const pending = []; // вложения, ещё не отправленные
const autoApprove = new Set(); // id чатов, где разрешено «применять всё»

const activeChat = () => (state.activeId ? getChat(state.activeId) : null);
const fineCursor = () => matchMedia('(pointer: fine)').matches;
const agentOn = (mode = state.mode) => mode === 'code' && state.settings.agent.on;

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
  const a = state.settings.agent;
  $('agentBtn').setAttribute('aria-pressed', String(a.on));
  $('planBtn').setAttribute('aria-pressed', String(a.plan));
  $('planBtn').disabled = !a.on;
  $('panelBtn').setAttribute('aria-pressed', String(P.isOpen()));
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
  const lead = state.mode === 'code' && state.settings.agent.on
    ? 'Агент сам пишет файлы, правит их и проверяет результат в превью. Бесплатные модели, твой дизайн.'
    : `${m.hint}. Бесплатные модели, твои промты, твой дизайн.`;
  const box = el('div', { class: 'empty' }, el('h2', { class: 'mode-word' }, m.label), el('p', { class: 'empty-lead' }, lead));
  const note = setupNote();
  if (note) box.append(note);
  box.append(
    el(
      'div', { class: 'starters' },
      ...m.starters.map((s) => el('button', { class: 'starter', type: 'button', onclick: () => { closeRail(); send(s); } }, s))
    )
  );
  if (state.mode === 'code') {
    const n = W.ws.index.length;
    box.append(
      el('p', { class: 'help', style: 'margin-top:18px' },
        el('button', { class: 'link-btn', type: 'button', onclick: () => P.openPanel('files') }, `Проект «${W.ws.name}»: ${n ? `${n} файл.` : 'пока пусто'}`),
        ' · ',
        el('button', { class: 'link-btn', type: 'button', onclick: () => openConnectors(connectorCtx) }, 'Файлы из GitHub или лог Vercel'))
    );
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

const shownText = (m) => (m.agent ? stripCalls(m.text || '') : m.text || '');

const STEP_MARK = { run: '', ok: '✓', err: '!', rejected: '×' };

function stepsEl(m) {
  return el(
    'div', { class: 'steps' },
    ...m.steps.map((s) =>
      el(
        'button',
        { class: `step ${s.status}`, type: 'button', title: s.note || '', onclick: () => stepClick(s) },
        el('span', { class: 'si' }, STEP_MARK[s.status] ?? ''),
        el('span', { class: 'sl' }, s.label || TOOL_LABELS[s.name] || s.name),
        s.add != null ? el('span', { class: 'stat' }, el('b', { class: 'plus' }, `+${s.add}`), ' ', el('b', { class: 'minus' }, `−${s.del}`)) : null,
        s.note && s.status !== 'run' ? el('small', {}, s.note) : null
      )
    )
  );
}

function stepClick(s) {
  if (s.changeId && W.ws.history.some((h) => h.id === s.changeId)) return P.focusChange(s.changeId);
  if (s.name === 'preview') return P.openPanel('preview');
  if (s.name === 'run_js') return P.openPanel('console');
  if (s.path && W.exists(s.path) && ['read_file', 'write_file', 'edit_file'].includes(s.name)) return P.showFile(s.path);
  P.openPanel('files');
}

function msgEl(m, chat) {
  if (m.hidden) return null;
  if (m.role === 'user') {
    const node = el('article', { class: 'msg user', dataset: { id: m.id } }, el('div', { class: 'bubble' }, m.text || '(без текста)'));
    if (m.atts?.length) node.append(el('div', { class: 'msg-atts' }, ...m.atts.map((a) => el('span', { class: 'chip-ro', title: a.name }, shortName(a.name)))));
    return node;
  }
  const streaming = running && running.msgId === m.id && running.phase === 'stream';
  const working = running && running.msgId === m.id && running.phase === 'tools';
  const node = el('article', { class: 'msg assistant' + (streaming ? ' streaming' : '') + (working ? ' working' : ''), dataset: { id: m.id } });
  node.append(el('div', { class: 'meta' }, el('span', { class: 'who' }, m.model || 'Модель'), m.note ? el('span', { class: 'note' }, m.note) : null));
  const txt = shownText(m);
  if (txt || streaming || !m.steps?.length) {
    const prose = el('div', { class: 'prose' });
    prose.innerHTML = renderMarkdown(txt);
    node.append(prose);
  }
  if (streaming) node.append(el('div', { class: 'live-slot' }));
  if (m.steps?.length) node.append(stepsEl(m));
  if (m.error) node.append(errNote(m.error));
  if (!streaming && !working) {
    const last = lastVisible(chat) === m;
    node.append(
      el(
        'div', { class: 'actions' },
        txt ? el('button', { class: 'act', type: 'button', dataset: { act: 'copy' } }, 'Копировать') : null,
        last ? el('button', { class: 'act', type: 'button', dataset: { act: 'retry' } }, 'Ещё раз') : null
      )
    );
  }
  return node;
}

function lastVisible(chat) {
  for (let i = chat.messages.length - 1; i >= 0; i--) if (!chat.messages[i].hidden) return chat.messages[i];
  return null;
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
  for (const m of chat.messages) {
    const n = msgEl(m, chat);
    if (n) t.append(n);
  }
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
    const node = $('thread').querySelector(`[data-id="${msg.id}"]`);
    const prose = node?.querySelector('.prose');
    if (!prose) return;
    const w = $('threadWrap');
    const stick = w.scrollHeight - w.scrollTop - w.clientHeight < 160;
    prose.innerHTML = renderMarkdown(shownText(msg));
    const slot = node.querySelector('.live-slot');
    if (slot) {
      const lt = msg.agent ? liveTool(msg.text) : null;
      slot.textContent = lt ? `${TOOL_LABELS[lt.name] || lt.name}${lt.path ? ' ' + lt.path : ''}… ${lt.chars.toLocaleString('ru')} символов` : '';
    }
    if (stick) w.scrollTop = w.scrollHeight;
  });
}

function replaceMsg(msg, chat) {
  if (state.activeId !== chat.id) return;
  const node = $('thread').querySelector(`[data-id="${msg.id}"]`);
  if (!node) return;
  if (!chat.messages.includes(msg)) return node.remove();
  const next = msgEl(msg, chat);
  if (next) node.replaceWith(next);
  const w = $('threadWrap');
  if (w.scrollHeight - w.scrollTop - w.clientHeight < 200) w.scrollTop = w.scrollHeight;
}

function toContent(m) {
  if (m.role !== 'user' || !m.atts?.length) return m.text;
  const files = m.atts
    .map((a) => `<file name="${a.name.replace(/"/g, "'")}"${a.truncated ? ' truncated="true"' : ''}>\n${a.body}\n</file>`)
    .join('\n\n');
  return `${files}\n\n${m.text || 'Посмотри вложения.'}`;
}

async function buildMessages(chat, endIdx, agent) {
  let sys = systemPrompt(chat.mode);
  if (agent) {
    const rules = state.settings.agent.rules ? await loadRules() : null;
    sys = agentSystem({ base: sys, rules, plan: state.settings.agent.plan, tree: W.treeText(150), projectName: W.ws.name, kind: W.ws.kind });
  }
  const slice = chat.messages.slice(0, endIdx).filter((m) => m.role === 'user' || (m.text || '').trim());
  const hist = slice.map((m, i) => {
    const old = i < slice.length - KEEP_FULL;
    let content = toContent(m);
    if (old && m.role === 'assistant' && m.agent) content = compactAssistant(content);
    if (old && m.hidden) content = compactResult(content);
    return { role: m.role, content };
  });
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

// Одна реплика модели со стримингом и переключением на запасные модели.
async function streamReply(chat, controller, { agent = false } = {}) {
  const msg = { id: uid(), role: 'assistant', text: '', model: '', ts: Date.now(), agent };
  chat.messages.push(msg);
  chat.updated = Date.now();
  running.msgId = msg.id;
  running.phase = 'stream';
  saveChats(true);
  renderChatList();
  renderTitle();
  renderThread();
  setSendState();

  const history = await buildMessages(chat, chat.messages.length - 1, agent);
  let ranked = rankModels(chat.mode, models);
  // Модель, которая уже ответила в этом запуске, идёт первой: не мучаем снова ту, что падала.
  const pi = running.pref ? ranked.findIndex((x) => x.id === running.pref) : -1;
  if (pi > 0) ranked = [ranked[pi], ...ranked.filter((_, j) => j !== pi)];
  const tries = ranked.length
    ? ranked.slice(0, state.settings.autoSwitch ? 4 : 1)
    : [{ id: state.settings.models[chat.mode] || 'openrouter/free', name: 'Авто' }];

  let lastErr = null;
  let aborted = false;
  let finish = '';
  for (let i = 0; i < tries.length; i++) {
    const m = tries[i];
    msg.model = m.name;
    msg.text = '';
    msg.error = null;
    msg.note = i ? 'другая модель после сбоя' : '';
    replaceMsg(msg, chat);
    try {
      const r = await streamChat({
        model: m.id,
        messages: history,
        signal: controller.signal,
        stop: agent ? ['<tool_result'] : undefined,
        onDelta: (d) => { msg.text += d; paintStream(msg); },
      });
      finish = r?.finish || '';
      running.pref = m.id;
      lastErr = null;
      break;
    } catch (e) {
      if (e.name === 'AbortError') {
        aborted = true;
        lastErr = null;
        if (msg.text) msg.note = msg.note ? `${msg.note} · остановлено` : 'остановлено';
        break;
      }
      lastErr = e;
      if (msg.text || !isRetryable(e) || i === tries.length - 1) break;
    }
  }
  if (lastErr) msg.error = { message: lastErr.message, code: lastErr.code, status: lastErr.status };
  if (agent) msg.text = cutHallucination(msg.text);
  if (!msg.text && !msg.error) chat.messages = chat.messages.filter((x) => x !== msg);
  return { msg, aborted, finish, failed: Boolean(lastErr) };
}

async function complete(chat) {
  const controller = new AbortController();
  running = { controller, chatId: chat.id, msgId: null, phase: 'stream' };
  let last = null;
  try {
    if (agentOn(chat.mode)) last = await runAgent(chat, controller);
    else last = (await streamReply(chat, controller)).msg;
  } catch (e) {
    console.error(e);
    toast('Что-то сломалось внутри: ' + (e.message || 'неизвестная ошибка'));
  } finally {
    hideApproval();
    running = null;
    chat.updated = Date.now();
    saveChats(true);
    setSendState();
    renderChatList();
    if (state.activeId === chat.id) {
      if (last) replaceMsg(last, chat);
      // сообщения без стрима перерисуем целиком, чтобы убрать индикаторы работы
      renderThread();
    }
  }
}

/* ================= агент ================= */

const WRITERS = new Set(['write_file', 'edit_file', 'delete_file']);

function needConfirm(chat) {
  const mode = state.settings.agent.confirm;
  if (autoApprove.has(chat.id)) return false;
  return mode === 'ask' || (mode === 'smart' && W.ws.kind === 'fs');
}

function toolCtx(chat, controller) {
  return {
    signal: controller.signal,
    confirm: (change) => (needConfirm(chat) ? askApproval(chat, change, controller) : Promise.resolve(true)),
    runJs: (code) => S.runJs(code),
    preview: (path) => P.checkPreview(path),
  };
}

async function runAgent(chat, controller) {
  const max = Math.max(2, Math.min(40, Number(state.settings.agent.steps) || 14));
  const ctx = toolCtx(chat, controller);
  let last = null;
  let step = 0;
  for (; step < max; step++) {
    const r = await streamReply(chat, controller, { agent: true });
    const msg = r.msg;
    last = msg;
    if (r.aborted || r.failed || !chat.messages.includes(msg)) break;

    const { calls, truncated } = parseCalls(msg.text);
    if (!calls.length && !truncated) break;

    running.phase = 'tools';
    msg.steps = [];
    replaceMsg(msg, chat);
    const blocks = [];
    const usedPreview = calls.some((c) => c.name === 'preview');
    const todo = calls.slice(0, MAX_CALLS_PER_TURN);

    for (const call of todo) {
      if (controller.signal.aborted) break;
      const st = { name: call.name, path: call.attrs.path || '', label: `${TOOL_LABELS[call.name]} ${call.attrs.path || ''}`.trim(), status: 'run' };
      msg.steps.push(st);
      replaceMsg(msg, chat);

      let res;
      if (state.settings.agent.plan && WRITERS.has(call.name)) {
        res = { ok: false, output: 'Сейчас режим плана: менять файлы нельзя. Предложи план текстом и дождись ответа пользователя.', step: { ...st, status: 'err', note: 'режим плана' } };
      } else {
        res = await execTool(call, ctx);
      }
      Object.assign(st, res.step);
      blocks.push(resultBlock(call, res));

      if (res.ok && !usedPreview && WRITERS.has(call.name) && /\.html?$/i.test(st.path)) {
        if (!P.isOpen() || P.previewing() === st.path || !P.previewing()) P.previewFile(st.path);
      } else if (res.ok && call.name === 'write_file' && !P.isOpen()) {
        P.openPanel('files');
      }
      replaceMsg(msg, chat);
    }
    if (calls.length > todo.length) blocks.push(`Выполнено только ${todo.length} из ${calls.length} вызовов (лимит за один ход). Остальные повтори следующим ходом.`);
    if (truncated) {
      blocks.push(
        `<tool_result name="${truncated.name}" ok="false">\nТвой ответ оборвался по длине на блоке ${truncated.name}, файл НЕ записан. Пиши файл короче или по частям: сначала каркас через write_file, потом дополняй через edit_file.\n</tool_result>`
      );
    }
    if (controller.signal.aborted) {
      msg.note = msg.note ? `${msg.note} · остановлено` : 'остановлено';
      msg.steps.forEach((s) => { if (s.status === 'run') { s.status = 'err'; s.note = 'остановлено'; } });
      break;
    }
    chat.messages.push({
      id: uid(), role: 'user', hidden: true, ts: Date.now(),
      text: `${blocks.join('\n\n')}\n\nПродолжай. Если задача выполнена, ответь коротким итогом без вызовов инструментов.`,
    });
    saveChats(true);
    if (!chat.messages.includes(msg)) break;
  }
  if (step >= max && last) {
    last.note = last.note ? `${last.note} · лимит шагов` : 'лимит шагов, напиши «продолжай»';
  }
  return last;
}

/* ---------- согласование правок ---------- */

let approvalCleanup = null;

function hideApproval() {
  approvalCleanup?.();
  approvalCleanup = null;
  const box = $('approval');
  box.hidden = true;
  box.replaceChildren();
}

function askApproval(chat, change, controller) {
  return new Promise((resolve) => {
    hideApproval();
    const box = $('approval');
    const verb = change.kind === 'create' ? 'создать' : change.kind === 'delete' ? 'удалить' : 'изменить';
    const done = (v) => {
      hideApproval();
      resolve(v);
    };
    const onAbort = () => done(false);
    controller.signal.addEventListener('abort', onAbort, { once: true });
    approvalCleanup = () => controller.signal.removeEventListener('abort', onAbort);

    const small = change.stats.add + change.stats.del <= 40;
    const diff = el('details', { class: 'ap-diff', open: small || undefined }, el('summary', {}, 'Показать изменения'), P.renderDiff(change.ops));
    box.replaceChildren(
      el('div', { class: 'ap-head' },
        el('span', {}, `Агент хочет ${verb} `, el('code', {}, change.path)),
        el('span', { class: 'stat' }, el('b', { class: 'plus' }, `+${change.stats.add}`), ' ', el('b', { class: 'minus' }, `−${change.stats.del}`))),
      diff,
      el('div', { class: 'ap-btns' },
        el('button', { class: 'btn', type: 'button', onclick: () => done(false) }, 'Отклонить'),
        el('button', { class: 'btn', type: 'button', onclick: () => { autoApprove.add(chat.id); done(true); } }, 'Применять всё в этом чате'),
        el('button', { class: 'btn primary', type: 'button', onclick: () => done(true) }, 'Применить'))
    );
    box.hidden = false;
    const w = $('threadWrap');
    w.scrollTop = w.scrollHeight;
  });
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
  while (chat.messages.length && (chat.messages[chat.messages.length - 1].role === 'assistant' || chat.messages[chat.messages.length - 1].hidden)) chat.messages.pop();
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

/* ================= команды ================= */

function toggleAgent(key) {
  const a = state.settings.agent;
  a[key] = !a[key];
  saveSettings();
  updateComposer();
  if (!activeChat()?.messages.length) renderThread();
  toast(key === 'on' ? (a.on ? 'Агент включён' : 'Агент выключен, обычный чат') : a.plan ? 'Режим плана: без правок' : 'Режим плана выключен');
}

function suggestName(lang, code) {
  const l = String(lang || '').toLowerCase();
  const base = { html: 'index.html', htm: 'index.html', svg: 'image.svg', css: 'style.css', js: 'script.js', javascript: 'script.js', ts: 'main.ts', typescript: 'main.ts', py: 'main.py', python: 'main.py', json: 'data.json', sh: 'run.sh', bash: 'run.sh', md: 'README.md' }[l]
    || (/^\s*(<!doctype html|<html)/i.test(code) ? 'index.html' : 'file.txt');
  if (!W.exists(base)) return base;
  const [n, ext] = base.split(/\.(?=[^.]+$)/);
  for (let i = 2; i < 100; i++) if (!W.exists(`${n}-${i}.${ext}`)) return `${n}-${i}.${ext}`;
  return base;
}

async function saveSnippet(code, lang) {
  const name = prompt('Сохранить в проект как', suggestName(lang, code));
  if (!name || !name.trim()) return;
  try {
    const path = name.trim();
    const before = W.exists(path) ? await W.readText(path).catch(() => null) : null;
    if (before !== null && !confirm(`Файл ${path} уже есть. Заменить?`)) return;
    await W.writeText(path, code);
    W.recordChange(`${before === null ? 'Создан' : 'Заменён'} ${path} из чата`, [{ path, before, after: code }]);
    toast(`Сохранено: ${path}`);
    P.showFile(path);
  } catch (e) { toast(e.message || 'Не получилось сохранить'); }
}

function commands() {
  const list = [
    { label: 'Новый чат', run: newChat },
    ...Object.values(MODES).map((m) => ({ label: `Режим ${m.label}`, hint: m.hint, run: () => switchMode(m.id), when: () => state.mode !== m.id })),
    { label: 'Выбрать модель', run: openModelDialog },
    { label: 'Настройки', run: () => openSettings(settingsCtx) },
    { label: 'Коннекторы', hint: 'GitHub, Vercel', run: () => openConnectors(connectorCtx) },
    { label: 'Остановить ответ', hint: 'Esc', run: stopRun, when: () => Boolean(running) },
  ];
  if (state.mode === 'code') {
    list.push(
      { label: P.isOpen() ? 'Скрыть панель проекта' : 'Показать панель проекта', hint: 'Ctrl J', run: () => P.togglePanel() },
      { label: 'Файлы проекта', run: () => P.openPanel('files') },
      { label: 'Превью', hint: 'открыть index.html', run: () => (W.exists('index.html') ? P.previewFile('index.html') : P.openPanel('preview')) },
      { label: 'Консоль', run: () => P.openPanel('console') },
      { label: 'Правки и откат', run: () => P.openPanel('changes') },
      { label: 'Откатить последнюю правку', run: async () => { const e = W.ws.history.find((h) => !h.undone); if (!e) return toast('Откатывать нечего'); await W.undoEntry(e.id); toast(`Откатил: ${e.label}`); } },
      { label: 'Открыть папку с компьютера', hint: 'Chrome, Edge', run: () => W.pickFolder().then(() => toast(`Подключена папка «${W.ws.name}»`)).catch((e) => { if (e.name !== 'AbortError') toast(e.message || 'Не вышло'); }), when: () => W.hasFsApi && W.ws.kind !== 'fs' },
      { label: 'Вернуться в песочницу', run: () => W.useVirtual(), when: () => W.ws.kind === 'fs' },
      { label: state.settings.agent.on ? 'Выключить агента' : 'Включить агента', run: () => toggleAgent('on') },
      { label: state.settings.agent.plan ? 'Выключить режим плана' : 'Включить режим плана', hint: 'сначала план, без правок', run: () => toggleAgent('plan'), when: () => state.settings.agent.on }
    );
  }
  for (const t of THEMES) list.push({ label: `Тема: ${t.label}`, run: () => { state.settings.theme = t.id; saveSettings(); applyAppearance(); }, when: () => state.settings.theme !== t.id });
  list.push({
    label: 'Скопировать последний ответ',
    run: async () => {
      const m = [...(activeChat()?.messages || [])].reverse().find((x) => x.role === 'assistant' && shownText(x));
      if (m && (await copyText(shownText(m)))) toast('Ответ скопирован');
    },
  });
  return list;
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
  $('openPalette').addEventListener('click', () => { closeRail(); openPalette(commands()); });
  $('ctxBtn').addEventListener('click', () => openConnectors(connectorCtx));
  $('attachBtn').addEventListener('click', () => $('fileInput').click());
  $('agentBtn').addEventListener('click', () => toggleAgent('on'));
  $('planBtn').addEventListener('click', () => toggleAgent('plan'));
  $('panelBtn').addEventListener('click', () => P.togglePanel());
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
    const block = e.target.closest('.code');
    const codeOf = () => block?.querySelector('code')?.textContent || '';
    const copyBtn = e.target.closest('[data-copy]');
    if (copyBtn) {
      const ok = await copyText(codeOf());
      copyBtn.textContent = ok ? 'Скопировано' : 'Не вышло';
      setTimeout(() => { copyBtn.textContent = 'Копировать'; }, 1300);
      return;
    }
    if (e.target.closest('[data-run]')) return P.previewSnippet(codeOf(), block.dataset.lang);
    if (e.target.closest('[data-save]')) return saveSnippet(codeOf(), block.dataset.lang);
    const act = e.target.closest('[data-act]');
    if (!act) return;
    if (act.dataset.act === 'retry') return retry();
    if (act.dataset.act === 'copy') {
      const id = act.closest('.msg')?.dataset.id;
      const m = activeChat()?.messages.find((x) => x.id === id);
      if (m && (await copyText(shownText(m)))) toast('Ответ скопирован');
    }
  });

  for (const dlg of document.querySelectorAll('dialog')) {
    dlg.addEventListener('click', (e) => {
      if (e.target === dlg || e.target.closest('[data-close]')) dlg.close();
    });
  }
  matchMedia('(pointer: fine)').addEventListener?.('change', updateComposer);

  document.addEventListener('keydown', (e) => {
    const mod = e.ctrlKey || e.metaKey;
    const key = e.key.toLowerCase();
    if (mod && key === 'k') {
      e.preventDefault();
      const dlg = $('palette');
      if (dlg.open) dlg.close();
      else openPalette(commands());
    } else if (mod && key === 'j' && state.mode === 'code') {
      e.preventDefault();
      P.togglePanel();
    } else if (e.key === 'Escape' && running && !document.querySelector('dialog[open]')) {
      stopRun();
    }
  });
}

async function init() {
  initPalette();
  P.initPanel({ openConnectors: () => openConnectors(connectorCtx), onToggle: () => updateComposer(), onWorkspace: (ev) => { if (ev.type === 'kind' || ev.type === 'index') { if (!activeChat()?.messages.length) renderThread(); } } });
  bind();
  renderAll();
  W.initWorkspace().catch(() => {});
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

// Для отладки и e2e-тестов.
window.__pult = { W, S, P, state };
