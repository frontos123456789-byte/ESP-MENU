// Построчный дифф (LCS) без зависимостей. Чистые функции, работают и в браузере, и в Node.

const MAX_CELLS = 3_000_000;

// Возвращает массив операций { t: ' ' | '+' | '-', s: строка }.
export function diffLines(before, after) {
  const a = before === '' || before == null ? [] : String(before).split('\n');
  const b = after === '' || after == null ? [] : String(after).split('\n');
  let start = 0;
  while (start < a.length && start < b.length && a[start] === b[start]) start++;
  let endA = a.length;
  let endB = b.length;
  while (endA > start && endB > start && a[endA - 1] === b[endB - 1]) {
    endA--;
    endB--;
  }
  const head = a.slice(0, start).map((s) => ({ t: ' ', s }));
  const tail = a.slice(endA).map((s) => ({ t: ' ', s }));
  const ma = a.slice(start, endA);
  const mb = b.slice(start, endB);
  return [...head, ...middle(ma, mb), ...tail];
}

function middle(a, b) {
  if (!a.length) return b.map((s) => ({ t: '+', s }));
  if (!b.length) return a.map((s) => ({ t: '-', s }));
  const n = a.length;
  const m = b.length;
  if (n * m > MAX_CELLS) return [...a.map((s) => ({ t: '-', s })), ...b.map((s) => ({ t: '+', s }))];
  // dp[i][j] = длина LCS хвостов a[i..], b[j..]
  const w = m + 1;
  const dp = new Uint32Array((n + 1) * w);
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      dp[i * w + j] = a[i] === b[j] ? dp[(i + 1) * w + j + 1] + 1 : Math.max(dp[(i + 1) * w + j], dp[i * w + j + 1]);
    }
  }
  const out = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) {
      out.push({ t: ' ', s: a[i] });
      i++;
      j++;
    } else if (dp[(i + 1) * w + j] >= dp[i * w + j + 1]) {
      out.push({ t: '-', s: a[i++] });
    } else {
      out.push({ t: '+', s: b[j++] });
    }
  }
  while (i < n) out.push({ t: '-', s: a[i++] });
  while (j < m) out.push({ t: '+', s: b[j++] });
  return out;
}

export function diffStats(ops) {
  let add = 0;
  let del = 0;
  for (const o of ops) {
    if (o.t === '+') add++;
    else if (o.t === '-') del++;
  }
  return { add, del };
}

// Сворачивает длинные неизменённые куски: оставляет ctx строк вокруг правок.
// Возвращает строки { t, s, n1, n2 } и разделители { t: '…', skipped }.
export function collapse(ops, ctx = 3) {
  const keep = new Array(ops.length).fill(false);
  ops.forEach((o, i) => {
    if (o.t === ' ') return;
    for (let k = Math.max(0, i - ctx); k <= Math.min(ops.length - 1, i + ctx); k++) keep[k] = true;
  });
  const out = [];
  let n1 = 1;
  let n2 = 1;
  let skipped = 0;
  ops.forEach((o, i) => {
    const row = { t: o.t, s: o.s, n1: o.t === '+' ? '' : n1, n2: o.t === '-' ? '' : n2 };
    if (o.t !== '+') n1++;
    if (o.t !== '-') n2++;
    if (keep[i]) {
      if (skipped) out.push({ t: '…', s: '', skipped });
      skipped = 0;
      out.push(row);
    } else skipped++;
  });
  if (skipped && out.length) out.push({ t: '…', s: '', skipped });
  return out;
}
