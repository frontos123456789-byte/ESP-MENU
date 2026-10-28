// Коннекторы: каждый — объект с render(body, ctx). Чтобы добавить новый, допиши его в список CONNECTORS.
// ctx.attach({name, body, truncated}) кладёт текст в сообщение как вложение.

import { state, saveSettings } from './store.js';
import { getJson } from './api.js';
import { el, toast, ago, debounce } from './ui.js';

let ctx = null;
let current = 'github';

export function openConnectors(context, tab) {
  ctx = context;
  if (tab) current = tab;
  const dlg = document.getElementById('connectorsDialog');
  renderShell();
  if (!dlg.open) dlg.showModal();
}

function renderShell() {
  const tabs = document.getElementById('connectorTabs');
  tabs.replaceChildren(
    ...CONNECTORS.map((c) =>
      el('button', { class: 'tab', role: 'tab', type: 'button', 'aria-selected': String(c.id === current), onclick: () => { current = c.id; renderShell(); } }, c.title)
    )
  );
  const body = document.getElementById('connectorBody');
  body.replaceChildren();
  CONNECTORS.find((c) => c.id === current).render(body);
  body.scrollTop = 0;
}

/* ---------- общие кусочки ---------- */

function tokenField({ label, help, value, placeholder, onSave, onCheck, extra }) {
  const input = el('input', { class: 'input', type: 'password', autocomplete: 'off', spellcheck: 'false', placeholder, 'aria-label': label });
  input.value = value;
  const btn = el('button', { class: 'btn primary', type: 'button' }, 'Подключить');
  btn.addEventListener('click', () => {
    onSave(input.value.trim());
    onCheck();
  });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); btn.click(); }
  });
  return el('div', { class: 'field' }, el('span', { class: 'lbl' }, label), el('div', { class: 'row' }, el('div', { style: 'flex:1;min-width:200px' }, input), btn), extra || null, el('p', { class: 'help' }, help));
}

function errorBox(err, retry) {
  const box = el('div', { class: 'err-note' }, el('p', {}, err.message || 'Не получилось'));
  if (retry) box.append(el('p', {}, el('button', { class: 'link-btn', type: 'button', onclick: retry }, 'Повторить')));
  return box;
}

function searchBox(onInput, placeholder) {
  const i = el('input', { class: 'input', type: 'search', placeholder, 'aria-label': placeholder });
  i.addEventListener('input', debounce(() => onInput(i.value.trim().toLowerCase()), 120));
  return i;
}

async function load(area, fn, retry) {
  area.replaceChildren(el('div', { class: 'loading' }, 'Загружаю…'));
  try {
    return await fn();
  } catch (e) {
    area.replaceChildren(errorBox(e, retry));
    return null;
  }
}

/* ---------- GitHub ---------- */

const github = {
  id: 'github',
  title: 'GitHub',
  render(body) {
    const cfg = state.settings.connectors.github;
    const area = el('div');
    const head = tokenField({
      label: 'Токен GitHub',
      value: cfg.token,
      placeholder: 'github_pat_… или ghp_…',
      help: 'Лучше fine-grained токен только на чтение: Contents, Metadata, Issues. Хранится в этом браузере.',
      onSave: (v) => { cfg.token = v; saveSettings(); },
      onCheck: () => repos(area),
      extra: el('p', { class: 'help' }, el('a', { href: 'https://github.com/settings/personal-access-tokens/new', target: '_blank', rel: 'noopener noreferrer', style: 'color:var(--accent)' }, 'Создать токен на GitHub')),
    });
    body.append(head, area);
    if (cfg.token) repos(area);
    else area.append(el('p', { class: 'help' }, 'Подключи токен, и здесь появятся твои репозитории. Файлы, коммиты и issues можно добавить в сообщение как контекст.'));
  },
};

const gh = (q) => getJson('/api/github?' + new URLSearchParams(q), { 'x-github-token': state.settings.connectors.github.token });

async function repos(area) {
  const j = await load(area, () => gh({ op: 'repos' }), () => repos(area));
  if (!j) return;
  const list = el('div', { class: 'pick-list' });
  const draw = (q = '') => {
    const rows = j.repos.filter((r) => r.full_name.toLowerCase().includes(q)).slice(0, 80);
    list.replaceChildren(
      ...(rows.length
        ? rows.map((r) =>
            el(
              'button',
              { class: 'pick', type: 'button', onclick: () => repoView(area, r) },
              el('span', { class: 'pick-main' }, el('b', {}, r.full_name), el('span', { class: 'tag' }, r.private ? 'приватный' : 'публичный')),
              el('small', {}, [r.language, r.description].filter(Boolean).join(' · ') || 'без описания')
            )
          )
        : [el('p', { class: 'help' }, 'Ничего не нашлось')])
    );
  };
  draw();
  area.replaceChildren(el('p', { class: 'help' }, `Токен принят. Репозиториев: ${j.repos.length}`), searchBox(draw, 'Найти репозиторий'), list);
}

function repoView(area, repo) {
  let tab = 'files';
  const panel = el('div');
  const tabs = el('div', { class: 'sub-tabs' });
  const draw = () => {
    tabs.replaceChildren(
      ...[['files', 'Файлы'], ['commits', 'Коммиты'], ['issues', 'Issues']].map(([id, label]) =>
        el('button', { class: 'pill', type: 'button', 'aria-pressed': String(tab === id), onclick: () => { tab = id; draw(); } }, label)
      )
    );
    ({ files: ghFiles, commits: ghCommits, issues: ghIssues })[tab](panel, repo);
  };
  area.replaceChildren(
    el('div', { class: 'crumb' }, el('button', { class: 'link-btn', type: 'button', onclick: () => repos(area) }, '← Репозитории'), el('b', {}, repo.full_name)),
    tabs,
    panel
  );
  draw();
}

async function ghFiles(panel, repo) {
  const j = await load(panel, () => gh({ op: 'tree', repo: repo.full_name }), () => ghFiles(panel, repo));
  if (!j) return;
  const list = el('div', { class: 'pick-list' });
  const draw = (q = '') => {
    const rows = j.files.filter((f) => f.path.toLowerCase().includes(q)).slice(0, 60);
    list.replaceChildren(
      ...(rows.length
        ? rows.map((f) =>
            el(
              'button',
              { class: 'pick', type: 'button', onclick: async (e) => {
                const b = e.currentTarget;
                b.disabled = true;
                try {
                  const file = await gh({ op: 'file', repo: repo.full_name, path: f.path, ref: j.ref });
                  ctx.attach({ name: `${repo.full_name}/${f.path}`, body: file.content, truncated: file.truncated });
                } catch (err) {
                  toast(err.message);
                }
                b.disabled = false;
              } },
              el('span', { class: 'pick-main' }, el('b', {}, f.path.split('/').pop()), el('span', { class: 'tag' }, `${Math.max(1, Math.round(f.size / 1024))} КБ`)),
              el('small', {}, f.path)
            )
          )
        : [el('p', { class: 'help' }, 'Ничего не нашлось')])
    );
  };
  draw();
  panel.replaceChildren(
    el('p', { class: 'help' }, `Ветка ${j.ref}, файлов: ${j.files.length}${j.truncated ? ' (список обрезан GitHub)' : ''}. Нажми на файл, чтобы добавить его в сообщение.`),
    searchBox(draw, 'Поиск по пути, например src/api'),
    list
  );
}

async function ghCommits(panel, repo) {
  const j = await load(panel, () => gh({ op: 'commits', repo: repo.full_name }), () => ghCommits(panel, repo));
  if (!j) return;
  const text = j.commits.map((c) => `${c.sha} ${c.message} (${c.author}, ${c.date.slice(0, 10)})`).join('\n');
  panel.replaceChildren(
    el('div', { class: 'row between' }, el('p', { class: 'help' }, `Последние коммиты: ${j.commits.length}`), el('button', { class: 'btn primary', type: 'button', onclick: () => ctx.attach({ name: `${repo.full_name}: коммиты`, body: text }) }, 'Добавить в сообщение')),
    el('div', { class: 'pick-list' }, ...j.commits.map((c) => el('div', { class: 'pick' }, el('span', { class: 'pick-main' }, el('b', {}, c.message), el('span', { class: 'tag' }, c.sha)), el('small', {}, `${c.author} · ${ago(c.date)}`))))
  );
}

async function ghIssues(panel, repo) {
  const j = await load(panel, () => gh({ op: 'issues', repo: repo.full_name }), () => ghIssues(panel, repo));
  if (!j) return;
  if (!j.issues.length) return panel.replaceChildren(el('p', { class: 'help' }, 'Открытых issues нет.'));
  const asText = (i) => `#${i.number} ${i.pr ? '[PR] ' : ''}${i.title} (${i.author})\n${i.body}`.trim();
  panel.replaceChildren(
    el('div', { class: 'row between' }, el('p', { class: 'help' }, 'Нажми на строку, чтобы добавить один, или добавь все.'), el('button', { class: 'btn', type: 'button', onclick: () => ctx.attach({ name: `${repo.full_name}: issues`, body: j.issues.map(asText).join('\n\n') }) }, 'Добавить все')),
    el('div', { class: 'pick-list' }, ...j.issues.map((i) =>
      el('button', { class: 'pick', type: 'button', onclick: () => ctx.attach({ name: `${repo.full_name}#${i.number}`, body: asText(i) }) },
        el('span', { class: 'pick-main' }, el('b', {}, i.title), el('span', { class: 'tag' }, `${i.pr ? 'PR' : 'issue'} #${i.number}`)),
        el('small', {}, i.author))
    ))
  );
}

/* ---------- Vercel ---------- */

const vercel = {
  id: 'vercel',
  title: 'Vercel',
  render(body) {
    const cfg = state.settings.connectors.vercel;
    const area = el('div');
    const team = el('input', { class: 'input', type: 'text', placeholder: 'team_… (только если проекты лежат в команде)', value: cfg.team, 'aria-label': 'Team ID' });
    team.addEventListener('input', () => { cfg.team = team.value.trim(); saveSettings(); });
    const head = tokenField({
      label: 'Токен Vercel',
      value: cfg.token,
      placeholder: 'Токен из настроек аккаунта',
      help: 'Токен нужен только на чтение логов и списков. Хранится в этом браузере.',
      onSave: (v) => { cfg.token = v; saveSettings(); },
      onCheck: () => projects(area),
      extra: el('div', { class: 'field', style: 'margin:0' }, el('span', { class: 'lbl' }, 'Team ID (необязательно)'), team),
    });
    body.append(head, area);
    if (cfg.token) projects(area);
    else area.append(el('p', { class: 'help' }, 'Создай токен на vercel.com/account/tokens, вставь сюда, и появятся проекты и деплои. Лог упавшей сборки можно отправить в Code одним нажатием.'));
  },
};

const vc = (q) => {
  const c = state.settings.connectors.vercel;
  const h = { 'x-vercel-token': c.token };
  if (c.team) h['x-vercel-team'] = c.team;
  return getJson('/api/vercel?' + new URLSearchParams(q), h);
};

async function projects(area) {
  const j = await load(area, () => vc({ op: 'projects' }), () => projects(area));
  if (!j) return;
  const list = el('div', { class: 'pick-list' });
  const draw = (q = '') => {
    const rows = j.projects.filter((p) => p.name.toLowerCase().includes(q));
    list.replaceChildren(
      ...(rows.length
        ? rows.map((p) =>
            el('button', { class: 'pick', type: 'button', onclick: () => deployments(area, p) },
              el('span', { class: 'pick-main' }, el('b', {}, p.name), el('span', { class: 'tag' }, p.framework || 'проект')),
              el('small', {}, [p.repo, p.updatedAt ? `обновлён ${ago(p.updatedAt)}` : ''].filter(Boolean).join(' · ')))
          )
        : [el('p', { class: 'help' }, 'Проектов не найдено. Если они в команде, впиши Team ID.')])
    );
  };
  draw();
  area.replaceChildren(el('p', { class: 'help' }, `Токен принят. Проектов: ${j.projects.length}`), searchBox(draw, 'Найти проект'), list);
}

async function deployments(area, project) {
  const back = el('div', { class: 'crumb' }, el('button', { class: 'link-btn', type: 'button', onclick: () => projects(area) }, '← Проекты'), el('b', {}, project.name));
  const j = await load(area, () => vc({ op: 'deployments', project: project.id }), () => deployments(area, project));
  if (!j) return area.prepend(back);
  const cls = (s) => (s === 'READY' ? 'ready' : s === 'ERROR' || s === 'CANCELED' ? 'error' : 'building');
  const summary = j.deployments
    .map((d) => `${d.state} · ${d.target} · ${d.branch || '—'} · ${d.message || 'без сообщения'} · ${d.url} · ${ago(d.createdAt)}`)
    .join('\n');
  area.replaceChildren(
    back,
    el('div', { class: 'row between' }, el('p', { class: 'help' }, 'Последние деплои'), el('button', { class: 'btn', type: 'button', onclick: () => ctx.attach({ name: `${project.name}: деплои`, body: summary }) }, 'Добавить сводку')),
    el('div', { class: 'pick-list' }, ...j.deployments.map((d) =>
      el('button', { class: 'pick', type: 'button', onclick: async (e) => {
        const b = e.currentTarget;
        b.disabled = true;
        try {
          const l = await vc({ op: 'logs', deployment: d.id });
          if (!l.log.trim()) toast('У этого деплоя нет текста лога');
          else ctx.attach({ name: `${project.name}: лог ${d.state} ${d.id.slice(-6)}`, body: l.log, truncated: l.truncated });
        } catch (err) {
          toast(err.message);
        }
        b.disabled = false;
      } },
        el('span', { class: 'pick-main' }, el('b', {}, el('span', { class: `state ${cls(d.state)}` }), d.message || d.url), el('span', { class: 'tag' }, d.state || '?')),
        el('small', {}, `${d.target} · ${d.branch || '—'} · ${ago(d.createdAt)} · нажми, чтобы добавить лог`))
    ))
  );
}

const CONNECTORS = [github, vercel];
