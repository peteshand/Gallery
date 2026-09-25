import { spawn } from 'node:child_process';

const root = process.cwd();
const browser = process.env.GALLERY_BROWSER_BIN || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const port = 43193;
const debugPort = 49247;
const server = spawn(process.execPath, ['server.mjs'], {
  cwd: root, windowsHide: true, env: { ...process.env, PORT: String(port), GALLERY_DB: ':memory:' }, stdio: 'ignore'
});
const chrome = spawn(browser, ['--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
  `--remote-debugging-port=${debugPort}`, `--user-data-dir=${root}\\.tools\\android-cdp`, 'about:blank'],
  { cwd: root, windowsHide: true, stdio: 'ignore' });
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function retry(action) {
  for (let attempt = 0; attempt < 60; attempt++) {
    try { return await action(); } catch { await sleep(250); }
  }
  throw Error('Headless browser did not start');
}
try {
  await retry(async () => { if (!(await fetch(`http://127.0.0.1:${port}/api/assets`)).ok) throw Error(); });
  const target = await retry(async () => {
    const pages = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
    return pages.find(page => page.type === 'page' && page.webSocketDebuggerUrl) || Promise.reject(Error());
  });
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let nextId = 1;
  const pending = new Map();
  const exceptions = [];
  socket.onmessage = event => {
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
    return new Promise((resolve, reject) => { pending.set(id, { resolve, reject }); socket.send(JSON.stringify({ id, method, params })); });
  }
  await command('Runtime.enable');
  await command('Page.enable');
  await command('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
  await command('Page.addScriptToEvaluateOnNewDocument', { source: `
    Object.defineProperty(navigator, 'userAgent', {get:()=> 'Mozilla/5.0 (Linux; Android 16; Pixel) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36'});
    window.__mockPhone = {access:'none',count:0,preferences:{autoBackup:false,wifiOnly:true,backgroundBackup:false}};
    window.__TAURI__ = {
      core: {invoke: async (command,args) => {
        if (command === 'list_assets') return window.__mockPhone.count ? [
          {id:'phone-1',filename:'Camera one.jpg',takenAt:'2026-09-22T10:00:00Z',collection:'On this phone / Camera',favorite:false,mediaUrl:'',thumbnailUrl:null,description:null,latitude:null,longitude:null,altitude:null,syncState:'not_synced',syncedAt:null,syncError:null},
          {id:'phone-2',filename:'WhatsApp image.jpg',takenAt:'2026-09-21T10:00:00Z',collection:'On this phone / WhatsApp',favorite:false,mediaUrl:'',thumbnailUrl:null,description:null,latitude:null,longitude:null,altitude:null,syncState:'not_synced',syncedAt:null,syncError:null}
        ] : [];
        if (command === 'get_phone_status') return {access:window.__mockPhone.access,count:window.__mockPhone.count};
        if (command === 'request_phone_access') {window.__mockPhone.access=window.__mockPhone.access==='selected'?'full':'selected';return {access:window.__mockPhone.access,count:0};}
        if (command === 'refresh_phone_media') {window.__mockPhone.count=2;return {access:window.__mockPhone.access,found:2,added:2};}
        if (command === 'get_backup_preferences') return window.__mockPhone.preferences;
        if (command === 'set_backup_preferences') {
          if (args.preferences.autoBackup && window.__mockPhone.access!=='full') throw Error('Allow access to all phone photos before enabling automatic backup');
          window.__mockPhone.preferences=args.preferences;return args.preferences;
        }
        if (command === 'ensure_media') return 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==';
        if (command === 'get_default_source') return null;
        if (command === 'get_s3_connection') return {configured:false,credentialsAvailable:false,bucket:'',region:'',endpoint:'',prefix:'',maskedKeyId:'',lastVerifiedAt:null};
        if (command === 'get_cache_status') return {usedBytes:0,limitBytes:2147483648,itemCount:0};
        if (command === 'get_sync_status') return {running:false,cancelling:false,cancelled:false,total:0,notSynced:0,preparing:0,uploading:0,synced:0,failed:0,currentName:null,lastError:null};
        throw Error('Unexpected native call: ' + command);
      }, convertFileSrc:path=>path}, dialog:{}
    };
  ` });
  await command('Page.navigate', { url: `http://127.0.0.1:${port}/` });
  await sleep(900);
  async function evaluate(expression) {
    const result = await command('Runtime.evaluate', { expression, returnByValue: true });
    if (result.exceptionDetails) throw Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
    return result.result.value;
  }
  const state = JSON.parse(await evaluate(`JSON.stringify({message:document.querySelector('.empty-state p')?.textContent,button:document.querySelector('.empty-state button')?.textContent,topImportHidden:document.querySelector('#import-button')?.classList.contains('hidden'),viewerAndroidInset:document.querySelector('#viewer')?.classList.contains('viewer-android'),viewerTopPadding:parseFloat(getComputedStyle(document.querySelector('#viewer')).paddingTop),galleryTopPadding:parseFloat(getComputedStyle(document.querySelector('.shell')).paddingTop),darkBackground:getComputedStyle(document.querySelector('.shell')).backgroundColor})`));
  await evaluate(`document.querySelector('.empty-state button').click()`);
  state.settingsOpened = await evaluate(`!document.querySelector('#settings').classList.contains('hidden')`);
  state.folderHidden = await evaluate(`document.querySelector('#source-choose').classList.contains('hidden')`);
  state.settingsTopPadding = await evaluate(`parseFloat(getComputedStyle(document.querySelector('.settings-card')).paddingTop)`);
  state.phoneSection = await evaluate(`!document.querySelector('.phone-source').classList.contains('hidden')`);
  state.backupDefaults = JSON.parse(await evaluate(`JSON.stringify({auto:document.querySelector('#phone-auto-backup').checked,wifi:document.querySelector('#phone-wifi-only').checked,background:document.querySelector('#phone-background-backup').checked})`));
  await evaluate(`document.querySelector('#phone-access').click()`);
  await sleep(400);
  state.phoneAccess = await evaluate(`document.querySelector('#phone-source-state').textContent`);
  state.phoneTiles = await evaluate(`document.querySelectorAll('.photo-tile').length`);
  await evaluate(`document.querySelector('[data-tab="Collections"]').click()`);
  await sleep(200);
  state.phoneCollection = await evaluate(`!!document.querySelector('[data-collection="On this phone"]')`);
  await evaluate(`document.querySelector('[data-collection="On this phone"]').click()`);
  state.phoneFolders = JSON.parse(await evaluate(`JSON.stringify([...document.querySelectorAll('.collection-card strong')].map(item=>item.textContent))`));
  await evaluate(`document.querySelector('[data-collection="On this phone / WhatsApp"]').click()`);
  state.whatsAppTiles = await evaluate(`document.querySelectorAll('.photo-tile').length`);
  await evaluate(`document.querySelector('#phone-auto-backup').click();document.querySelector('#phone-backup-save').click()`);
  await sleep(200);
  state.selectedAutoRejected = await evaluate(`document.querySelector('#phone-source-message').textContent.includes('Allow access to all phone photos') && !window.__mockPhone.preferences.autoBackup`);
  await evaluate(`document.querySelector('#phone-access').click()`);
  await sleep(200);
  state.fullAccess = await evaluate(`document.querySelector('#phone-source-state').textContent.includes('All phone photos available')`);
  await evaluate(`document.querySelector('#phone-auto-backup').checked=true;document.querySelector('#phone-backup-save').click()`);
  await sleep(200);
  state.autoSaved = await evaluate(`window.__mockPhone.preferences.autoBackup && window.__mockPhone.preferences.wifiOnly && !window.__mockPhone.preferences.backgroundBackup`);
  await evaluate(`document.querySelector('#phone-background-backup').click();document.querySelector('#phone-backup-save').click()`);
  await sleep(200);
  state.backgroundSaved = await evaluate(`window.__mockPhone.preferences.backgroundBackup`);
  console.log(JSON.stringify({ state, exceptions }));
  socket.close();
  if (!state.message?.includes('Connect cloud storage') || state.button !== 'Open settings' || !state.topImportHidden || !state.settingsOpened || !state.folderHidden || !state.viewerAndroidInset || state.viewerTopPadding < 32 || state.galleryTopPadding < 32 || state.darkBackground !== 'rgb(21, 24, 27)' || state.settingsTopPadding < 52 || !state.phoneSection || state.backupDefaults.auto || !state.backupDefaults.wifi || state.backupDefaults.background || !state.phoneAccess.includes('Selected phone photos') || state.phoneTiles !== 1 || !state.phoneCollection || !state.phoneFolders.includes('Camera') || !state.phoneFolders.includes('WhatsApp') || state.whatsAppTiles !== 1 || !state.selectedAutoRejected || !state.fullAccess || !state.autoSaved || !state.backgroundSaved || exceptions.length) process.exitCode = 1;
} finally {
  server.kill();
  chrome.kill();
}
