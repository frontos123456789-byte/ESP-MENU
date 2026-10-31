// Агентный слой: текстовый протокол инструментов, который работает с любой моделью (без tool calling API),
// разбор вызовов, выполнение над рабочим проектом, сжатие истории.

import * as W from './workspace.js';
import { diffLines, diffStats } from './diff.js';

export const MAX_CALLS_PER_TURN = 10;

export const TOOL_LABELS = {
  list_files: 'Смотрю файлы',
  read_file: 'Читаю',
  search: 'Ищу',
  write_file: 'Пишу',
  edit_file: 'Правлю',
  delete_file: 'Удаляю',
  run_js: 'Запускаю код',
  preview: 'Проверяю превью',
};
const KNOWN = new Set(Object.keys(TOOL_LABELS));

export const AGENT_RULES = `Ты работаешь как агент: сам смотришь файлы, пишешь и правишь код в проекте пользователя и проверяешь результат.

Вызов инструмента — это блок прямо в твоём ответе, ровно в таком виде (не оборачивай в тройные кавычки и не меняй теги):

<tool name="list_files" path="src"/>
<tool name="read_file" path="src/app.js" from="1" to="80"/>
<tool name="search" query="handleClick"/>
<tool name="write_file" path="index.html">
весь текст файла
</tool>
<tool name="edit_file" path="src/app.js">
<old>точный фрагмент, который нужно заменить</old>
<new>на что заменить</new>
</tool>
<tool name="delete_file" path="old.js"/>
<tool name="run_js">
console.log(2 + 2)
</tool>
<tool name="preview" path="index.html"/>

Что делает каждый: list_files — список файлов (path необязателен); read_file — прочитать файл (from и to необязательны); search — поиск текста по проекту (regex="true" для регулярки); write_file — создать или целиком перезаписать файл; edit_file — точечная правка, old должен встретиться в файле ровно один раз, можно несколько пар old/new; delete_file — удалить файл; run_js — выполнить JavaScript в изолированной песочнице и получить вывод консоли; preview — открыть html из проекта в превью и получить ошибки консоли.

Правила:
1. Сначала скажи в одной-двух фразах, что собираешься сделать, потом вызывай инструменты. После блоков остановись: результат придёт следующим сообщением. Не придумывай результат сам.
2. Перед правкой существующего файла прочитай его. Мелкие изменения делай через edit_file, новые файлы и большие переписывания через write_file с полным содержимым, без пропусков вроде «остальной код без изменений».
3. Веб-проекты собирай так, чтобы они открывались из index.html без сборки: обычные HTML, CSS и JS (ES-модули с относительными импортами можно), без npm и внешних файлов. Картинки, звук и видео, если не просили иначе, создавай кодом (canvas, SVG, WebAudio). Для звука нужен клик пользователя, поэтому делай экран «Нажми, чтобы начать».
4. После создания или крупной правки html вызови preview, прочитай ошибки консоли и исправь их. Не больше трёх попыток починки подряд.
5. Когда всё готово, ответь коротким итогом без блоков инструментов: что сделано и что открыть. Код не пересказывай.
6. Файлы с секретами (.env, ключи) недоступны. Пути только внутри проекта, без «..».`;

export const PLAN_RULES = 'РЕЖИМ ПЛАНА: ничего не меняй и не запускай. Сначала предложи короткий нумерованный план и жди ответа пользователя. Читать файлы можно.';

export function agentSystem({ base, rules, plan, tree, projectName, kind }) {
  const parts = [base, AGENT_RULES];
  if (plan) parts.push(PLAN_RULES);
  parts.push(`Проект: «${projectName}» (${kind === 'fs' ? 'папка на компьютере пользователя, правки пишутся в реальные файлы' : 'песочница в браузере'}).\nФайлы:\n${tree || '(пока пусто)'}`);
  if (rules) parts.push(`Правила проекта (из ${rules.name}):\n${rules.text}`);
  return parts.join('\n\n');
}

export async function loadRules() {
  for (const name of ['AGENTS.md', 'CLAUDE.md', '.pultrules', 'PULT.md']) {
    if (!W.exists(name)) continue;
    try {
      const text = (await W.readText(name, 100_000)).trim();
      if (text) return { name, text: text.slice(0, 4000) };
    } catch { /* пропускаем */ }
  }
  return null;
}

/* ---------- разбор ---------- */

function attrsOf(s) {
  const a = {};
  for (const m of s.matchAll(/([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) a[m[1]] = m[2] ?? m[3] ?? '';
  return a;
}

function stripFence(body) {
  let b = body.replace(/^\r?\n/, '').replace(/\r?\n$/, '');
  const m = b.match(/^```[^\n]*\n([\s\S]*?)\n?```\s*$/);
  if (m) b = m[1];
  return b;
}

const CALL_RE = /<tool\s+name\s*=\s*["'](\w+)["']([^>]*?)(?:\/>|>([\s\S]*?)<\/tool>)/g;

// Режем всё после выдуманного ответа инструмента.
export function cutHallucination(text) {
  const i = text.search(/<tool_result\b/);
  return i >= 0 ? text.slice(0, i) : text;
}

export function parseCalls(rawText) {
  const text = cutHallucination(rawText);
  const calls = [];
  let end = 0;
  for (const m of text.matchAll(CALL_RE)) {
    end = m.index + m[0].length;
    if (!KNOWN.has(m[1])) continue;
    calls.push({ name: m[1], attrs: attrsOf(m[2] || ''), body: m[3] ?? '' });
  }
  // оборванный блок в конце (модель упёрлась в лимит длины)
  const tail = text.slice(end);
  const open = tail.match(/<tool\s+name\s*=\s*["'](\w+)["']([^>]*)>/);
  const truncated = open && !/<\/tool>/.test(tail.slice(open.index)) && !/\/>\s*$/.test(open[0]) ? { name: open[1], attrs: attrsOf(open[2] || '') } : null;
  return { calls, truncated, text };
}

// Текст для показа: без блоков инструментов.
export function stripCalls(raw) {
  let t = cutHallucination(raw);
  t = t.replace(CALL_RE, '');
  const i = t.search(/<tool\s+name\s*=/);
  if (i >= 0) t = t.slice(0, i);
  return t.replace(/\n{3,}/g, '\n\n').trim();
}

// Что модель пишет прямо сейчас (для живого индикатора).
export function liveTool(raw) {
  const t = cutHallucination(raw);
  const last = [...t.matchAll(/<tool\s+name\s*=\s*["'](\w+)["']([^>]*)>?/g)].pop();
  if (!last) return null;
  const tail = t.slice(last.index);
  if (/<\/tool>/.test(tail) || /\/>/.test(last[0])) return null;
  const a = attrsOf(last[2] || '');
  return { name: last[1], path: a.path || '', chars: tail.length };
}

/* ---------- сжатие старой истории ---------- */

export function compactAssistant(raw) {
  return raw.replace(CALL_RE, (full, name, attrs, body) => {
    if (body == null || (name !== 'write_file' && name !== 'edit_file' && name !== 'run_js')) return full;
    const lines = body.split('\n').length;
    return `<tool name="${name}"${attrs}>[содержимое: ${lines} стр., уже применено]</tool>`;
  });
}

export function compactResult(text) {
  return text.replace(/(<tool_result\b[^>]*>)([\s\S]*?)(<\/tool_result>)/g, (m, a, body, c) =>
    body.length > 500 ? `${a}${body.slice(0, 480)}\n…[обрезано в истории]\n${c}` : m
  );
}

/* ---------- выполнение ---------- */

const short = (s, n = 60) => (s.length > n ? s.slice(0, n - 1) + '…' : s);

function pairsOf(body) {
  const pairs = [];
  for (const m of body.matchAll(/<old>([\s\S]*?)<\/old>\s*<new>([\s\S]*?)<\/new>/g)) {
    const clean = (s) => s.replace(/^\r?\n/, '').replace(/\r?\n$/, '');
    pairs.push({ old: clean(m[1]), neu: clean(m[2]) });
  }
  return pairs;
}

// Замена с запасным вариантом: сравнение по строкам без хвостовых пробелов.
export function applyEdit(text, oldStr, newStr) {
  if (!oldStr) return { error: 'пустой <old>' };
  const first = text.indexOf(oldStr);
  if (first >= 0) {
    if (text.indexOf(oldStr, first + 1) >= 0) return { error: 'фрагмент встречается больше одного раза, добавь окружающие строки' };
    return { text: text.slice(0, first) + newStr + text.slice(first + oldStr.length) };
  }
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  const want = oldStr.replace(/\r\n/g, '\n').split('\n').map((l) => l.trimEnd());
  const hits = [];
  for (let i = 0; i + want.length <= lines.length; i++) {
    let ok = true;
    for (let j = 0; j < want.length; j++) {
      if (lines[i + j].trimEnd() !== want[j]) { ok = false; break; }
    }
    if (ok) hits.push(i);
  }
  if (hits.length === 1) {
    const out = [...lines.slice(0, hits[0]), ...newStr.replace(/\r\n/g, '\n').split('\n'), ...lines.slice(hits[0] + want.length)];
    return { text: out.join('\n') };
  }
  return { error: hits.length ? 'фрагмент встречается больше одного раза' : 'такого фрагмента в файле нет (проверь пробелы и отступы, прочитай файл заново)' };
}

const lineCount = (s) => (s === '' ? 0 : s.split('\n').length);

function numbered(text, from, to) {
  const lines = text.split('\n');
  const a = Math.max(1, from || 1);
  const b = Math.min(lines.length, to || lines.length);
  return { body: lines.slice(a - 1, b).join('\n'), a, b, total: lines.length };
}

/**
 * Выполняет один вызов. ctx: { confirm(change) -> Promise<boolean>, runJs(code), preview(path), signal }
 * Возвращает { ok, output, step }.
 */
export async function execTool(call, ctx) {
  const { name, attrs } = call;
  const step = { name, path: attrs.path || '', label: '', status: 'ok' };
  const fail = (msg) => {
    step.status = 'err';
    step.note = msg;
    return { ok: false, output: msg, step };
  };

  try {
    switch (name) {
      case 'list_files': {
        step.label = attrs.path ? `${TOOL_LABELS[name]} ${attrs.path}` : TOOL_LABELS[name];
        const t = W.treeText(300, attrs.path || '');
        return { ok: true, output: t || '(файлов нет)', step };
      }

      case 'read_file': {
        const path = W.normPath(attrs.path);
        step.path = path;
        step.label = `${TOOL_LABELS[name]} ${path}`;
        const text = await W.readText(path, 400_000);
        const from = Number(attrs.from) || 0;
        const to = Number(attrs.to) || 0;
        if (from || to) {
          const r = numbered(text, from, to);
          return { ok: true, output: `строки ${r.a}–${r.b} из ${r.total}\n${r.body}`, step };
        }
        if (text.length > 24000) {
          return { ok: true, output: `${text.slice(0, 24000)}\n…[файл обрезан, всего ${text.length} символов; читай по частям через from/to]`, step };
        }
        return { ok: true, output: text === '' ? '(файл пустой)' : text, step };
      }

      case 'search': {
        const q = attrs.query || call.body.trim();
        if (!q) return fail('не указан query');
        step.label = `${TOOL_LABELS[name]} «${short(q, 40)}»`;
        const r = await W.searchText(q, { regex: attrs.regex === 'true' });
        return { ok: true, output: r.hits.length ? r.hits.join('\n') + (r.more ? '\n…[показаны не все совпадения]' : '') : 'Ничего не найдено', step };
      }

      case 'write_file': {
        const path = W.normPath(attrs.path);
        step.path = path;
        const after = stripFence(call.body);
        let before = null;
        if (W.exists(path)) {
          try { before = await W.readText(path); } catch { before = null; }
        }
        step.label = `${before === null ? 'Создаю' : 'Переписываю'} ${path}`;
        if (before === after) return { ok: true, output: `Файл ${path} уже содержит этот текст`, step };
        return await applyChange({ path, before, after, kind: before === null ? 'create' : 'modify' }, ctx, step);
      }

      case 'edit_file': {
        const path = W.normPath(attrs.path);
        step.path = path;
        step.label = `${TOOL_LABELS[name]} ${path}`;
        const pairs = pairsOf(call.body);
        if (!pairs.length) return fail('в edit_file нужны блоки <old>…</old><new>…</new>');
        const before = await W.readText(path);
        let text = before;
        for (let i = 0; i < pairs.length; i++) {
          const r = applyEdit(text, pairs[i].old, pairs[i].neu);
          if (r.error) return fail(`Правка ${i + 1} не применена: ${r.error}. Начало <old>: «${short(pairs[i].old, 70)}». Файл не изменён.`);
          text = r.text;
        }
        if (text === before) return { ok: true, output: 'Правка ничего не меняет', step };
        return await applyChange({ path, before, after: text, kind: 'modify' }, ctx, step);
      }

      case 'delete_file': {
        const path = W.normPath(attrs.path);
        step.path = path;
        step.label = `${TOOL_LABELS[name]} ${path}`;
        const before = await W.readText(path);
        return await applyChange({ path, before, after: null, kind: 'delete' }, ctx, step);
      }

      case 'run_js': {
        step.label = TOOL_LABELS[name];
        const code = stripFence(call.body);
        if (!code.trim()) return fail('пустой код');
        const r = await ctx.runJs(code);
        const out = r.logs.map((l) => (l.level === 'log' ? l.text : `[${l.level}] ${l.text}`)).join('\n');
        step.note = r.logs.some((l) => l.level === 'error') ? 'есть ошибки' : '';
        return { ok: true, output: (out || '(вывода нет)') + (r.timedOut ? '\n[остановлено по таймауту]' : ''), step };
      }

      case 'preview': {
        const path = W.normPath(attrs.path || 'index.html');
        step.path = path;
        step.label = `${TOOL_LABELS[name]} ${path}`;
        if (!W.exists(path)) return fail(`Файла нет: ${path}`);
        const r = await ctx.preview(path);
        const errs = r.logs.filter((l) => l.level === 'error');
        step.note = errs.length ? `ошибок: ${errs.length}` : 'без ошибок';
        const out = r.logs.map((l) => (l.level === 'log' ? l.text : `[${l.level}] ${l.text}`)).join('\n');
        return { ok: true, output: `Страница загружена. ${errs.length ? `Ошибок в консоли: ${errs.length}.` : 'Ошибок в консоли нет.'}${out ? `\n${out.slice(0, 3000)}` : ''}`, step };
      }

      default:
        return fail(`Неизвестный инструмент ${name}`);
    }
  } catch (e) {
    return fail(e.message || 'Ошибка инструмента');
  }
}

async function applyChange(change, ctx, step) {
  const ops = diffLines(change.before ?? '', change.after ?? '');
  const stats = diffStats(ops);
  step.add = stats.add;
  step.del = stats.del;
  const ok = ctx.confirm ? await ctx.confirm({ ...change, stats, ops }) : true;
  if (!ok) {
    step.status = 'rejected';
    step.note = 'отклонено';
    return { ok: false, output: `Пользователь отклонил изменение ${change.path}. Файл не тронут. Спроси, что поправить.`, step };
  }
  if (change.after === null) await W.removePath(change.path);
  else await W.writeText(change.path, change.after);
  const verb = change.kind === 'create' ? 'Создан' : change.kind === 'delete' ? 'Удалён' : 'Изменён';
  const entry = W.recordChange(`${verb} ${change.path}`, [{ path: change.path, before: change.before, after: change.after }]);
  step.changeId = entry.id;
  const lines = lineCount(change.after ?? '');
  return {
    ok: true,
    output: change.kind === 'delete' ? `Файл ${change.path} удалён.` : `${verb} файл ${change.path} (${lines} стр., +${stats.add} −${stats.del}).`,
    step,
  };
}

export function resultBlock(call, res) {
  const path = call.attrs.path ? ` path="${call.attrs.path}"` : '';
  return `<tool_result name="${call.name}"${path} ok="${res.ok}">\n${res.output}\n</tool_result>`;
}
