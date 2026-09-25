import { spawn } from 'node:child_process';
import { browserExecutable, browserProfile, testSource } from './headless-browser.mjs';

const root = process.cwd();
const port = 43192;
const debugPort = 49246;
const browserBin = browserExecutable();
const sourceFolder = testSource();
const server = spawn(process.execPath, ['server.mjs'], {
  cwd: root, windowsHide: true,
  env: { ...process.env, PORT: String(port), GALLERY_DB: ':memory:', GALLERY_SOURCE: sourceFolder },
  stdio: ['ignore', 'pipe', 'pipe']
});
const chrome = spawn(browserBin, [
  '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run', '--no-default-browser-check',
  `--remote-debugging-port=${debugPort}`, `--user-data-dir=${browserProfile(root, 'remote-cdp')}`, 'about:blank'
], { cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function retry(fn) {
  for (let n = 0; n < 80; n++) {
    try { return await fn(); } catch { await sleep(250); }
  }
  throw Error('service did not start');
}
try {
  await retry(async () => { const response = await fetch(`http://127.0.0.1:${port}/api/assets`); if (!response.ok) throw Error(); });
  const imported = await fetch(`http://127.0.0.1:${port}/api/import`, { method: 'POST' });
  if (!imported.ok) throw Error(await imported.text());
  const assets = await (await fetch(`http://127.0.0.1:${port}/api/assets`)).json();
  if (assets.length !== 111) throw Error(`Expected 111 source photos, got ${assets.length}`);
  const pages = await retry(async () => (await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json()).filter(page => page.type === 'page'));
  const ws = new WebSocket(pages[0].webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  let nextId = 1;
  const pending = new Map();
  const exceptions = [];
  ws.onmessage = event => {
    const message = JSON.parse(event.data);
    if (message.method === 'Runtime.exceptionThrown') exceptions.push(message.params.exceptionDetails.exception?.description || message.params.exceptionDetails.text);
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
  async function evaluate(expression) {
    const result = await command('Runtime.evaluate', { expression, returnByValue: true });
    if (result.exceptionDetails) throw Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
    return result.result.value;
  }
  await command('Runtime.enable');
  await command('Page.enable');
  await command('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
  await command('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 1 });
  const bootstrap = `window.__mediaCalls=[]; window.__catalogRefreshes=0; window.__cacheLimit=2147483648;
    const assets=${JSON.stringify(assets)};
    window.__TAURI__={core:{convertFileSrc:path=>path,invoke:async(command,args={})=>{
      if(command==='list_assets') return assets.map(asset=>({...asset,mediaUrl:'',thumbnailUrl:null,syncState:'synced'}));
      if(command==='get_default_source') return null;
      if(command==='get_s3_connection') return {configured:true,credentialsAvailable:true,bucket:'test',region:'us-east-1',endpoint:'',prefix:'gallery/',maskedKeyId:'••••1234',lastVerifiedAt:1};
      if(command==='get_sync_status') return {running:false,cancelling:false,cancelled:false,total:0,notSynced:0,preparing:0,uploading:0,synced:0,failed:0,currentName:null,lastError:null};
      if(command==='refresh_remote'){window.__catalogRefreshes++;return {scanned:111,added:0,updated:0,unchanged:111,errors:[]};}
      if(command==='get_cache_status') return {limitBytes:window.__cacheLimit,usedBytes:0,itemCount:0};
      if(command==='set_cache_limit'){window.__cacheLimit=args.bytes;return {limitBytes:args.bytes,usedBytes:0,itemCount:0};}
      if(command==='ensure_media'){window.__mediaCalls.push({id:args.id,variant:args.variant});return assets.find(asset=>asset.id===args.id).mediaUrl;}
      if(command==='set_favorite') return assets.find(asset=>asset.id===args.id);
      throw Error('Unexpected native command '+command);
    }},dialog:{open:async()=>null}};`;
  await command('Page.addScriptToEvaluateOnNewDocument', { source: bootstrap });
  await command("Page.addScriptToEvaluateOnNewDocument", {source:"localStorage.removeItem('gallery.thumbnailOnly');"});
  await command('Page.navigate', { url: `http://127.0.0.1:${port}/` });
  await sleep(1200);
  const count = await evaluate(`document.querySelectorAll('.photo-tile').length`);
  const thumbnailCalls = await evaluate(`window.__mediaCalls.filter(call=>call.variant==='thumbnail').length`);
  if (count !== 111 || thumbnailCalls < 1 || thumbnailCalls >= 111) throw Error(`Lazy grid failed: ${count} tiles, ${thumbnailCalls} thumbnail calls`);
  await evaluate(`document.querySelector('.photo-tile').click()`);
  await sleep(300);
  const previewCalls = await evaluate(`window.__mediaCalls.filter(call=>call.variant==='preview').length`);
  if (previewCalls < 1) throw Error('Viewer did not request a preview');
  await evaluate(`document.querySelector('#viewer-close').click();document.querySelector('#settings-button').click()`);
  await sleep(100);
  const limit = await evaluate(`document.querySelector('#cache-limit').value`);
  await evaluate(`document.querySelector('#cache-limit').value='1';document.querySelector('#cache-save').click()`);
  await sleep(100);
  const savedLimit = await evaluate(`window.__cacheLimit`);
  if (Number(limit) !== 2 || Math.abs(savedLimit - 1073741824) > 1) throw Error('Cache setting did not persist in UI');
  const thumbnailDefault = await evaluate(`document.querySelector("#thumbnail-only").checked`);
  await evaluate(`document.querySelector("#thumbnail-only").click();document.querySelector("#settings-close").click();document.querySelectorAll(".photo-tile")[1].click()`);
  await sleep(300);
  const previewAfterThumbnailOnly = await evaluate(`window.__mediaCalls.filter(call=>call.variant==="preview").length`);
  const thumbnailOnlySaved = await evaluate(`localStorage.getItem("gallery.thumbnailOnly")`);
  if (thumbnailDefault || previewAfterThumbnailOnly !== previewCalls || thumbnailOnlySaved !== "true") throw Error("Thumbnail-only mode downloaded a preview or failed to persist");
  if (exceptions.length > 0) throw Error(exceptions.join('\n'));
  console.log(JSON.stringify({ tiles:count, thumbnailCalls, previewCalls, cacheGB:savedLimit/1073741824,
    catalogRefreshes:await evaluate(`window.__catalogRefreshes`) }));
} finally {
  chrome.kill();
  server.kill();
}
