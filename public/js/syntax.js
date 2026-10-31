// Лёгкая подсветка синтаксиса без зависимостей. Один проход регуляркой на язык.
// Классы: tk-c комментарий, tk-s строка, tk-n число, tk-k ключевое слово, tk-f функция, tk-t тип/тег, tk-a атрибут.

const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;' };
const esc = (s) => s.replace(/[&<>]/g, (c) => ESC[c]);
const span = (cls, s) => `<span class="tk-${cls}">${esc(s)}</span>`;

const set = (s) => new Set(s.split(' '));

const JS_KW = set(
  'const let var function return if else for while do switch case break continue new class extends import from export default async await try catch finally throw typeof instanceof in of this super null undefined true false void yield delete static get set interface type enum implements public private protected readonly as namespace declare abstract'
);
const PY_KW = set(
  'def class return if elif else for while in not and or is import from as with try except finally raise pass break continue lambda None True False yield global nonlocal assert del async await self'
);
const SH_KW = set('if then else elif fi for while do done case esac function in return exit echo cd export local source alias unset set');
const GENERIC_KW = set('true false null none if else for while return function class import export const let var def end do then');

const RE = {
  js: /(\/\/[^\n]*|\/\*[\s\S]*?(?:\*\/|$))|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\[\s\S]|[^`\\])*(?:`|$))|(\b0x[\da-fA-F]+\b|\b\d[\d_]*(?:\.\d+)?(?:e[+-]?\d+)?\b)|([A-Za-z_$][\w$]*)/g,
  py: /(#[^\n]*)|("""[\s\S]*?(?:"""|$)|'''[\s\S]*?(?:'''|$)|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')|(\b\d[\d_]*(?:\.\d+)?\b)|([A-Za-z_][\w]*)/g,
  sh: /(#[^\n]*)|("(?:\\.|[^"\\])*"|'[^']*')|(\b\d+\b)|(\$\{?[A-Za-z_][\w]*\}?|[A-Za-z_][\w-]*)/g,
  generic: /(#[^\n]*|\/\/[^\n]*)|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')|(\b\d[\d_.]*\b)|([A-Za-z_][\w]*)/g,
  css: /(\/\*[\s\S]*?(?:\*\/|$))|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')|(#[\da-fA-F]{3,8}\b|\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|s|ms|deg|fr)?\b)|(@[\w-]+|--[\w-]+|[A-Za-z-]+(?=\s*:(?!:)))/g,
  html: /(<!--[\s\S]*?(?:-->|$))|(<\/?[A-Za-z][\w:-]*)|((?<==\s*)"[^"\n]*"|(?<==\s*)'[^'\n]*')|([\w:@.-]+(?=\s*=))|(\/?>)/g,
  json: /()("(?:\\.|[^"\\\n])*"(?=\s*:))|("(?:\\.|[^"\\\n])*")|(-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)|(true|false|null)/g,
};

const ALIAS = {
  js: 'js', javascript: 'js', mjs: 'js', cjs: 'js', jsx: 'js', ts: 'js', typescript: 'js', tsx: 'js', node: 'js',
  json: 'json', jsonc: 'json',
  html: 'html', htm: 'html', xml: 'html', svg: 'html', vue: 'html',
  css: 'css', scss: 'css', less: 'css',
  py: 'py', python: 'py',
  sh: 'sh', bash: 'sh', zsh: 'sh', shell: 'sh', console: 'sh',
  yaml: 'generic', yml: 'generic', toml: 'generic', ini: 'generic', env: 'generic',
};

export function langOf(nameOrLang) {
  const s = String(nameOrLang || '').toLowerCase();
  const ext = s.includes('.') ? s.split('.').pop() : s;
  return ALIAS[ext] || '';
}

function wordClass(kind, w, next) {
  const kw = kind === 'py' ? PY_KW : kind === 'sh' ? SH_KW : kind === 'generic' ? GENERIC_KW : JS_KW;
  if (kw.has(w)) return 'k';
  if (kind === 'sh' && w.startsWith('$')) return 'a';
  if (next === '(') return 'f';
  if (/^[A-Z]/.test(w) && kind !== 'sh' && w.length > 1) return 't';
  return '';
}

export function highlight(code, lang) {
  const kind = langOf(lang);
  if (!kind || code.length > 80000) return esc(code);
  const re = RE[kind];
  re.lastIndex = 0;
  let out = '';
  let last = 0;
  let m;
  while ((m = re.exec(code))) {
    if (m[0] === '') {
      re.lastIndex++;
      continue;
    }
    out += esc(code.slice(last, m.index));
    last = m.index + m[0].length;
    const text = m[0];
    if (kind === 'html') {
      if (m[1]) out += span('c', text);
      else if (m[2]) out += span('t', text);
      else if (m[3]) out += span('s', text);
      else if (m[4]) out += span('a', text);
      else out += span('t', text);
    } else if (kind === 'css') {
      if (m[1]) out += span('c', text);
      else if (m[2]) out += span('s', text);
      else if (m[3]) out += span('n', text);
      else out += span(text.startsWith('@') ? 'k' : 'a', text);
    } else if (kind === 'json') {
      if (m[2]) out += span('a', text);
      else if (m[3]) out += span('s', text);
      else if (m[4]) out += span('n', text);
      else out += span('k', text);
    } else if (m[1]) out += span('c', text);
    else if (m[2]) out += span('s', text);
    else if (m[3]) out += span('n', text);
    else {
      const cls = wordClass(kind, text, code[last]);
      out += cls ? span(cls, text) : esc(text);
    }
  }
  return out + esc(code.slice(last));
}
