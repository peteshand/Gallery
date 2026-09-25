import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const root = process.cwd();
const viewportWidth = Number(process.env.GALLERY_VIEWPORT_WIDTH || 390);
if (!Number.isInteger(viewportWidth) || viewportWidth < 320 || viewportWidth > 600) throw Error('GALLERY_VIEWPORT_WIDTH must be 320–600');
const browserBin = process.env.GALLERY_BROWSER_BIN || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const profileName = browserBin.toLowerCase().includes('msedge') ? 'edge-cdp' : 'chrome-cdp';
const port = 43191;
const debugPort = 49245;
const server = spawn(process.execPath, ['server.mjs'], {
  cwd: root, windowsHide: true,
  env: { ...process.env, PORT: String(port), GALLERY_DB: ':memory:', GALLERY_SOURCE: 'I:\\Photos\\Best of Poe 2' },
  stdio: ['ignore', 'pipe', 'pipe']
});
const chrome = spawn(browserBin, [
  '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run', '--no-default-browser-check',
  `--remote-debugging-port=${debugPort}`, `--user-data-dir=${root}\\.tools\\${profileName}`, 'about:blank'
], { cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function retry(fn) {
  for (let n = 0; n < 60; n++) {
    try { return await fn(); } catch { await sleep(250); }
  }
  throw Error('service did not start');
}
try {
  await retry(async () => { const r = await fetch(`http://127.0.0.1:${port}/api/assets`); if (!r.ok) throw Error(); });
  const targets = await retry(async () => {
    const r = await fetch(`http://127.0.0.1:${debugPort}/json/list`);
    const pages = await r.json();
    if (!pages.some(p => p.type === 'page')) throw Error();
    return pages;
  });
  const ws = new WebSocket(targets.find(p => p.type === 'page').webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  let nextId = 1;
  const pending = new Map();
  const exceptions = [];
  ws.onmessage = event => {
    const message = JSON.parse(event.data);
    if (message.method === 'Runtime.exceptionThrown') exceptions.push(message.params.exceptionDetails.text + ': ' + (message.params.exceptionDetails.exception?.description || ''));
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      message.error ? reject(Error(message.error.message)) : resolve(message.result);
    }
  };
  function command(method, params = {}) {
    const id = nextId++;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, method, params }));
    });
  }
  await command('Runtime.enable');
  await command('Page.enable');
  await command('Network.enable');
  await command('Network.setCacheDisabled', { cacheDisabled: true });
  if (process.env.GALLERY_MOCK_TAURI === '1') {
    const sampleSource = String.raw`I:\Photos\Best of Poe 2`;
    const source = `let cloud = {configured:false,credentialsAvailable:false,bucket:'',region:'',endpoint:'',prefix:'',maskedKeyId:'',lastVerifiedAt:null};
    let syncRunning = false;
    let syncCancelled = false;
    window.__selectedSyncCalls = [];
    window.__TAURI__ = {
      core: {
        invoke: async (command, args = {}) => {
          let response;
          if (command === 'list_assets') response = await fetch('/api/assets');
          else if (command === 'import_source') response = await fetch('/api/import', { method: 'POST' });
          else if (command === 'set_favorite') response = await fetch('/api/assets/' + args.id + '/favorite', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ favorite: args.favorite }) });
          else if (command === 'get_default_source') return ${JSON.stringify(sampleSource)};
          else if (command === 'list_import_errors') return [];
          else if (command === 'get_s3_connection') return cloud;
          else if (command === 'save_s3_connection') {
            cloud = {configured:true,credentialsAvailable:true,bucket:args.input.bucket,region:args.input.region,endpoint:args.input.endpoint,prefix:args.input.prefix + '/',maskedKeyId:'••••' + args.input.accessKeyId.slice(-4),lastVerifiedAt:null};
            return cloud;
          }
          else if (command === 'remove_s3_connection') {
            cloud = {configured:false,credentialsAvailable:false,bucket:'',region:'',endpoint:'',prefix:'',maskedKeyId:'',lastVerifiedAt:null};
            return cloud;
          }
          else if (command === 'test_s3_connection') return true;
          else if (command === 'get_sync_status') return {running:syncRunning,cancelling:false,cancelled:syncCancelled,total:111,notSynced:syncRunning?110:111,preparing:syncRunning?1:0,uploading:0,synced:0,failed:0,currentName:syncRunning?'sample.jpg':null,lastError:null};
          else if (command === 'start_sync') { syncRunning = true; syncCancelled = false; return {running:true,cancelling:false,cancelled:false,total:111,notSynced:110,preparing:1,uploading:0,synced:0,failed:0,currentName:'sample.jpg',lastError:null}; }
          else if (command === 'cancel_sync') { syncRunning = false; syncCancelled = true; return {running:false,cancelling:false,cancelled:true,total:111,notSynced:111,preparing:0,uploading:0,synced:0,failed:0,currentName:null,lastError:null}; }
          else if (command === 'start_sync_selected') {
            window.__selectedSyncCalls.push(args.ids);
            return {running:false,cancelling:false,cancelled:false,total:111,notSynced:109,preparing:0,uploading:0,synced:2,failed:0,currentName:null,lastError:null};
          }
          else throw Error('Unknown command: ' + command);
          if (!response.ok) throw Error(await response.text());
          const result = await response.json();
          if (command === 'list_assets') result.forEach((asset, index) => { asset.syncState = index === 0 ? 'synced' : index === 1 ? 'uploading' : index === 2 ? 'failed' : 'not_synced'; });
          return result;
        },
        convertFileSrc: path => path
      },
      dialog: { open: async () => ${JSON.stringify(sampleSource)} }
    };`;
    await command('Page.addScriptToEvaluateOnNewDocument', { source });
  }
  await command('Emulation.setDeviceMetricsOverride', { width: viewportWidth, height: 844, deviceScaleFactor: 1, mobile: true });
  await command('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 1 });
  exceptions.length = 0;
  await command('Page.navigate', { url: `http://127.0.0.1:${port}/` });
  await sleep(800);
  async function evaluate(expression) {
    const result = await command('Runtime.evaluate', { expression, returnByValue: true });
    if (result.exceptionDetails) throw Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
    return result.result.value;
  }
  const initialCount = await evaluate(`document.querySelectorAll('.photo-tile').length`);
  await evaluate(`document.querySelector('#import-button').click()`);
  let loadedCount = 0;
  for (let i = 0; i < 100; i++) {
    await sleep(200);
    loadedCount = await evaluate(`document.querySelectorAll('.photo-tile').length`);
    if (loadedCount === 111) break;
  }
  const evaluation = await command('Runtime.evaluate', { expression: `JSON.stringify({title:document.title, content:document.querySelector('#content')?.innerText?.slice(0,150), count:document.querySelectorAll('.photo-tile').length, nav:document.querySelectorAll('.nav-item').length, width:document.documentElement.scrollWidth, viewport:innerWidth, status:document.querySelector('#status').textContent})`, returnByValue: true });
  console.log('page', evaluation.result.value);
  const page = JSON.parse(evaluation.result.value);
  const syncBadges = await evaluate(`document.querySelectorAll('.sync-badge').length`);
  console.log('mode', process.env.GALLERY_MOCK_TAURI === '1' ? 'Tauri service mock' : 'browser service');
  console.log('import', JSON.stringify({ initialCount, loadedCount }));
  await sleep(650);
  await evaluate(`document.querySelector('#status').style.visibility='hidden'`);
  const screenshot = await command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  writeFileSync(`.tools/mobile-gallery-${viewportWidth}.png`, Buffer.from(screenshot.data, 'base64'));
  const grid = JSON.parse(await evaluate(`(() => { const content=document.querySelector('#content'); const tile=document.querySelector('.photo-tile'); const image=tile.querySelector('img').cloneNode(); image.classList.remove('loaded'); tile.appendChild(image); const placeholderHidden=image.alt===''&&getComputedStyle(image).opacity==='0'; image.remove(); const before=getComputedStyle(document.querySelector('.photo-grid')).gridTemplateColumns.split(' ').length; const a=new Touch({identifier:41,target:content,clientX:100,clientY:300}); const b=new Touch({identifier:42,target:content,clientX:200,clientY:300}); const far=new Touch({identifier:42,target:content,clientX:280,clientY:300}); content.dispatchEvent(new TouchEvent('touchstart',{bubbles:true,touches:[a,b]})); content.dispatchEvent(new TouchEvent('touchend',{bubbles:true,touches:[a],changedTouches:[far]})); const zoomed=getComputedStyle(document.querySelector('.photo-grid')).gridTemplateColumns.split(' ').length; return JSON.stringify({before,zoomed,placeholderHidden}); })()`));
  console.log('grid', JSON.stringify(grid));
  const justified = JSON.parse(await evaluate(`(() => {
    const content=document.querySelector('#content');
    const a=new Touch({identifier:51,target:content,clientX:100,clientY:300});
    const b=new Touch({identifier:52,target:content,clientX:200,clientY:300});
    const far=new Touch({identifier:52,target:content,clientX:290,clientY:300});
    content.dispatchEvent(new TouchEvent('touchstart',{bubbles:true,touches:[a,b]}));
    content.dispatchEvent(new TouchEvent('touchend',{bubbles:true,touches:[a],changedTouches:[far]}));
    const grid=document.querySelector('.photo-grid');
    const rows=new Map();
    for (const tile of grid.querySelectorAll('.photo-tile')) {
      const r=tile.getBoundingClientRect();const key=Math.round(r.top);
      if (!rows.has(key)) rows.set(key,[]);rows.get(key).push(r);
    }
    const complete=[...rows.values()].filter(row=>row.length>1).slice(0,3);
    const edge=grid.getBoundingClientRect().right;
    return JSON.stringify({mode:getComputedStyle(grid).display,rows:complete.length,filled:complete.every(row=>Math.abs(row[row.length-1].right-edge)<3),sameHeight:complete.every(row=>row.every(r=>Math.abs(r.height-row[0].height)<1))});
  })()`));
  console.log('justified', JSON.stringify(justified));
  const largeGridShot = await command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  writeFileSync(`.tools/mobile-large-grid-${viewportWidth}.png`, Buffer.from(largeGridShot.data, 'base64'));
  const timeline = JSON.parse(await evaluate(`(() => { const dates=[...document.querySelectorAll('#content .photo-tile')].map(tile=>tile.getAttribute('data-taken-at')); return JSON.stringify({grids:document.querySelectorAll('#content .photo-grid').length,dateHeadings:document.querySelectorAll('#content .date-heading').length,chronological:dates.every((date,index)=>index===0||dates[index-1]>=date)}); })()`));
  console.log('timeline', JSON.stringify(timeline));
  const visual = JSON.parse(await evaluate(`(() => { const shell=document.querySelector('.shell'); const nav=document.querySelector('.bottom-nav'); const pill=document.querySelector('.nav-pill'); return JSON.stringify({background:getComputedStyle(shell).backgroundColor,stories:document.querySelectorAll('.story-card').length,storyHeading:document.querySelectorAll('.section-heading').length,navBackground:getComputedStyle(nav).backgroundColor,pillRadius:getComputedStyle(pill).borderRadius,syncedBadgeHidden:[...document.querySelectorAll('.sync-badge.synced')].every(badge=>getComputedStyle(badge).display==='none')}); })()`));
  console.log('visual', JSON.stringify(visual));
  await evaluate(`document.querySelector('.story-card').click()`);
  const memoryTitle = await evaluate(`document.querySelector('#viewer-title').textContent`);
  const viewer = await evaluate(`JSON.stringify({open:!document.querySelector('#viewer').classList.contains('hidden'),title:document.querySelector('#viewer-title').textContent})`);
  await evaluate(`(() => { const stage = document.querySelector('.viewer-stage'); const begin = new Touch({identifier:1,target:stage,clientX:300,clientY:350}); const end = new Touch({identifier:1,target:stage,clientX:50,clientY:350}); stage.dispatchEvent(new TouchEvent('touchstart',{bubbles:true,touches:[begin]})); stage.dispatchEvent(new TouchEvent('touchend',{bubbles:true,changedTouches:[end]})); })()`);
  await new Promise(resolve => setTimeout(resolve, 350));
  const swipedTitle = await evaluate(`document.querySelector('#viewer-title').textContent`);
  await evaluate(`document.querySelector('#viewer-favorite').click()`);
  await sleep(500);
  const favorite = await evaluate(`document.querySelector('#viewer-favorite').textContent`);
  await evaluate(`(() => { const stage = document.querySelector('.viewer-stage'); const begin = new Touch({identifier:3,target:stage,clientX:20,clientY:350}); const end = new Touch({identifier:3,target:stage,clientX:160,clientY:355}); stage.dispatchEvent(new TouchEvent('touchstart',{bubbles:true,touches:[begin]})); stage.dispatchEvent(new TouchEvent('touchend',{bubbles:true,changedTouches:[end]})); })()`);
  await new Promise(resolve => setTimeout(resolve, 220));
  const edgeClosedViewer = await evaluate(`document.querySelector('#viewer').classList.contains('hidden')`);
  await evaluate(`document.querySelector('.story-card').click()`);
  await evaluate(`(() => { const stage = document.querySelector('.viewer-stage'); const begin = new Touch({identifier:2,target:stage,clientX:150,clientY:250}); const end = new Touch({identifier:2,target:stage,clientX:155,clientY:420}); stage.dispatchEvent(new TouchEvent('touchstart',{bubbles:true,touches:[begin]})); stage.dispatchEvent(new TouchEvent('touchend',{bubbles:true,changedTouches:[end]})); })()`);
  await new Promise(resolve => setTimeout(resolve, 220));
  const swipeClosedViewer = await evaluate(`document.querySelector('#viewer').classList.contains('hidden')`);
  await evaluate(`document.querySelector('[data-tab="Collections"]').click()`);
  const collections = await evaluate(`document.querySelectorAll('.collection-card').length`);
  const collectionsShot = await command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  writeFileSync(`.tools/mobile-collections-${viewportWidth}.png`, Buffer.from(collectionsShot.data, 'base64'));
  await evaluate(`document.querySelector('[data-tab="Search"]').click()`);
  const search = await evaluate(`JSON.stringify({input:!!document.querySelector('.search-input'),count:document.querySelectorAll('.photo-tile').length})`);
  const searchShot = await command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  writeFileSync(`.tools/mobile-search-${viewportWidth}.png`, Buffer.from(searchShot.data, 'base64'));
  await evaluate(`document.querySelector('#settings-button').click()`);
  const settings = await evaluate(`!document.querySelector('#settings').classList.contains('hidden')`);
  let chosenSource = null;
  let cloudResult = null;
  if (process.env.GALLERY_MOCK_TAURI === '1') {
    await evaluate(`document.querySelector('#source-choose').click()`);
    await sleep(100);
    chosenSource = await evaluate(`localStorage.getItem('gallery.sourcePath')`);
    await evaluate(`(() => {
      document.querySelector('#cloud-bucket').value='test-gallery-bucket';
      document.querySelector('#cloud-region').value='ap-southeast-2';
      document.querySelector('#cloud-key').value='EXAMPLEKEY1234';
      document.querySelector('#cloud-secret').value='not-a-real-secret';
      document.querySelector('#cloud-form').requestSubmit();
    })()`);
    await sleep(100);
    const saved = JSON.parse(await evaluate(`JSON.stringify({state:document.querySelector('#cloud-state').textContent, key:document.querySelector('#cloud-key').value, secret:document.querySelector('#cloud-secret').value, secretReadonly:document.querySelector('#cloud-secret').readOnly, stored:Object.values(localStorage).some(value => value.includes('not-a-real-secret'))})`));
    await evaluate(`document.querySelector('#cloud-test').click()`);
    await sleep(100);
    const tested = await evaluate(`document.querySelector('#cloud-state').textContent`);
    await evaluate(`document.querySelector('#settings-close').click()`);
    await evaluate(`document.querySelectorAll('.photo-tile')[3].click(); document.querySelector('#viewer-info').click()`);
    const info = await evaluate(`document.querySelector('#viewer-details').textContent`);
    await evaluate(`document.querySelector('#viewer-details button').click()`);
    await sleep(100);
    await evaluate(`document.querySelector('#viewer-close').click()`);
    await evaluate(`(() => { const tile=document.querySelectorAll('.photo-tile')[4]; tile.scrollIntoView({block:'center'}); const rect=tile.getBoundingClientRect(); window.__hold={x:rect.left+rect.width/2,y:rect.top+rect.height/2}; tile.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,pointerType:'touch',pointerId:7,button:0,clientX:window.__hold.x,clientY:window.__hold.y})); })()`);
    await sleep(500);
    const afterHold = await evaluate(`document.querySelector('#selection-count').textContent`);
    await evaluate(`document.dispatchEvent(new PointerEvent('pointerup',{bubbles:true,pointerType:'touch',pointerId:7,button:0,clientX:window.__hold.x,clientY:window.__hold.y})); document.querySelectorAll('.photo-tile')[5].dispatchEvent(new PointerEvent('click',{bubbles:true,pointerType:'touch',button:0}));`);
    const afterTap = await evaluate(`document.querySelector('#selection-count').textContent`);
    const selectionShot = await command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
    writeFileSync(`.tools/mobile-selection-${viewportWidth}.png`, Buffer.from(selectionShot.data, 'base64'));
    await evaluate(`document.querySelector('#selection-backup').click()`);
    await sleep(100);
    const selectedSyncCalls = JSON.parse(await evaluate(`JSON.stringify(window.__selectedSyncCalls.map(ids => ids.length))`));
    const selectionCleared = await evaluate(`document.querySelector('#selection-bar').classList.contains('hidden')`);
    await evaluate(`(() => { const tile=document.querySelectorAll('.photo-tile')[10]; tile.scrollIntoView({block:'center'}); const r=tile.getBoundingClientRect(); window.__dragStart={x:r.left+r.width/2,y:r.top+r.height/2}; tile.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,pointerType:'touch',pointerId:11,button:0,clientX:window.__dragStart.x,clientY:window.__dragStart.y})); })()`);
    await sleep(500);
    const dragRange = JSON.parse(await evaluate(`(() => { const tiles=[...document.querySelectorAll('.photo-tile')]; const visible=tiles.map((tile,index)=>({tile,index,rect:tile.getBoundingClientRect()})).filter(item=>item.rect.top>70&&item.rect.bottom<innerHeight-110); const end=visible[visible.length-1]; document.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,pointerType:'touch',pointerId:11,button:0,clientX:end.rect.left+end.rect.width/2,clientY:end.rect.top+end.rect.height/2})); const selected=tiles.map((tile,index)=>tile.getAttribute('aria-pressed')==='true'?index:-1).filter(index=>index>=0); document.dispatchEvent(new PointerEvent('pointerup',{bubbles:true,pointerType:'touch',pointerId:11,button:0,clientX:end.rect.left+end.rect.width/2,clientY:end.rect.top+end.rect.height/2})); return JSON.stringify({from:10,to:end.index,selected,complete:Array.from({length:Math.abs(end.index-10)+1},(_,offset)=>Math.min(10,end.index)+offset).every(index=>selected.includes(index))}); })()`));
    await evaluate(`(() => { const tile=document.querySelectorAll('.photo-tile')[12]; tile.scrollIntoView({block:'center'}); const r=tile.getBoundingClientRect(); window.__edgeBefore=scrollY; tile.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,pointerType:'touch',pointerId:12,button:0,clientX:r.left+r.width/2,clientY:r.top+r.height/2})); document.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,pointerType:'touch',pointerId:12,button:0,clientX:r.left+r.width/2,clientY:innerHeight-5})); })()`);
    await sleep(240);
    const edgeScrolled = await evaluate(`scrollY > window.__edgeBefore`);
    await evaluate(`document.dispatchEvent(new PointerEvent('pointerup',{bubbles:true,pointerType:'touch',pointerId:12,button:0,clientX:100,clientY:innerHeight-5})); document.querySelector('#selection-cancel').click()`);
    await sleep(200);
    const desktop = JSON.parse(await evaluate(`(() => { const tiles=document.querySelectorAll('.photo-tile'); const click=(index,options)=>{const tile=tiles[index]; const opts={bubbles:true,pointerType:'mouse',pointerId:30+index,button:0,...options}; tile.dispatchEvent(new PointerEvent('pointerdown',opts)); tile.dispatchEvent(new PointerEvent('pointerup',opts)); tile.dispatchEvent(new PointerEvent('click',opts));}; click(10,{ctrlKey:true}); click(13,{ctrlKey:true}); const additive=document.querySelector('#selection-count').textContent; click(16,{shiftKey:true}); const range=[10,13,14,15,16].every(index=>tiles[index].getAttribute('aria-pressed')==='true'); const rangeCount=document.querySelector('#selection-count').textContent; click(17,{metaKey:true}); const macAdditive=document.querySelector('#selection-count').textContent; click(18,{}); const opened=!document.querySelector('#viewer').classList.contains('hidden'); const cleared=document.querySelector('#selection-bar').classList.contains('hidden'); document.querySelector('#viewer-close').click(); return JSON.stringify({additive,range,rangeCount,macAdditive,opened,cleared}); })()`));
    await evaluate(`(() => { const tile=document.querySelectorAll('.photo-tile')[19]; tile.scrollIntoView({block:'center'}); const r=tile.getBoundingClientRect(); window.__mouseHold={x:r.left+r.width/2,y:r.top+r.height/2}; tile.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,pointerType:'mouse',pointerId:60,button:0,clientX:window.__mouseHold.x,clientY:window.__mouseHold.y})); })()`);
    await sleep(500);
    const desktopHold = await evaluate(`document.querySelector('#selection-count').textContent`);
    await evaluate(`(() => { const tile=document.querySelectorAll('.photo-tile')[19]; const opts={bubbles:true,pointerType:'mouse',pointerId:60,button:0,clientX:window.__mouseHold.x,clientY:window.__mouseHold.y}; tile.dispatchEvent(new PointerEvent('pointerup',opts)); tile.dispatchEvent(new PointerEvent('click',opts)); document.querySelector('#selection-cancel').click(); })()`);
    const touchStart = JSON.parse(await evaluate(`(() => { const tile=document.querySelectorAll('.photo-tile')[20]; tile.scrollIntoView({block:'center'}); const r=tile.getBoundingClientRect(); return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2,before:scrollY}); })()`));
    await command('Input.dispatchTouchEvent', { type:'touchStart', touchPoints:[{x:touchStart.x,y:touchStart.y,id:21}] });
    await command('Input.dispatchTouchEvent', { type:'touchMove', touchPoints:[{x:touchStart.x,y:touchStart.y-140,id:21}] });
    await sleep(120);
    await command('Input.dispatchTouchEvent', { type:'touchEnd', touchPoints:[] });
    const normalTouchScrolled = await evaluate(`scrollY > ${touchStart.before} && document.querySelector('#selection-bar').classList.contains('hidden')`);
    const touchDrag = JSON.parse(await evaluate(`(() => { const tiles=[...document.querySelectorAll('.photo-tile')]; const tile=tiles[20]; tile.scrollIntoView({block:'center'}); const rect=tile.getBoundingClientRect(); const visible=tiles.map((item,index)=>({index,rect:item.getBoundingClientRect()})).filter(item=>item.rect.top>70&&item.rect.bottom<innerHeight-110&&item.index>20); const end=visible[Math.min(3,visible.length-1)]; return JSON.stringify({start:{x:rect.left+rect.width/2,y:rect.top+rect.height/2},end:{x:end.rect.left+end.rect.width/2,y:end.rect.top+end.rect.height/2},to:end.index,before:scrollY}); })()`));
    await command('Input.dispatchTouchEvent', { type:'touchStart', touchPoints:[{x:touchDrag.start.x,y:touchDrag.start.y,id:22}] });
    await sleep(520);
    await command('Input.dispatchTouchEvent', { type:'touchMove', touchPoints:[{x:touchDrag.end.x,y:touchDrag.end.y,id:22}] });
    await sleep(100);
    const realTouchRange = await evaluate(`document.querySelector('#selection-count').textContent`);
    await command('Input.dispatchTouchEvent', { type:'touchEnd', touchPoints:[] });
    await sleep(150);
    const tap = JSON.parse(await evaluate(`(() => { const tile=document.querySelectorAll('.photo-tile')[30]; tile.scrollIntoView({block:'center'}); const r=tile.getBoundingClientRect(); return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2}); })()`));
    await command('Input.dispatchTouchEvent', { type:'touchStart', touchPoints:[{x:tap.x,y:tap.y,id:23}] });
    await command('Input.dispatchTouchEvent', { type:'touchEnd', touchPoints:[] });
    const realTouchTap = await evaluate(`document.querySelector('#selection-count').textContent`);
    await evaluate(`document.querySelector('#selection-cancel').click()`);
    await evaluate(`document.querySelector('#settings-button').click()`);
    const syncVisible = await evaluate(`!document.querySelector('#sync-start').classList.contains('hidden')`);
    await evaluate(`document.querySelector('#sync-start').click()`);
    await sleep(100);
    const syncText = await evaluate(`document.querySelector('#sync-progress').textContent`);
    const cancelLabel = await evaluate(`document.querySelector('#sync-start').textContent`);
    await evaluate(`document.querySelector('.settings-card').scrollTop = document.querySelector('.settings-card').scrollHeight`);
    const syncShot = await command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
    writeFileSync(`.tools/mobile-sync-${viewportWidth}.png`, Buffer.from(syncShot.data, 'base64'));
    await evaluate(`document.querySelector('#sync-start').click()`);
    await sleep(100);
    const cancelledText = await evaluate(`document.querySelector('#sync-progress').textContent`);
    const resumeLabel = await evaluate(`document.querySelector('#sync-start').textContent`);
    await evaluate(`document.querySelector('#cloud-edit').click()`);
    const replacing = JSON.parse(await evaluate(`JSON.stringify({key:document.querySelector('#cloud-key').value,secret:document.querySelector('#cloud-secret').value})`));
    await evaluate(`document.querySelector('#cloud-edit').click()`);
    await evaluate(`document.querySelector('#cloud-remove').click()`);
    await sleep(100);
    const removed = await evaluate(`document.querySelector('#cloud-state').textContent`);
    cloudResult = { saved, tested, info, afterHold, afterTap, selectedSyncCalls, selectionCleared, dragRange, edgeScrolled, desktop, desktopHold, normalTouchScrolled, realTouchRange, realTouchExpected: touchDrag.to - 20 + 1, realTouchTap, syncVisible, syncText, cancelLabel, cancelledText, resumeLabel, replacing, removed };
  }
  console.log('interactions', JSON.stringify({ memoryTitle, swipedTitle, viewer: JSON.parse(viewer), favorite, edgeClosedViewer, swipeClosedViewer, collections, search: JSON.parse(search), settings, chosenSource, cloudResult }));
  console.log('exceptions', JSON.stringify(exceptions));
  ws.close();
  if (exceptions.length || initialCount !== 0 || loadedCount !== 111 || page.viewport !== viewportWidth || page.width !== viewportWidth || grid.before !== 5 || grid.zoomed !== 4 || !grid.placeholderHidden || justified.mode !== 'flex' || justified.rows < 2 || !justified.filled || !justified.sameHeight || timeline.grids !== 1 || timeline.dateHeadings !== 0 || !timeline.chronological || visual.background !== 'rgb(21, 24, 27)' || visual.stories !== 2 || visual.storyHeading !== 0 || visual.navBackground !== 'rgba(0, 0, 0, 0)' || !visual.syncedBadgeHidden || memoryTitle === swipedTitle || !edgeClosedViewer || !swipeClosedViewer || collections < 1 || !settings || (process.env.GALLERY_MOCK_TAURI === '1' && (syncBadges !== 111 || chosenSource !== String.raw`I:\Photos\Best of Poe 2` || !cloudResult.saved.state.includes('••••1234') || cloudResult.saved.key !== '••••1234' || !cloudResult.saved.secretReadonly || cloudResult.saved.secret.includes('not-a-real-secret') || cloudResult.saved.stored || !cloudResult.tested.includes('S3 access verified') || !cloudResult.info.includes('Not backed up') || cloudResult.afterHold !== '1 selected' || cloudResult.afterTap !== '2 selected' || JSON.stringify(cloudResult.selectedSyncCalls) !== '[1,2]' || !cloudResult.selectionCleared || !cloudResult.syncVisible || !cloudResult.syncText.includes('Uploading') || cloudResult.replacing.key !== '' || cloudResult.replacing.secret !== '' || cloudResult.removed !== 'No S3 connection saved'))) process.exitCode = 1;
  if (cloudResult && (cloudResult.cancelLabel !== 'Cancel sync' || !cloudResult.cancelledText.includes('Backup stopped') || cloudResult.resumeLabel !== 'Sync now')) process.exitCode = 1;
  if (cloudResult && (!cloudResult.dragRange.complete || cloudResult.dragRange.selected.length < 2 || !cloudResult.edgeScrolled || cloudResult.desktop.additive !== '2 selected' || !cloudResult.desktop.range || cloudResult.desktop.rangeCount !== '5 selected' || cloudResult.desktop.macAdditive !== '6 selected' || !cloudResult.desktop.opened || !cloudResult.desktop.cleared || cloudResult.desktopHold !== '1 selected' || !cloudResult.normalTouchScrolled || cloudResult.realTouchRange !== `${cloudResult.realTouchExpected} selected` || cloudResult.realTouchTap !== `${cloudResult.realTouchExpected + 1} selected`)) process.exitCode = 1;
} finally {
  server.kill();
  chrome.kill();
}
