import { createServer } from 'node:http';
import { createReadStream, existsSync, mkdirSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, resolve, basename, extname, sep } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const root = resolve(import.meta.dirname);
const webRoot = join(root, 'web');
const source = resolve(process.env.GALLERY_SOURCE || 'I:\\Photos\\Best of Poe 2');
const dataRoot = join(root, 'data');
mkdirSync(dataRoot, { recursive: true });
const dbPath = process.env.GALLERY_DB === ':memory:' ? ':memory:' : resolve(process.env.GALLERY_DB || join(dataRoot, 'best-of-poe.sqlite'));
const db = new DatabaseSync(dbPath);
db.exec(`
  PRAGMA journal_mode=WAL;
  CREATE TABLE IF NOT EXISTS assets (
    id TEXT PRIMARY KEY,
    filename TEXT NOT NULL,
    path TEXT NOT NULL,
    taken_at TEXT NOT NULL,
    collection TEXT NOT NULL,
    favorite INTEGER NOT NULL DEFAULT 0,
    favorite_modified INTEGER NOT NULL DEFAULT 0,
    taken_at_source INTEGER NOT NULL DEFAULT 0,
    imported_at TEXT NOT NULL,
    description TEXT,
    latitude REAL,
    longitude REAL,
    altitude REAL
  );
`);
const columns = new Set(db.prepare('PRAGMA table_info(assets)').all().map(row => row.name));
for (const [name, type] of [['description', 'TEXT'], ['latitude', 'REAL'], ['longitude', 'REAL'], ['altitude', 'REAL'], ['favorite_modified', 'INTEGER NOT NULL DEFAULT 0'], ['taken_at_source', 'INTEGER NOT NULL DEFAULT 0']]) {
  if (!columns.has(name)) db.exec(`ALTER TABLE assets ADD COLUMN ${name} ${type}`);
}

const listAssets = db.prepare('SELECT id, filename, taken_at AS takenAt, collection, favorite, description, latitude, longitude, altitude FROM assets ORDER BY taken_at DESC, filename');
const getAsset = db.prepare('SELECT * FROM assets WHERE id = ?');
const insertAsset = db.prepare('INSERT OR IGNORE INTO assets (id, filename, path, taken_at, collection, imported_at, favorite, favorite_modified, taken_at_source, description, latitude, longitude, altitude) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?)');
const updateMetadata = db.prepare(`UPDATE assets SET
  taken_at = CASE WHEN taken_at_source = 0 AND ? IS NOT NULL THEN ? ELSE taken_at END,
  taken_at_source = CASE WHEN ? IS NOT NULL THEN 1 ELSE taken_at_source END,
  favorite = CASE WHEN favorite_modified = 0 AND ? = 1 THEN 1 ELSE favorite END,
  description = COALESCE(description, ?), latitude = COALESCE(latitude, ?),
  longitude = COALESCE(longitude, ?), altitude = COALESCE(altitude, ?), path = ?
  WHERE id = ?`);
const updateFavorite = db.prepare('UPDATE assets SET favorite = ?, favorite_modified = 1 WHERE id = ?');

function assetJson(row) {
  return {
    id: row.id,
    filename: row.filename,
    takenAt: row.takenAt,
    collection: row.collection,
    favorite: Boolean(row.favorite),
    mediaUrl: `/api/media/${row.id}`,
    description: row.description,
    latitude: row.latitude,
    longitude: row.longitude,
    altitude: row.altitude
  };
}

function metadataFor(directory) {
  const result = new Map();
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (!entry.isFile()) continue;
    const match = /^(.*)\.supplemental-metadata(?:\((\d+)\))?\.json$/i.exec(entry.name);
    if (!match) continue;
    const original = match[1];
    const extension = extname(original);
    const mediaName = match[2]
      ? `${original.slice(0, -extension.length)}(${match[2]})${extension}`
      : original;
    try {
      result.set(mediaName.toLowerCase(), JSON.parse(readFileSync(join(directory, entry.name), 'utf8')));
    } catch (error) {
      console.warn(`Invalid sidecar ${entry.name}: ${error.message}`);
    }
  }
  return result;
}

function importSource() {
  if (!existsSync(source)) throw new Error(`Import source is missing: ${source}`);
  const sidecars = metadataFor(source);
  const files = readdirSync(source, { withFileTypes: true })
    .filter(entry => entry.isFile() && /\.(jpe?g|png|webp|heic|gif)$/i.test(entry.name));
  const result = { scanned: files.length, added: 0, existing: 0, errors: [] };
  db.exec('BEGIN');
  try {
    for (const file of files) {
      try {
        const path = join(source, file.name);
        const id = createHash('sha256').update(readFileSync(path)).digest('hex');
        const sidecar = sidecars.get(file.name.toLowerCase());
        const location = sidecar?.geoDataExif || sidecar?.geoData;
        const description = sidecar?.description || null;
        const latitude = Number.isFinite(location?.latitude) ? location.latitude : null;
        const longitude = Number.isFinite(location?.longitude) ? location.longitude : null;
        const altitude = Number.isFinite(location?.altitude) ? location.altitude : null;
        const unixTime = Number(sidecar?.photoTakenTime?.timestamp);
        const hasSidecarDate = Number.isFinite(unixTime) && unixTime > 0;
        const takenAt = hasSidecarDate
          ? new Date(unixTime * 1000).toISOString()
          : statSync(path).mtime.toISOString();
        const run = insertAsset.run(id, file.name, path, takenAt, basename(source), new Date().toISOString(), sidecar?.favorited === true ? 1 : 0, hasSidecarDate ? 1 : 0, description, latitude, longitude, altitude);
        if (run.changes > 0) result.added++;
        else {
          const sidecarDate = hasSidecarDate ? takenAt : null;
          const stored = getAsset.get(id);
          const mediaPath = existsSync(stored.path) ? stored.path : path;
          updateMetadata.run(sidecarDate, sidecarDate, sidecarDate, sidecar?.favorited === true ? 1 : 0, description, latitude, longitude, altitude, mediaPath, id);
          result.existing++;
        }
      } catch (error) {
        result.errors.push(`${file.name}: ${error.message}`);
      }
    }
    db.exec('COMMIT');
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
  return result;
}

function json(response, status, value) {
  const body = JSON.stringify(value);
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store'
  });
  response.end(body);
}

async function readJson(request) {
  let body = '';
  for await (const chunk of request) {
    body += chunk;
    if (body.length > 1024 * 1024) throw new Error('Request too large');
  }
  return JSON.parse(body || '{}');
}

function serveFile(response, path, type, cacheControl = 'private, max-age=3600') {
  const length = statSync(path).size;
  response.writeHead(200, { 'Content-Type': type, 'Content-Length': length, 'Cache-Control': cacheControl });
  createReadStream(path).pipe(response);
}

const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.heic': 'image/heic', '.gif': 'image/gif' };

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://127.0.0.1');
    const pathname = decodeURIComponent(url.pathname);
    if (pathname === '/api/assets' && request.method === 'GET') {
      return json(response, 200, listAssets.all().map(assetJson));
    }
    if (pathname === '/api/settings' && request.method === 'GET') {
      return json(response, 200, { source });
    }
    if (pathname === '/api/import' && request.method === 'POST') {
      return json(response, 200, importSource());
    }
    const media = /^\/api\/media\/([a-f0-9]{64})$/.exec(pathname);
    if (media && request.method === 'GET') {
      const asset = getAsset.get(media[1]);
      if (!asset || !existsSync(asset.path)) return json(response, 404, { error: 'Photo not found' });
      return serveFile(response, asset.path, types[extname(asset.path).toLowerCase()] || 'application/octet-stream');
    }
    const favorite = /^\/api\/assets\/([a-f0-9]{64})\/favorite$/.exec(pathname);
    if (favorite && request.method === 'POST') {
      const input = await readJson(request);
      if (typeof input.favorite !== 'boolean') return json(response, 400, { error: 'favorite must be a boolean' });
      if (!getAsset.get(favorite[1])) return json(response, 404, { error: 'Photo not found' });
      updateFavorite.run(input.favorite ? 1 : 0, favorite[1]);
      return json(response, 200, assetJson(getAsset.get(favorite[1])));
    }
    if (request.method !== 'GET') return json(response, 405, { error: 'Method not allowed' });
    const filePath = resolve(webRoot, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!filePath.startsWith(webRoot + sep) || !existsSync(filePath) || !statSync(filePath).isFile()) return json(response, 404, { error: 'Not found' });
    return serveFile(response, filePath, types[extname(filePath)] || 'application/octet-stream', 'no-store');
  } catch (error) {
    console.error(error);
    return json(response, 500, { error: error.message });
  }
});

const port = Number(process.env.PORT || 4173);
server.listen(port, '127.0.0.1', () => console.log(`Gallery prototype: http://127.0.0.1:${port}`));
