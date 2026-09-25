import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const root = resolve(import.meta.dirname, '..');
const temp = mkdtempSync(join(tmpdir(), 'gallery-smoke-'));
const safeParent = realpathSync(tmpdir());
if (!realpathSync(temp).startsWith(safeParent + sep)) throw new Error('Temporary test path escaped the temp directory');
let child;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function digest(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

async function freePort() {
  const probe = createServer();
  await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  return port;
}

async function request(base, path, method = 'GET', body) {
  const response = await fetch(base + path, {
    method,
    headers: body ? {'Content-Type': 'application/json'} : undefined,
    body: body ? JSON.stringify(body) : undefined
  });
  assert(response.ok, `${path} returned ${response.status}`);
  return response.json();
}

try {
  const source = join(temp, 'photos');
  mkdirSync(source);
  const first = join(source, 'one.jpg');
  const second = join(source, 'two.jpg');
  writeFileSync(first, 'one image');
  writeFileSync(second, 'two image');
  writeFileSync(join(source, 'copy.jpg'), 'one image');
  writeFileSync(join(source, 'one.jpg.supplemental-metadata.json'), JSON.stringify({
    photoTakenTime: {timestamp: '1585452449'},
    description: 'Poe at home',
    geoDataExif: {latitude: -33.87, longitude: 151.18, altitude: 34.8},
    favorited: true
  }));
  const before = digest(first);

  const dbPath = join(temp, 'old.sqlite');
  const old = new DatabaseSync(dbPath);
  old.exec('CREATE TABLE assets (id TEXT PRIMARY KEY, filename TEXT NOT NULL, path TEXT NOT NULL, taken_at TEXT NOT NULL, collection TEXT NOT NULL, favorite INTEGER NOT NULL DEFAULT 0, imported_at TEXT NOT NULL)');
  old.prepare('INSERT INTO assets (id, filename, path, taken_at, collection, favorite, imported_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .run(before, 'copy.jpg', join(source, 'missing.jpg'), '2025-01-01T00:00:00.000Z', 'photos', 0, '2025-01-01T00:00:00.000Z');
  old.close();

  const port = await freePort();
  let stderr = '';
  child = spawn(process.execPath, [join(root, 'server.mjs')], {
    cwd: root,
    env: {...process.env, GALLERY_SOURCE: source, GALLERY_DB: dbPath, PORT: String(port)},
    stdio: ['ignore', 'ignore', 'pipe'],
    windowsHide: true
  });
  child.stderr.on('data', chunk => { stderr += chunk.toString(); });
  const base = `http://127.0.0.1:${port}`;
  let ready = false;
  for (let attempt = 0; attempt < 50; attempt++) {
    if (child.exitCode != null) throw new Error(`Server exited: ${stderr}`);
    try {
      await request(base, '/api/assets');
      ready = true;
      break;
    } catch {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }
  assert(ready, `Server did not start: ${stderr}`);

  const firstImport = await request(base, '/api/import', 'POST');
  assert(firstImport.scanned === 3 && firstImport.added === 1 && firstImport.existing === 2 && firstImport.errors.length === 0, `Unexpected first import: ${JSON.stringify(firstImport)}`);
  const assets = await request(base, '/api/assets');
  assert(assets.length === 2, 'Duplicate content was not deduplicated');
  const photo = assets.find(asset => asset.id === before);
  assert(photo?.description === 'Poe at home', 'Takeout description missing');
  assert(photo?.latitude === -33.87 && photo?.longitude === 151.18 && photo?.altitude === 34.8, 'Takeout location missing');
  assert(photo?.favorite === true && photo?.takenAt.startsWith('2020-03-29'), `Takeout date or favourite missing: ${JSON.stringify(photo)}`);
  const media = await fetch(`${base}/api/media/${photo.id}`);
  assert(media.ok && (await media.text()) === 'one image', 'Reimport did not repair a missing media path');

  await request(base, `/api/assets/${photo.id}/favorite`, 'POST', {favorite: false});
  const secondImport = await request(base, '/api/import', 'POST');
  assert(secondImport.added === 0 && secondImport.existing === 3, 'Repeat import was not idempotent');
  const after = await request(base, '/api/assets');
  assert(after.find(asset => asset.id === photo.id)?.favorite === false, 'Repeat import overwrote the user favourite');
  assert(digest(first) === before, 'Import changed a source photo');

  console.log('Browser smoke passed: old-schema migration, Takeout metadata, deduplication, reimport, favourite preservation, read-only source');
} finally {
  if (child && child.exitCode == null) {
    child.kill();
    await new Promise(resolve => child.once('exit', resolve));
  }
  rmSync(temp, {recursive: true, force: true});
}
