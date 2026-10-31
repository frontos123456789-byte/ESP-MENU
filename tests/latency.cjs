const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const http=require('node:http');
let browser,server,url=process.env.APP_URL;
const settings={theme:'dark',activeMode:'code',webSearch:false,keys:{openrouter:'test-not-a-real-key'},models:{code:'or:openrouter/free'}};
async function page(){
  const context=await browser.newContext({viewport:{width:390,height:844}});
  await context.addInitScript(s=>{if(window!==top)return;localStorage.clear();localStorage.setItem('shtab.settings.v1',JSON.stringify(s));},settings);
  const p=await context.newPage();const errors=[];p.on('pageerror',e=>errors.push(e.message));
  await p.route('**/*',r=>r.request().url().startsWith(url)?r.continue():r.abort());
  await p.goto(url,{waitUntil:'domcontentloaded'});
  p.setDefaultTimeout(5000);
  return {p,context,errors};
}
async function installStream(p){
  await p.evaluate(()=>{
    window.__requests=[];window.__cancelled=0;const native=fetch;
    window.fetch=async (url,opts={})=>{
      if(!String(url).includes('/chat/completions'))return native(url,opts);
      __requests.push(JSON.parse(opts.body));
      if(__requests.length>1)return new Response(JSON.stringify({choices:[{message:{content:'Готово: файл сохранён.'},finish_reason:'stop'}]}),{headers:{'Content-Type':'application/json'}});
      const encoder=new TextEncoder();
      return new Response(new ReadableStream({
        start(c){window.__emit=value=>c.enqueue(encoder.encode('data: '+JSON.stringify(value)+'\n\n'));},
        cancel(){window.__cancelled++;}
      }),{headers:{'Content-Type':'text/event-stream'}});
    };
  });
}
const tests=[];
const test=(name,fn)=>tests.push([name,fn]);
test('real staged tool stream shows draft before completion without writing early',async()=>{
  const {p,context,errors}=await page();await installStream(p);
  await p.locator('#input').fill('Создай latency.js');await p.locator('#sendBtn').click();
  await p.waitForFunction(()=>typeof __emit==='function');
  assert(!((await p.locator('#workTerm').textContent()).includes('Получает ответ')));
  assert.match(await p.locator('.assistant .agent-progress').textContent(),/Ожидает первый/);
  await p.evaluate(()=>__emit({choices:[{index:0,delta:{tool_calls:[{index:0,id:'call_write',type:'function',function:{name:'write_file',arguments:'{"path":"latency.js","content":"console.log(1);\\n'}}]}}]}));
  await p.waitForFunction(()=>document.querySelector('.agent-progress pre')?.textContent.includes('console.log(1)'));
  assert.match(await p.locator('.agent-progress').textContent(),/latency\.js/);
  assert.match(await p.locator('#workTerm').textContent(),/Генерирует файл/);
  assert.equal(await p.evaluate(()=>Object.hasOwn(workspaceSnapshot(),'latency.js')),false);
  await p.evaluate(()=>__emit({choices:[{index:0,delta:{tool_calls:[{index:0,function:{arguments:'console.log(2);"}'}}]},finish_reason:'tool_calls'}]}));
  await p.waitForFunction(()=>!isStreaming);
  assert.equal(await p.evaluate(()=>workspaceRead('latency.js')),'console.log(1);\nconsole.log(2);');
  assert.equal(await p.evaluate(()=>__cancelled),1,'terminal finish must cancel without waiting for DONE');
  assert.equal(await p.evaluate(()=>__requests.length),2);
  assert.deepEqual(errors,[]);await context.close();
});
test('cancelling partial arguments never writes a file',async()=>{
  const {p,context}=await page();await installStream(p);
  await p.locator('#input').fill('Создай never.js');await p.locator('#sendBtn').click();await p.waitForFunction(()=>typeof __emit==='function');
  await p.evaluate(()=>__emit({choices:[{delta:{tool_calls:[{index:0,id:'partial',type:'function',function:{name:'write_file',arguments:'{"path":"never.js","content":"incomplete'}}]}}]}));
  await p.locator('#wpCancel').click();await p.waitForFunction(()=>!isStreaming);
  assert.equal(await p.evaluate(()=>Object.hasOwn(workspaceSnapshot(),'never.js')),false);await context.close();
});
test('heartbeats and reasoning cannot prolong the first useful output deadline',async()=>{
  const {p,context}=await page();
  const result=await p.evaluate(async()=>{
    const encoder=new TextEncoder();let interval,cancelled=false;
    const response=new Response(new ReadableStream({start(c){interval=setInterval(()=>c.enqueue(encoder.encode(': heartbeat\n\ndata: {"choices":[{"delta":{"reasoning":"thinking"}}]}\n\n')),15);},cancel(){cancelled=true;clearInterval(interval);}}));
    const began=Date.now();try{await readAgentSSE(response,null,agentTurnAccumulator(),{firstContentMs:100,idleContentMs:100});return {bad:true};}catch(e){return {name:e.name,elapsed:Date.now()-began,cancelled};}
  });
  assert.equal(result.name,'TimeoutError');assert(result.elapsed<1200);assert(result.elapsed>=70);assert(result.cancelled);await context.close();
});
test('active generation may exceed first-output deadline and finish without DONE',async()=>{
  const {p,context}=await page();
  const result=await p.evaluate(async()=>{
    const encoder=new TextEncoder();let interval,n=0,cancelled=false;
    const response=new Response(new ReadableStream({start(c){interval=setInterval(()=>{n++;const choice={delta:{content:'x'}};if(n===5){choice.finish_reason='stop';clearInterval(interval);}c.enqueue(encoder.encode('data: '+JSON.stringify({choices:[choice]})+'\n\n'));},35);},cancel(){cancelled=true;clearInterval(interval);}}));
    const started=Date.now();const answer=await readAgentSSE(response,null,agentTurnAccumulator(),{firstContentMs:100,idleContentMs:100});return {answer,cancelled,elapsed:Date.now()-started};
  });
  assert.equal(result.answer.content,'xxxxx');assert(result.elapsed>100);assert(result.elapsed<1200);assert(result.cancelled);await context.close();
});
test('first-output timeout covers a stalled HTTP handshake',async()=>{
  const {p,context}=await page();
  const result=await p.evaluate(async()=>{
    window.fetch=(url,opts)=>new Promise((resolve,reject)=>opts.signal.addEventListener('abort',()=>reject(opts.signal.reason),{once:true}));
    const started=Date.now();try{await streamAgentTurn({key:'or:openrouter/free',messages:[{role:'user',content:'test'}],timing:{firstContentMs:90,idleContentMs:90}});return {bad:true};}catch(e){return {name:e.name,before:e.beforeOutput,elapsed:Date.now()-started};}
  });
  assert.equal(result.name,'TimeoutError');assert.equal(result.before,true);assert(result.elapsed<1200);await context.close();
});
test('Auto uses verified free coding models and retries only before any useful output',async()=>{
  const {p,context}=await page();
  const result=await p.evaluate(async()=>{
    orFreeModels=[{id:'cohere/north-mini-code:free',tools:true,label:'Code mini'},{id:'poolside/laguna-xs-2.1:free',tools:true,label:'Code XS'}];
    const candidates=agentModelCandidates('or:openrouter/free');const explicit=agentModelCandidates('or:cohere/north-mini-code:free');
    const keys=[],logs=[];streamAgentTurn=async opts=>{keys.push(opts.key);if(keys.length===1){const e=new DOMException('slow','TimeoutError');e.beforeOutput=true;throw e;}return {content:'Done',toolCalls:[]};};
    await runIDEAgent({key:'or:openrouter/free',messages:[{role:'user',content:'Explain'}],onStep:s=>logs.push(s)});
    const firstKeys=[...keys];keys.length=0;
    streamAgentTurn=async opts=>{keys.push(opts.key);const e=new DOMException('partial stalled','TimeoutError');e.beforeOutput=false;throw e;};
    try{await runIDEAgent({key:'or:openrouter/free',messages:[{role:'user',content:'Explain'}]});}catch{}
    return {candidates,explicit,firstKeys,afterPartial:keys,logs};
  });
  assert.equal(result.candidates.length,2);assert.equal(result.explicit.length,1);assert.deepEqual(result.firstKeys,result.candidates);assert.equal(result.afterPartial.length,1);assert(result.logs.some(x=>x.includes('Пробует')));await context.close();
});
test('draft decoder safely handles escaped and incomplete JSON strings',async()=>{
  const {p,context}=await page();
  const values=await p.evaluate(()=>[
    partialToolString('{"path":"src/main.js","content":"hello\\n\\u041f\\"world\\\\','content'),
    partialToolString('{"path":"src/main.js","content":"hello\\n\\u04','content'),
    partialToolString('{"path":"src/main.js"','path'),
    partialToolString('{"content":"<img onerror=alert(1)>','content')
  ]);
  assert.deepEqual(values,['hello\nП"world\\','hello\n','src/main.js','<img onerror=alert(1)>']);await context.close();
});
(async()=>{
  if(!url){server=http.createServer((req,res)=>{res.setHeader('Content-Type','text/html; charset=utf-8');res.end(fs.readFileSync(path.resolve(__dirname,'../index.html')));});await new Promise(r=>server.listen(0,'127.0.0.1',r));url='http://127.0.0.1:'+server.address().port;}
  browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE||undefined,headless:true,args:['--no-sandbox'],...(process.env.HTTPS_PROXY?{proxy:{server:process.env.HTTPS_PROXY,bypass:'127.0.0.1,localhost'}}:{})});
  let failed=0;for(const [name,fn]of tests){try{await fn();console.log('PASS',name);}catch(e){failed++;console.error('FAIL',name,e);}}
  console.log(`${tests.length-failed}/${tests.length} latency tests passed`);process.exitCode=failed?1:0;
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(async()=>{await browser?.close();server?.close();});
