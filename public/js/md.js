// Маленький безопасный рендер markdown: без зависимостей, всё экранируется.
// Недозакрытый блок кода (пока идёт стрим) показывается как код.

export function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function inline(text) {
  const codes = [];
  let t = text.replace(/`([^`\n]+)`/g, (_, c) => {
    codes.push(c);
    return `\u0000${codes.length - 1}\u0000`;
  });
  t = escapeHtml(t);
  t = t
    .replace(/\*\*([^*\n]+?)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|[\s(])\*([^*\s][^*\n]*?)\*(?=[\s).,!?:;]|$)/g, '$1<em>$2</em>')
    .replace(/~~([^~\n]+?)~~/g, '<del>$1</del>')
    .replace(/\[([^\]\n]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');
  return t.replace(/\u0000(\d+)\u0000/g, (_, i) => `<code>${escapeHtml(codes[i])}</code>`);
}

function codeBlock(code, lang) {
  const label = escapeHtml(lang || 'текст');
  return (
    `<div class="code"><div class="code-head"><span>${label}</span>` +
    `<button type="button" class="code-copy" data-copy>Копировать</button></div>` +
    `<pre><code>${escapeHtml(code)}</code></pre></div>`
  );
}

const FENCE = /^\s*```\s*([^\s`]*)[^`]*$/;
const FENCE_END = /^\s*```\s*$/;
const HEADING = /^(#{1,6})\s+(.*)$/;
const HR = /^\s*([-*_])(\s*\1){2,}\s*$/;
const LIST = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/;
const TABLE_SEP = /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/;

function isBlockStart(line, next) {
  return (
    FENCE.test(line) ||
    HEADING.test(line) ||
    HR.test(line) ||
    LIST.test(line) ||
    /^\s*>/.test(line) ||
    (line.includes('|') && next !== undefined && TABLE_SEP.test(next) && next.includes('-'))
  );
}

function splitRow(line) {
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);
  return s.split('|').map((c) => c.trim());
}

function renderList(items) {
  let out = '';
  const stack = [];
  for (const it of items) {
    const tag = it.ordered ? 'ol' : 'ul';
    while (stack.length && it.indent < stack[stack.length - 1].indent) out += `</li></${stack.pop().tag}>`;
    if (!stack.length || it.indent > stack[stack.length - 1].indent) {
      out += `<${tag}><li>${inline(it.text)}`;
      stack.push({ indent: it.indent, tag });
    } else {
      out += `</li><li>${inline(it.text)}`;
    }
  }
  while (stack.length) out += `</li></${stack.pop().tag}>`;
  return out;
}

export function renderMarkdown(src) {
  const lines = String(src).replace(/\r\n?/g, '\n').replace(/\u0000/g, '').split('\n');
  let html = '';
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    let m;

    if (!line.trim()) {
      i++;
      continue;
    }

    if ((m = line.match(FENCE))) {
      const buf = [];
      i++;
      while (i < lines.length && !FENCE_END.test(lines[i])) buf.push(lines[i++]);
      i++;
      html += codeBlock(buf.join('\n'), m[1]);
      continue;
    }

    if ((m = line.match(HEADING))) {
      const level = Math.min(m[1].length + 1, 6);
      html += `<h${level}>${inline(m[2].replace(/\s+#+\s*$/, ''))}</h${level}>`;
      i++;
      continue;
    }

    if (HR.test(line)) {
      html += '<hr>';
      i++;
      continue;
    }

    if (/^\s*>/.test(line)) {
      const buf = [];
      while (i < lines.length && /^\s*>/.test(lines[i])) buf.push(lines[i++].replace(/^\s*>\s?/, ''));
      html += `<blockquote>${renderMarkdown(buf.join('\n'))}</blockquote>`;
      continue;
    }

    if (line.includes('|') && lines[i + 1] !== undefined && TABLE_SEP.test(lines[i + 1]) && lines[i + 1].includes('-')) {
      const head = splitRow(line);
      i += 2;
      const rows = [];
      while (i < lines.length && lines[i].includes('|') && lines[i].trim()) rows.push(splitRow(lines[i++]));
      html +=
        '<div class="table-wrap"><table><thead><tr>' +
        head.map((c) => `<th>${inline(c)}</th>`).join('') +
        '</tr></thead><tbody>' +
        rows.map((r) => '<tr>' + r.map((c) => `<td>${inline(c)}</td>`).join('') + '</tr>').join('') +
        '</tbody></table></div>';
      continue;
    }

    if ((m = line.match(LIST))) {
      const items = [];
      while (i < lines.length) {
        const lm = lines[i].match(LIST);
        if (lm) {
          items.push({ indent: lm[1].replace(/\t/g, '  ').length, ordered: /\d/.test(lm[2]), text: lm[3] });
          i++;
        } else if (/^\s{2,}\S/.test(lines[i]) && items.length && !isBlockStart(lines[i])) {
          items[items.length - 1].text += ' ' + lines[i].trim();
          i++;
        } else if (!lines[i].trim() && LIST.test(lines[i + 1] || '')) {
          i++;
        } else break;
      }
      html += renderList(items);
      continue;
    }

    const buf = [];
    while (i < lines.length && lines[i].trim() && !(buf.length && isBlockStart(lines[i], lines[i + 1]))) buf.push(lines[i++]);
    html += `<p>${buf.map(inline).join('<br>')}</p>`;
  }
  return html;
}

// Для заголовка чата: убираем разметку и берём первую содержательную строку.
export function titleFrom(text) {
  const t = String(text).replace(/```[\s\S]*?(```|$)/g, ' ').replace(/[#>*_`~[\]()]/g, '').replace(/\s+/g, ' ').trim();
  if (!t) return 'Новый чат';
  return t.length > 48 ? t.slice(0, 46).trimEnd() + '…' : t;
}
