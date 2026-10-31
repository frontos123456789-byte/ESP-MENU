const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const APP = process.env.APP_PATH || path.resolve(__dirname, '../index.html');
const ARTIFACTS = process.env.TEST_ARTIFACTS_DIR || fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'shtab-tests-'));
fs.mkdirSync(ARTIFACTS, {recursive:true});
let URL = process.env.APP_URL;
let server;
const report = [];
let browser;
const settingsKey = 'shtab.settings.v1';
const chatsKey = 'shtab.chats.v1';
const fixtureSettings = { theme:'dark', font:'Golos Text',fontSize:'15',webSearch:false,models:{chat:'or:openrouter/free',work:'or:openrouter/free',code:'or:openrouter/free'},prompts:{chat:'',work:'',code:''},keys:{groq:'',openrouter:'test-key-not-real',pollinations:'',tavily:''},connectors:{github:{enabled:false,token:'',user:null},vercel:{enabled:false,token:'',user:null}},activeMode:'chat',activeChats:{chat:null,work:null,code:null} };
async function test(name, fn) { try { await fn(); report.push({name,pass:true}); console.log('PASS',name); } catch(e) { report.push({name,pass:false,error:String(e.stack||e)}); console.log('FAIL',name,String(e.message)); } }
async function pageFor({viewport={width:1440,height:1000},settings=fixtureSettings,chats=[],response='normal',mobile=false}={}) {
 const context = await browser.newContext({ viewport, isMobile:mobile, deviceScaleFactor:1 });
 const errors = []; const requests=[];
 const page = await context.newPage(); page.on('pageerror', e=>errors.push(e.message));
 await context.addInitScript(({settings,chats,settingsKey,chatsKey})=>{if(window!==window.top)return;if(localStorage.getItem('__harness_seeded'))return;localStorage.clear();localStorage.setItem('__harness_seeded','1');localStorage.setItem(settingsKey,typeof settings==='string'?settings:JSON.stringify(settings));localStorage.setItem(chatsKey,typeof chats==='string'?chats:JSON.stringify(chats));}, {settings,chats,settingsKey,chatsKey});
 await page.route('**/*', async route=> {
  const req=route.request(); const url=req.url();
  if(url.startsWith(URL)) return route.continue();
  if(url.includes('fonts.googleapis.com') || url.includes('fonts.gstatic.com')) return route.continue();
  if(url.includes('/chat/completions')) {
   requests.push(req.postDataJSON());
   if(response==='401') return route.fulfill({status:401,contentType:'application/json',body:JSON.stringify({error:{message:'Invalid API key'}})});
   if(response==='delay') { await new Promise(r=>setTimeout(r,2500)); }
   if(response==='agent-loop') {
    const check = 'const { multiply } = require("./multiply.js"); if (multiply(3, 4) !== 12) throw new Error("Expected 12, got " + multiply(3, 4)); console.log("PASS: multiply(3, 4) = 12");';
    const actions = [
     ['write_file', {path:'multiply.js', content:'module.exports.multiply = (a, b) => a + b;'}],
     ['run_javascript', {code:check}],
     ['replace_in_file', {path:'multiply.js',old_text:'a + b',new_text:'a * b'}],
     ['run_javascript', {code:check}]
    ];
    const action=actions[requests.length-1];
    const events=[];
    if(action) {
     const args=JSON.stringify(action[1]),split=Math.floor(args.length/2);
     events.push({choices:[{index:0,delta:{tool_calls:[{index:0,id:'call_'+requests.length,type:'function',function:{name:action[0],arguments:args.slice(0,split)}}]}}]});
     events.push({choices:[{index:0,delta:{tool_calls:[{index:0,function:{arguments:args.slice(split)}}]},finish_reason:'tool_calls'}]});
    } else events.push({choices:[{index:0,delta:{content:'Исправлено. multiply.js проверен настоящим JavaScript-тестом.'},finish_reason:'stop'}]});
    return route.fulfill({status:200,contentType:'text/event-stream',body:events.map(event=>'data: '+JSON.stringify(event)+'\n\n').join('')+'data: [DONE]\n\n',headers:{'access-control-allow-origin':'*'}});
   }
   const reply='Ответ готов.\n\n```js\nconst n = 2;\nconsole.log(n);\n```';
   const stream='data: '+JSON.stringify({choices:[{delta:{content:reply.slice(0,12)}}]})+'\n\n'+'data: '+JSON.stringify({choices:[{delta:{content:reply.slice(12)}}]})+'\n\n'+'data: '+JSON.stringify({choices:[{delta:{},finish_reason:'stop'}]})+'\n\n'+'data: [DONE]\n\n';
   return route.fulfill({status:200,contentType:'text/event-stream',body:stream,headers:{'access-control-allow-origin':'*'}});
  }
  if(url.includes('openrouter.ai/api/v1/models')) return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({data:[{id:'openrouter/free',name:'Free Router',pricing:{prompt:'0',completion:'0'}},{id:'test/model:free',name:'Test model',pricing:{prompt:'0',completion:'0'}}]})});
  return route.abort();
 });
 await page.goto(URL,{waitUntil:'domcontentloaded'}); await page.waitForTimeout(120);page.setDefaultTimeout(8000);
 return {context,page,errors,requests};
}
async function send(page,text='Проверь пример') { await page.locator('#input').fill(text); await page.locator('#sendBtn').click(); }
(async()=>{
 if(!URL){ server=require('node:http').createServer((req,res)=>{res.setHeader('Content-Type','text/html; charset=utf-8');res.end(fs.readFileSync(APP));});await new Promise(r=>server.listen(0,'127.0.0.1',r));URL='http://127.0.0.1:'+server.address().port;}
 browser=await chromium.launch({...(process.env.CHROMIUM_EXECUTABLE?{executablePath:process.env.CHROMIUM_EXECUTABLE}:{}),headless:true,args:['--no-sandbox'],...(process.env.HTTPS_PROXY?{proxy:{server:process.env.HTTPS_PROXY,bypass:'127.0.0.1,localhost'}}:{})});
 await test('standalone HTML startup and default empty state',async()=>{const {context,page,errors}=await pageFor({settings:{}});assert.equal(errors.length,0,errors.join('\n'));assert.equal(await page.evaluate(()=>typeof sendMessage),'function');assert(await page.locator('#input').isVisible());assert(await page.locator('.empty').isVisible());await context.close();});
 await test('malformed persisted records never crash startup',async()=>{for(const raw of ['null','{}','[{"id":"x","mode":"bad","title":null,"messages":[]}]']){const {context,page,errors}=await pageFor({chats:raw});assert.equal(errors.length,0,errors.join('\n'));assert(await page.locator('#input').isVisible());await context.close();}});
 await test('streamed response renders code and persists conversation',async()=>{const {context,page,errors,requests}=await pageFor();await send(page);await page.waitForFunction(()=>!isStreaming);assert.equal(errors.length,0,errors.join('\n'));assert.equal(requests.length,1);assert.equal(requests[0].model,'openrouter/free');assert.match(await page.locator('.assistant .msg-body').innerText(),/Ответ готов/);assert.equal((await page.locator('.assistant pre code').textContent()).trim(),'const n = 2;\nconsole.log(n);');const saved=await page.evaluate(key=>JSON.parse(localStorage.getItem(key)),chatsKey);assert.equal(saved[0].messages.length,2);assert.equal(saved[0].messages[1].typing,false);await context.close();});
 await test('provider error shown and composer returns ready',async()=>{const {context,page,errors}=await pageFor({response:'401'});await send(page);await page.waitForFunction(()=>!isStreaming);assert.match(await page.locator('.assistant .msg-body').innerText(),/ключ|key|401|авторизац/i);assert.equal(errors.length,0,errors.join('\n'));assert.equal(await page.locator('#sendIcon').textContent(),'arrow_upward');await context.close();});
 await test('abort stops code overlay and restores composer',async()=>{const {context,page,errors}=await pageFor({response:'delay'});await page.locator('.tab[data-mode="code"]').click();await send(page);await page.waitForFunction(()=>isStreaming);assert(await page.locator('#workOverlay').evaluate(el=>el.classList.contains('show')));await page.locator('#wpCancel').click();await page.waitForFunction(()=>!isStreaming);await page.waitForTimeout(900);assert(!(await page.locator('#workOverlay').evaluate(el=>el.classList.contains('show'))));assert.equal(errors.length,0,errors.join('\n'));await context.close();});
 await test('mobile layouts fit viewport at 390 and 320px',async()=>{for(const width of [390,320]){const {context,page,errors}=await pageFor({viewport:{width,height:844},mobile:true});const over=await page.evaluate(()=>({scroll:document.documentElement.scrollWidth,width:innerWidth}));assert(over.scroll<=width+1,JSON.stringify(over));await page.locator('#btnMenu').click();assert(await page.locator('#sidebar').evaluate(el=>el.classList.contains('open')));await page.locator('#btnSettings').click();assert(await page.locator('#settingsModal').evaluate(el=>el.classList.contains('show')));const bounds=await page.locator('#settingsModal').boundingBox();assert(bounds.x>=-1 && bounds.x+bounds.width<=width+1,JSON.stringify(bounds));await page.screenshot({path:path.join(ARTIFACTS,`mobile-${width}.png`)});assert.equal(errors.length,0,errors.join('\n'));await context.close();}});
 await test('modal keyboard focus stays in dialog and Escape returns it',async()=>{const {context,page}=await pageFor();await page.locator('#btnSettings').click();await page.waitForTimeout(150);assert(await page.evaluate(()=>document.activeElement.closest('#settingsModal')!==null),'initial focus outside');for(let i=0;i<90;i++){await page.keyboard.press('Tab');assert(await page.evaluate(()=>document.activeElement.closest('#settingsModal')!==null),'Tab escaped modal');}await page.keyboard.press('Escape');assert(!(await page.locator('#settingsModal').evaluate(el=>el.classList.contains('show'))));await context.close();});
 await test('code preview cannot access parent API keys',async()=>{const {context,page}=await pageFor();await page.evaluate(()=>openPreview('html','<script>try { parent.__previewEscape=localStorage.getItem("shtab.settings.v1"); } catch(e) {}<\/script>'));await page.waitForTimeout(150);assert.equal(await page.evaluate(()=>window.__previewEscape),undefined);const sandbox=await page.locator('#previewFrame').getAttribute('sandbox');assert(!sandbox.includes('allow-same-origin'));await context.close();});
 await test('malicious import is safe and accepted records are normalized',async()=>{const {context,page,errors}=await pageFor();await page.locator('#btnSettings').click();const payload={chats:[{id:'x\" onclick=\"window.__xss=1',mode:'chat',title:'Bad',created:Date.now(),updated:Date.now(),messages:[{id:'m',role:'assistant',content:'[bad](javascript:alert(1))',ts:Date.now(),sources:[{title:'bad',url:'javascript:alert(1)',host:'bad'}]}]},{id:'broken',mode:'invalid',title:null,messages:[]}]};await page.locator('#importFile').setInputFiles({name:'import.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(payload))});await page.waitForTimeout(200);assert.equal(errors.length,0,errors.join('\n'));assert.equal(await page.locator('[onclick]').count(),0);await page.keyboard.press('Escape');const imported=page.locator('.hist-item').filter({hasText:'Bad'});if(await imported.count())await imported.first().click();assert.equal(await page.locator('a[href^="javascript:"]').count(),0);await context.close();});
 await test('missing key preserves draft and opens settings',async()=>{const {context,page,errors,requests}=await pageFor({settings:{...fixtureSettings,keys:{groq:'',openrouter:'',pollinations:''}}});await send(page,'Мой важный черновик');await page.waitForTimeout(150);assert.equal(await page.locator('#input').inputValue(),'Мой важный черновик');assert.equal(requests.length,0);assert(await page.locator('#settingsModal').evaluate(el=>el.classList.contains('show')));assert.equal(errors.length,0,errors.join('\n'));await context.close();});
 await test('theme and completed history survive reload',async()=>{const {context,page,errors}=await pageFor();await send(page,'Сохрани этот диалог');await page.waitForFunction(()=>!isStreaming);await page.locator('#btnThemeQuick').click();assert.equal(await page.locator('html').getAttribute('data-theme'),'light');await page.reload({waitUntil:'domcontentloaded'});assert.equal(await page.locator('html').getAttribute('data-theme'),'light');assert.match(await page.locator('.assistant .msg-body').innerText(),/Ответ готов/);assert.equal(errors.length,0,errors.join('\n'));await context.close();});
 await test('copy code returns original source text',async()=>{const {context,page}=await pageFor();await page.evaluate(()=>{Object.defineProperty(navigator,'clipboard',{value:{writeText:async value=>{window.__copied=value;}},configurable:true});});await send(page);await page.waitForFunction(()=>!isStreaming);await page.locator('.cb-copy').click();assert.equal((await page.evaluate(()=>window.__copied)).trim(),'const n = 2;\nconsole.log(n);');await context.close();});
 await test('request keeps selected mode during response',async()=>{const {context,page,errors,requests}=await pageFor({response:'delay'});await send(page);await page.waitForFunction(()=>isStreaming);const tab=page.locator('.tab[data-mode="work"]');if(!(await tab.isDisabled()))await tab.click({force:true});assert.equal(await page.evaluate(()=>settings.activeMode),'chat');await page.waitForFunction(()=>!isStreaming);assert.equal(requests.length,1);const saved=await page.evaluate(key=>JSON.parse(localStorage.getItem(key)),chatsKey);assert.equal(saved[0].mode,'chat');assert.equal(errors.length,0,errors.join('\n'));await context.close();});
 await test('regenerate retains original conversation',async()=>{const {context,page,errors}=await pageFor();await send(page,'Первый вопрос');await page.waitForFunction(()=>!isStreaming);await send(page,'Второй вопрос');await page.waitForFunction(()=>!isStreaming);const original=await page.evaluate(()=>currentChat().id);await page.locator('[data-regen]').first().click();await page.waitForFunction(()=>!isStreaming);const all=await page.evaluate(key=>JSON.parse(localStorage.getItem(key)),chatsKey);const old=all.find(c=>c.id===original);assert.equal(old.messages.length,4);assert.equal(all.length,2);assert.equal(errors.length,0,errors.join('\n'));await context.close();});

 await test('IDE agent writes, executes failing code, fixes it and actually passes',async()=>{
  const {context,page,errors,requests}=await pageFor({response:'agent-loop',settings:{...fixtureSettings,connectors:{github:{enabled:true,token:'github-token-must-stay-private',user:{login:'example',public_repos:1},repos:[]},vercel:{enabled:false,token:'vercel-token-must-stay-private',user:null}}}});
  await page.locator('.tab[data-mode="code"]').click();
  assert(await page.locator('#ideWorkspace').isVisible());
  await send(page,'Создай multiply.js, проверь multiply(3, 4) = 12 и исправь найденную ошибку.');
  await page.waitForFunction(()=>!isStreaming,null,{timeout:30000});
  assert.equal(errors.length,0,errors.join('\n'));
  assert.equal(requests.length,5,'expected four actual tool turns followed by final answer');
  assert(requests.every(request=>Array.isArray(request.tools) && request.tools.some(tool=>tool.function.name==='run_javascript')));
  assert.match(await page.evaluate(()=>workspaceRead('multiply.js')),/a \* b/);
  const failed=JSON.parse(requests[2].messages.filter(message=>message.role==='tool').at(-1).content);
  assert.equal(failed.executed,true);assert.equal(failed.ok,false);assert.match(failed.error,/Expected 12, got 7/);
  const passed=JSON.parse(requests[4].messages.filter(message=>message.role==='tool').at(-1).content);
  assert.equal(passed.executed,true);assert.equal(passed.ok,true);assert.match(passed.stdout,/PASS: multiply\(3, 4\) = 12/);
  const bodies=JSON.stringify(requests);
  for(const secret of ['test-key-not-real','github-token-must-stay-private','vercel-token-must-stay-private'])assert(!bodies.includes(secret),'credential leaked in model context');
  assert.match(await page.locator('.assistant .msg-body').innerText(),/Исправлено/);
  assert.equal(await page.locator('#ideEditor').isDisabled(),false);
  await page.reload({waitUntil:'domcontentloaded'});assert.match(await page.evaluate(()=>workspaceRead('multiply.js')),/a \* b/);
  await context.close();
 });
 await test('IDE edits persist and undo restores a previous saved version',async()=>{
  const {context,page,errors}=await pageFor();await page.locator('.tab[data-mode="code"]').click();
  await page.evaluate(()=>workspaceWrite('notes.js','const note = 1;'));
  await page.locator('#ideFileList [data-path="notes.js"]').click();
  await page.locator('#ideEditor').fill('const note = 2;');
  await page.waitForFunction(()=>workspaceRead('notes.js')==='const note = 2;');
  await page.locator('#ideUndo').click();assert.equal(await page.evaluate(()=>workspaceRead('notes.js')),'const note = 1;');
  await page.reload({waitUntil:'domcontentloaded'});assert.equal(await page.evaluate(()=>workspaceRead('notes.js')),'const note = 1;');
  assert.equal(errors.length,0,errors.join('\n'));await context.close();
 });
 await test('IDE storage failure rolls back a write and rejects unsafe paths',async()=>{
  const {context,page}=await pageFor();
  const result=await page.evaluate(()=>{
   const before=workspaceSnapshot(),native=Storage.prototype.setItem;
   Storage.prototype.setItem=function(key,value){if(key==='shtab.workspace.v1')throw new DOMException('Quota exceeded','QuotaExceededError');return native.call(this,key,value);};
   let failed=false;try{workspaceWrite('not-saved.js','bad');}catch{failed=true;}finally{Storage.prototype.setItem=native;}
   const unsafe=['../escape.js','/absolute.js','a/../../escape.js','C:\\escape.js'].map(path=>{try{workspaceWrite(path,'bad');return false;}catch{return true;}});
   return {failed,unchanged:JSON.stringify(before)===JSON.stringify(workspaceSnapshot()),unsafe};
  });assert(result.failed);assert(result.unchanged);assert(result.unsafe.every(Boolean));await context.close();
 });
 await test('sandbox executes local modules and blocks browser secrets and network',async()=>{
  const {context,page,errors}=await pageFor();
  const result=await page.evaluate(()=>runWorkspaceJavaScript({files:{'src/add.js':'module.exports = (a, b) => a + b;'},code:'const add = require("./src/add.js"); if(add(2,3)!==5)throw Error("wrong sum"); console.log("sum",add(2,3)); console.log(typeof localStorage,typeof window); try { await fetch("https://example.com/secret"); throw Error("network unexpectedly allowed"); } catch(error) { if(error.message==="network unexpectedly allowed")throw error; console.log("network blocked"); }'}));
  assert.equal(result.success,true,result.error);assert.match(result.stdout.join('\n'),/sum 5/);assert.match(result.stdout.join('\n'),/undefined undefined/);assert.match(result.stdout.join('\n'),/network blocked/);assert.equal(errors.length,0,errors.join('\n'));await context.close();
 });
 await test('sandbox terminates infinite loops and aborts long asynchronous runs',async()=>{
  const {context,page}=await pageFor();
  const timed=await page.evaluate(()=>runWorkspaceJavaScript({code:'while(true){}',timeoutMs:300}));assert.equal(timed.success,false);assert.match(timed.error,/время|мс|time/i);
  const aborted=await page.evaluate(async()=>{const control=new AbortController();const job=runWorkspaceJavaScript({code:'await new Promise(resolve=>setTimeout(resolve,10000));',signal:control.signal,timeoutMs:20000});setTimeout(()=>control.abort(),100);return job;});assert.equal(aborted.success,false);assert.match(aborted.error,/отмен|abort/i);assert.equal(await page.locator('iframe[data-ide-runner]').count(),0);await context.close();
 });
 await test('Code workspace panels fit 320px and a local preview actually runs',async()=>{
  const {context,page,errors}=await pageFor({viewport:{width:320,height:844},mobile:true});await page.locator('.tab[data-mode="code"]').click();
  for(const view of ['files','editor','preview','chat']){
   await page.locator(`#ideMobileTabs [data-ide-view="${view}"]`).click();
   const bounds=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth}));assert(bounds.scroll<=bounds.width+1,JSON.stringify({view,...bounds}));
  }
  await page.evaluate(()=>workspaceWrite('test-preview.html','<!doctype html><html><body><button id="counter">0</button><script>document.getElementById("counter").onclick = event => event.target.textContent = Number(event.target.textContent) + 1;<\/script></body></html>'));
  await page.locator('#ideMobileTabs [data-ide-view="preview"]').click();await page.locator('#ideEntry').selectOption('test-preview.html');
  const frame=page.frameLocator('#idePreviewFrame');await frame.locator('#counter').click();assert.equal(await frame.locator('#counter').textContent(),'1');
  await page.screenshot({path:path.join(ARTIFACTS,'ide-mobile-320.png')});assert.equal(errors.length,0,errors.join('\n'));await context.close();
 });


 await test('workspace ZIP export contains the actual saved files',async()=>{
  const {context,page}=await pageFor();await page.locator('.tab[data-mode="code"]').click();
  await page.evaluate(()=>workspaceWrite('nested/hello.txt','Привет & <tag>'));
  const downloadPromise=page.waitForEvent('download');await page.locator('#ideExport').click();const download=await downloadPromise;
  assert.match(download.suggestedFilename(),/\.zip$/);const bytes=fs.readFileSync(await download.path());
  const extracted=new Map();let offset=0;
  while(offset+30<=bytes.length && bytes.readUInt32LE(offset)===0x04034b50){
   assert.equal(bytes.readUInt16LE(offset+8),0,'single-file exporter uses uncompressed ZIP entries');
   const length=bytes.readUInt32LE(offset+18),nameLength=bytes.readUInt16LE(offset+26),extraLength=bytes.readUInt16LE(offset+28);
   const name=bytes.subarray(offset+30,offset+30+nameLength).toString('utf8'),start=offset+30+nameLength+extraLength;
   extracted.set(name,bytes.subarray(start,start+length).toString('utf8'));offset=start+length;
  }
  assert.equal(extracted.get('nested/hello.txt'),'Привет & <tag>');assert(extracted.size>1);await context.close();
 });

 await test('desktop screenshot',async()=>{const {context,page}=await pageFor({settings:{}});await page.screenshot({path:path.join(ARTIFACTS,'desktop.png')});await context.close();});
 await browser.close();server?.close();fs.writeFileSync(path.join(ARTIFACTS,'results.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({passed:report.filter(x=>x.pass).length,total:report.length,artifacts:ARTIFACTS}));process.exitCode=report.some(x=>!x.pass)?1:0;
})().catch(e=>{console.error(e);process.exitCode=1;browser?.close();server?.close();});
