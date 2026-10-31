import { state, saveSettings, saveChats, MODES, THEMES, FONTS, exportAll, importAll, wipeAll } from './store.js';
import { applyAppearance, loadFont } from './appearance.js';
import { el, toast } from './ui.js';

const TABS = [
  ['look', 'Вид'],
  ['prompts', 'Промты'],
  ['models', 'Модели'],
  ['agent', 'Агент'],
  ['access', 'Доступ'],
  ['data', 'Данные'],
];

let ctx = null;
let current = 'look';

export function openSettings(context, tab) {
  ctx = context;
  current = tab || current;
  const dlg = document.getElementById('settingsDialog');
  render();
  if (!dlg.open) dlg.showModal();
}

function render() {
  const tabs = document.getElementById('settingsTabs');
  tabs.replaceChildren(
    ...TABS.map(([id, label]) =>
      el('button', { class: 'tab', role: 'tab', type: 'button', 'aria-selected': String(id === current), onclick: () => { current = id; render(); } }, label)
    )
  );
  const body = document.getElementById('settingsBody');
  body.replaceChildren(({ look, prompts, models, agent, access, data })[current](body));
  body.scrollTop = 0;
}

function save() {
  saveSettings();
}

function field(label, control, help) {
  return el('div', { class: 'field' }, el('span', { class: 'lbl' }, label), control, help ? el('p', { class: 'help' }, help) : null);
}

function toggle(label, help, key) {
  const input = el('input', { type: 'checkbox', 'aria-label': label });
  input.checked = state.settings[key];
  input.addEventListener('change', () => {
    state.settings[key] = input.checked;
    save();
    ctx.refresh();
  });
  return el('label', { class: 'switch' }, el('span', {}, el('span', { class: 'lbl' }, label), help ? el('p', { class: 'help' }, help) : null), input);
}

/* ---------------- Вид ---------------- */
function look() {
  const s = state.settings;
  const wrap = el('div');

  const themeBtns = THEMES.map((t) =>
    el(
      'button',
      {
        class: 'swatch', type: 'button', 'aria-pressed': String(s.theme === t.id),
        onclick: () => { s.theme = t.id; save(); applyAppearance(); render(); },
      },
      el('i', {}, ...t.swatch.map((c) => el('b', { style: `background:${c}` }))),
      t.label
    )
  );
  wrap.append(field('Тема', el('div', { class: 'swatches' }, themeBtns)));

  FONTS.forEach(loadFont);
  const fontBtns = FONTS.map((f) =>
    el(
      'button',
      {
        class: 'font-opt', type: 'button', style: `font-family:${f.stack}`, 'aria-pressed': String(s.font === f.id),
        onclick: () => { s.font = f.id; save(); applyAppearance(); render(); },
      },
      f.label,
      el('small', {}, 'Съешь ещё этих мягких булок')
    )
  );
  wrap.append(field('Шрифт', el('div', { class: 'font-grid' }, fontBtns)));

  const size = el('input', { type: 'range', min: '13', max: '19', step: '1', value: String(s.fontSize), 'aria-label': 'Размер текста' });
  const sizeOut = el('span', { class: 'help' }, `${s.fontSize} px`);
  size.addEventListener('input', () => {
    s.fontSize = Number(size.value);
    sizeOut.textContent = `${s.fontSize} px`;
    save();
    applyAppearance();
  });
  wrap.append(field('Размер текста', el('div', { class: 'row' }, size, sizeOut)));

  const modeBtn = el('button', { class: 'pill', type: 'button', 'aria-pressed': String(s.accentMode === 'mode'), onclick: () => { s.accentMode = 'mode'; save(); applyAppearance(); render(); } }, 'По режиму');
  const customBtn = el('button', { class: 'pill', type: 'button', 'aria-pressed': String(s.accentMode === 'custom'), onclick: () => { s.accentMode = 'custom'; save(); applyAppearance(); render(); } }, 'Один свой цвет');
  const color = el('input', { type: 'color', value: s.accentColor, 'aria-label': 'Цвет акцента' });
  color.addEventListener('input', () => {
    s.accentColor = color.value;
    s.accentMode = 'custom';
    save();
    applyAppearance();
  });
  color.addEventListener('change', render);
  wrap.append(
    field(
      'Акцент',
      el('div', { class: 'row color-row' }, modeBtn, customBtn, s.accentMode === 'custom' ? color : null),
      'По режиму: Chat розовый, Code янтарный, Work бирюзовый.'
    )
  );

  wrap.append(
    el(
      'div',
      { class: 'preview' },
      el('p', {}, 'Так будет выглядеть текст ответа. Размер и шрифт применяются сразу.')
    )
  );
  wrap.append(el('div', { style: 'height:18px' }));
  wrap.append(toggle('Enter отправляет сообщение', 'Иначе Enter переносит строку, а отправка по Ctrl+Enter. На телефоне Enter всегда переносит строку.', 'enterToSend'));
  return wrap;
}

/* ---------------- Промты ---------------- */
function prompts() {
  const s = state.settings;
  const wrap = el('div');

  const globalArea = el('textarea', { rows: '5', placeholder: 'Например: отвечай коротко, обращайся на «ты», код пиши на TypeScript.' });
  globalArea.value = s.globalPrompt;
  globalArea.addEventListener('input', () => { s.globalPrompt = globalArea.value; save(); });
  wrap.append(field('Мои инструкции для всех режимов', globalArea, 'Добавляются к промту любого режима.'));

  for (const m of Object.values(MODES)) {
    const area = el('textarea', { rows: '5', placeholder: m.prompt });
    area.value = s.prompts[m.id];
    area.addEventListener('input', () => { s.prompts[m.id] = area.value; save(); });
    const reset = el('button', { class: 'link-btn', type: 'button', onclick: () => { s.prompts[m.id] = ''; save(); render(); toast(`Промт ${m.label} сброшен`); } }, 'Сбросить');
    wrap.append(
      el(
        'div',
        { class: 'field' },
        el('div', { class: 'row between' }, el('span', { class: 'lbl' }, `Промт режима ${m.label}`), reset),
        area,
        el('p', { class: 'help' }, s.prompts[m.id].trim() ? 'Используется твой промт вместо стандартного.' : 'Пусто: работает стандартный промт (виден в подсказке).')
      )
    );
  }
  return wrap;
}

/* ---------------- Модели ---------------- */
function models() {
  const s = state.settings;
  const wrap = el('div');

  wrap.append(toggle('Переключаться при сбое', 'Если бесплатная модель упёрлась в лимит или молчит, Пульт сам попробует следующую подходящую.', 'autoSwitch'));

  const temp = el('input', { type: 'range', min: '0', max: '1.5', step: '0.1', value: String(s.temperature), 'aria-label': 'Температура' });
  const out = el('span', { class: 'help' }, String(s.temperature));
  temp.addEventListener('input', () => { s.temperature = Number(temp.value); out.textContent = String(s.temperature); save(); });
  wrap.append(field('Творчество (temperature)', el('div', { class: 'row' }, temp, out), 'Ниже — точнее и суше, выше — свободнее.'));

  for (const m of Object.values(MODES)) {
    const sel = el('select', { 'aria-label': `Модель для ${m.label}` }, el('option', { value: '' }, 'Авто: подбор под режим'));
    for (const mod of ctx.models()) sel.append(el('option', { value: mod.id }, mod.name));
    sel.value = s.models[m.id];
    if (sel.value !== s.models[m.id]) sel.value = '';
    sel.addEventListener('change', () => { s.models[m.id] = sel.value; save(); ctx.refresh(); });
    wrap.append(field(`Модель по умолчанию: ${m.label}`, sel));
  }
  wrap.append(el('p', { class: 'help' }, 'Список бесплатных моделей берётся у OpenRouter и обновляется сам.'));
  return wrap;
}

/* ---------------- Агент ---------------- */
function agent() {
  const a = state.settings.agent;
  const wrap = el('div');
  const sw = (label, help, key) => {
    const input = el('input', { type: 'checkbox', 'aria-label': label });
    input.checked = a[key];
    input.addEventListener('change', () => { a[key] = input.checked; save(); ctx.refresh(); });
    return el('label', { class: 'switch' }, el('span', {}, el('span', { class: 'lbl' }, label), el('p', { class: 'help' }, help)), input);
  };
  wrap.append(sw('Агент в режиме Code', 'Модель сама читает, создаёт и правит файлы проекта, запускает код и проверяет превью. Выключишь, и Code станет обычным чатом.', 'on'));
  wrap.append(sw('Читать правила проекта', 'Если в проекте есть AGENTS.md, CLAUDE.md или .pultrules, их текст добавляется в инструкции агента.', 'rules'));
  wrap.append(sw('Режим плана', 'Агент сначала предлагает план и ничего не меняет, пока ты не ответишь.', 'plan'));

  const sel = el('select', { 'aria-label': 'Подтверждение правок' },
    el('option', { value: 'smart' }, 'Умно: спрашивать только при записи в папку на компьютере'),
    el('option', { value: 'ask' }, 'Всегда спрашивать перед правкой'),
    el('option', { value: 'auto' }, 'Не спрашивать, всё можно откатить в «Правках»'));
  sel.value = a.confirm;
  sel.addEventListener('change', () => { a.confirm = sel.value; save(); });
  wrap.append(field('Подтверждение правок', sel, 'В песочнице браузера ничего не страшно, поэтому умный режим применяет правки сразу. Настоящие файлы он защищает вопросом с диффом.'));

  const steps = el('input', { type: 'range', min: '4', max: '30', step: '1', value: String(a.steps), 'aria-label': 'Максимум шагов' });
  const out = el('span', { class: 'help' }, String(a.steps));
  steps.addEventListener('input', () => { a.steps = Number(steps.value); out.textContent = String(a.steps); save(); });
  wrap.append(field('Максимум шагов за запрос', el('div', { class: 'row' }, steps, out), 'Шаг — одна реплика модели с вызовами инструментов. Больше шагов, больше расход бесплатного лимита.'));
  wrap.append(el('p', { class: 'help' }, 'Ключи и токены агент не видит: файлы .env и подобные для него закрыты. Код запускается в изолированной песочнице без доступа к настройкам Пульта.'));
  return wrap;
}

/* ---------------- Доступ ---------------- */
function access() {
  const s = state.settings;
  const wrap = el('div');

  const or = el('input', { class: 'input', type: 'password', autocomplete: 'off', spellcheck: 'false', placeholder: 'sk-or-…' });
  or.value = s.keys.openrouter;
  or.addEventListener('input', () => { s.keys.openrouter = or.value.trim(); save(); ctx.refresh(); });
  wrap.append(
    field(
      'Свой ключ OpenRouter',
      or,
      el('span', {}, 'Бесплатно создаётся на ', el('a', { href: 'https://openrouter.ai/keys', target: '_blank', rel: 'noopener noreferrer' }, 'openrouter.ai/keys'), '. Хранится только в этом браузере и уходит на твой сервер при каждом запросе. С собственным ключом открыты и платные модели.')
    )
  );

  const code = el('input', { class: 'input', type: 'password', autocomplete: 'off', placeholder: 'Если на сайте включён ACCESS_CODE' });
  code.value = s.keys.access;
  code.addEventListener('input', () => { s.keys.access = code.value.trim(); save(); });
  wrap.append(field('Код доступа к сайту', code, 'Нужен, только если владелец сайта защитил его кодом.'));
  return wrap;
}

/* ---------------- Данные ---------------- */
function data() {
  const wrap = el('div');
  const fileIn = el('input', { type: 'file', accept: 'application/json', hidden: true });
  fileIn.addEventListener('change', async () => {
    const f = fileIn.files[0];
    if (!f) return;
    try {
      importAll(await f.text());
      applyAppearance();
      ctx.refresh(true);
      render();
      toast('Импорт готов');
    } catch (e) {
      toast(e.message || 'Не получилось прочитать файл');
    }
    fileIn.value = '';
  });

  wrap.append(
    field(
      'Резервная копия',
      el(
        'div',
        { class: 'row' },
        el('button', { class: 'btn', type: 'button', onclick: () => {
          const blob = new Blob([exportAll()], { type: 'application/json' });
          const a = el('a', { href: URL.createObjectURL(blob), download: `pult-${new Date().toISOString().slice(0, 10)}.json` });
          document.body.append(a);
          a.click();
          a.remove();
        } }, 'Скачать чаты и настройки'),
        el('button', { class: 'btn', type: 'button', onclick: () => fileIn.click() }, 'Загрузить из файла'),
        fileIn
      ),
      'Ключи и токены коннекторов в копию не попадают.'
    )
  );

  const wipe = el('button', { class: 'btn danger', type: 'button', onclick: () => {
    if (!confirm('Удалить все чаты, настройки, ключи и токены из этого браузера?')) return;
    wipeAll();
    location.reload();
  } }, 'Стереть всё в этом браузере');
  wrap.append(field('Очистка', wipe, 'Чаты, настройки, ключи и токены хранятся только здесь, на сервере их нет.'));

  const clearChats = el('button', { class: 'btn danger', type: 'button', onclick: () => {
    if (!confirm('Удалить все чаты? Настройки останутся.')) return;
    state.chats = [];
    state.activeId = null;
    saveChats(true);
    ctx.refresh(true);
    toast('Чаты удалены');
  } }, 'Удалить только чаты');
  wrap.append(field('', clearChats));
  return wrap;
}
