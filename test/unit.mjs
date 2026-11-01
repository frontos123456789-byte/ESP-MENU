// Юнит-проверки чистой логики: подсветка, дифф, ZIP, агентный протокол и проект. Запуск: node --no-warnings test/unit.mjs
import { highlight, langOf } from '../public/js/syntax.js';
import { diffLines, diffStats, collapse } from '../public/js/diff.js';
import { makeZip } from '../public/js/zip.js';
import * as A from '../public/js/agent.js';
import * as W from '../public/js/workspace.js';
let fails = 0;
const ok = (n, c, x) => { console.log((c ? 'ok   ' : 'FAIL ') + n + (c ? '' : ' ' + JSON.stringify(x))); if (!c) fails++; };

ok('подсветка js: ключевое слово, функция, строка, комментарий', /tk-k">const.*tk-f">foo.*tk-s">"x&lt;y&gt;".*tk-c">\/\/ hi/s.test(highlight('const a = foo("x<y>"); // hi', 'js')));
ok('подсветка экранирует html', !highlight('<script>alert(1)</script>', 'html').includes('<script>'));
ok('язык по имени файла', langOf('src/App.tsx') === 'js' && langOf('x.md') === '');
const ops = diffLines('l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10', 'l1\nl2\nX\nl4\nl5\nl6\nl7\nl8\nl9\nl10\nl11');
ok('дифф считает +2 −1', JSON.stringify(diffStats(ops)) === '{"add":2,"del":1}');
ok('дифф сворачивает длинный неизменённый кусок', collapse(ops, 1).some((r) => r.t === '…'));
ok('дифф пустого файла', diffStats(diffLines('', 'a\nb')).add === 2 && diffStats(diffLines('a\nb', '')).del === 2);
const zip = makeZip([{ path: 'a.txt', data: 'hello' }]);
ok('zip: сигнатура и размер', zip[0] === 0x50 && zip[1] === 0x4b && zip.length > 40);
const txt=`Сделаю.\n<tool name="write_file" path="index.html">\n\`\`\`html\n<h1>Hi</h1>\n\`\`\`\n</tool>\n<tool name="read_file" path="a.js" from="2" to="3"/>\n<tool name='edit_file' path='a.js'><old>\nfoo\n</old><new>\nbar\n</new></tool>\nИ ещё <tool_result>выдумка</tool_result> хвост`;
const p=A.parseCalls(txt);
ok('3 вызова', p.calls.length===3, p.calls.map(c=>c.name));
ok('атрибуты', p.calls[1].attrs.from==='2'&&p.calls[2].attrs.path==='a.js');
ok('нет обрезки', p.truncated===null);
ok('strip', A.stripCalls(txt)==='Сделаю.\n\nИ ещё', A.stripCalls(txt));
ok('live пусто когда закрыт', A.liveTool(txt)===null);
const part='Пишу\n<tool name="write_file" path="x/y.js">\nconst a=';
ok('live открыт', A.liveTool(part)?.path==='x/y.js'&&A.liveTool(part).chars>10, A.liveTool(part));
ok('оборван', A.parseCalls(part).truncated?.name==='write_file');
ok('strip оборван', A.stripCalls(part)==='Пишу');
ok('applyEdit точно', A.applyEdit('a\nfoo\nb','foo','bar').text==='a\nbar\nb');
ok('applyEdit дубль', !!A.applyEdit('foo foo','foo','x').error);
ok('applyEdit пробелы', A.applyEdit('a  \n  foo  \nb','  foo','  bar').text!==undefined);
ok('applyEdit нет', !!A.applyEdit('abc','zzz','x').error);
const comp=A.compactAssistant('x <tool name="write_file" path="a">\n1\n2\n3\n</tool> y');
ok('compact', comp.includes('[содержимое: 5 стр.') , comp);
await W.initWorkspace();
const ctx={confirm:async()=>true,runJs:async()=>({logs:[{level:'log',text:'4'}],timedOut:false}),preview:async()=>({logs:[]})};
let r=await A.execTool({name:'write_file',attrs:{path:'index.html'},body:'\n```html\n<h1>Hi</h1>\n```\n'},ctx);
ok('write ok', r.ok&&r.step.add===1&&W.exists('index.html'), r);
ok('содержимое без забора', (await W.readText('index.html'))==='<h1>Hi</h1>', await W.readText('index.html'));
r=await A.execTool({name:'edit_file',attrs:{path:'index.html'},body:'<old>\n<h1>Hi</h1>\n</old><new>\n<h1>Привет</h1>\n<p>x</p>\n</new>'},ctx);
ok('edit ok', r.ok&&r.step.add===2&&r.step.del===1, r);
r=await A.execTool({name:'edit_file',attrs:{path:'index.html'},body:'<old>нет такого</old><new>x</new>'},ctx);
ok('edit fail', !r.ok&&r.output.includes('Файл не изменён'), r);
r=await A.execTool({name:'read_file',attrs:{path:'../etc/passwd'},body:''},ctx); ok('path traversal', !r.ok, r.output);
r=await A.execTool({name:'read_file',attrs:{path:'.env'},body:''},ctx); ok('секрет', !r.ok, r.output);
r=await A.execTool({name:'write_file',attrs:{path:'.env'},body:'K=1'},ctx); ok('секрет write', !r.ok, r.output);
r=await A.execTool({name:'search',attrs:{query:'привет'},body:''},ctx); ok('search', r.output.startsWith('index.html:1:'), r.output);
r=await A.execTool({name:'list_files',attrs:{},body:''},ctx); ok('list', r.output.includes('index.html'), r.output);
const e=W.ws.history[0]; ok('история', W.ws.history.length===2);
await W.undoEntry(W.ws.history[0].id); ok('undo edit', (await W.readText('index.html'))==='<h1>Hi</h1>');
await W.undoEntry(W.ws.history[1].id); ok('undo create', !W.exists('index.html'));
const reject=await A.execTool({name:'write_file',attrs:{path:'z.js'},body:'1'},{...ctx,confirm:async()=>false}); ok('reject', !reject.ok&&reject.step.status==='rejected'&&!W.exists('z.js'));

// --- регрессии из ревью ---
{
  const body = 'const s = "</tool>";\nconsole.log(s)';
  let pc = A.parseCalls(`Ок\n<tool name="write_file" path="a.js">\n${body}\n</tool>\n<tool name="read_file" path="b.js"/>`);
  ok('</tool> внутри файла', pc.calls.length === 2 && pc.calls[0].body.includes('console.log(s)'), pc.calls);
  pc = A.parseCalls('<tool name="write_file" path="a>b.js">\nx\n</tool>');
  ok('> внутри атрибута', pc.calls.length === 1 && pc.calls[0].attrs.path === 'a>b.js', pc.calls);
  pc = A.parseCalls('<tool name="hack" path="x"/>\n<tool name="read_file" path="a"/>');
  ok('неизвестный инструмент отдельно', pc.calls.length === 1 && pc.unknown[0] === 'hack', pc);
  ok('stripFence md не трогает код', A.stripFence('\n```js\nx\n```\n', 'README.md') === '```js\nx\n```');
  ok('stripFence md-обёртка', A.stripFence('```md\n# a\n```', 'README.md') === '# a');
  ok('stripFence 4 тика', A.stripFence('````html\n<p>```</p>\n````', 'a.html') === '<p>```</p>');
  ok('compact честный', !A.compactAssistant('<tool name="write_file" path="a">\n1\n2\n</tool>').includes('уже применено'));
  ok('applyEdit CRLF сохраняет', A.applyEdit('a\r\nb  \r\nc', 'b', 'X').text === 'a\r\nX  \r\nc' || A.applyEdit('a\r\nb\r\nc', 'b', 'X').text === 'a\r\nX\r\nc');
  const r1 = A.parseCalls('<tool name="write_file" path="x.js">\nconst a=');
  ok('оборванный блок', r1.truncated?.name === 'write_file');
  ok('секреты: расширенный список', ['.npmrc', 'a/.ssh/config', 'k.key', 'id_ed25519', '.ENV'].every((x) => W.isSecret(x)) && !W.isSecret('.env.example'));
  let threw = false; try { W.normPath('.GIT/config'); } catch { threw = true; }
  ok('.GIT закрыт', threw);
  r = await A.execTool({ name: 'search', attrs: { query: '(a+)+$', regex: 'true' }, body: '' }, ctx);
  ok('ReDoS отклонён', !r.ok, r.output);
  await W.writeText('u.txt', 'one');
  const en = W.recordChange('t', [{ path: 'u.txt', before: null, after: 'one' }]);
  await W.writeText('u.txt', 'two');
  let code = '';
  try { await W.undoEntry(en.id); } catch (e) { code = e.code; }
  ok('откат отказывает при конфликте', code === 'CONFLICT' && W.exists('u.txt'));
  ok('откат force', await W.undoEntry(en.id, { force: true }) && !W.exists('u.txt'));
  r = await A.execTool({ name: 'list_files', attrs: { path: '.' }, body: '' }, ctx);
  ok('list_files "."', r.ok, r.output);
}
console.log(fails?'FAILS '+fails:'ALL OK'); process.exit(fails?1:0);
