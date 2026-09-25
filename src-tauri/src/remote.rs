use crate::{cloud, database, events, media_cache};
use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use serde_json::Value;
use std::{fs, io::{Read, Write}, path::{Path, PathBuf}, time::{SystemTime, UNIX_EPOCH}};
use sha2::{Digest, Sha256};
use tauri::{AppHandle, Manager};

const MAX_MANIFEST_BYTES: usize = 1024 * 1024;
const MAX_THUMBNAIL_BYTES: i64 = 16 * 1024 * 1024;
const MAX_PREVIEW_BYTES: i64 = 64 * 1024 * 1024;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteRefreshResult { pub scanned: usize, pub added: usize, pub updated: usize, pub unchanged: usize, pub errors: Vec<String> }

pub fn prepare(db: &Connection) -> Result<(), String> {
    db.execute_batch("CREATE TABLE IF NOT EXISTS remote_assets (
        asset_id TEXT PRIMARY KEY, original_key TEXT NOT NULL, original_bytes INTEGER NOT NULL,
        preview_key TEXT NOT NULL, preview_bytes INTEGER NOT NULL,
        thumbnail_key TEXT NOT NULL, thumbnail_bytes INTEGER NOT NULL, manifest_version INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS remote_manifest_etags (
        asset_id TEXT NOT NULL, target TEXT NOT NULL, etag TEXT NOT NULL,
        PRIMARY KEY(asset_id,target));")
        .map_err(|error| format!("Could not prepare cloud catalogue: {error}"))
}

fn listed_manifest_id<'a>(prefix: &str, key: &'a str) -> Option<&'a str> {
    let name = key.strip_prefix(prefix)?.strip_suffix(".json")?;
    valid_id(name).then_some(name)
}

fn manifest_target(config: &cloud::S3Config) -> String {
    serde_json::json!([&config.bucket, &config.region, &config.endpoint, &config.prefix]).to_string()
}

fn manifest_unchanged(db: &Connection, target: &str, id: &str, etag: Option<&str>) -> Result<bool, String> {
    let Some(etag) = etag.filter(|value| !value.is_empty()) else { return Ok(false) };
    let stored: Option<String> = db.query_row("SELECT etag FROM remote_manifest_etags
        WHERE asset_id=?1 AND target=?2
        AND EXISTS (SELECT 1 FROM remote_assets WHERE asset_id=?1)
        AND EXISTS (SELECT 1 FROM assets WHERE id=?1)",
        params![id,target], |row| row.get(0)).optional().map_err(|error| error.to_string())?;
    Ok(stored.as_deref() == Some(etag))
}

fn record_manifest_etag(db: &Connection, target: &str, id: &str, etag: Option<&str>) -> Result<(), String> {
    let Some(etag) = etag.filter(|value| !value.is_empty()) else { return Ok(()) };
    db.execute("INSERT INTO remote_manifest_etags(asset_id,target,etag) VALUES (?1,?2,?3)
        ON CONFLICT(asset_id,target) DO UPDATE SET etag=excluded.etag", params![id,target,etag])
        .map_err(|error| error.to_string())?;
    Ok(())
}

fn valid_id(id: &str) -> bool {
    id.len() == 64 && id.bytes().all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
}

fn field<'a>(value: &'a Value, name: &str) -> Result<&'a str, String> {
    value.get(name).and_then(Value::as_str).filter(|s| !s.is_empty())
        .ok_or_else(|| format!("Missing {name} in cloud manifest"))
}

fn media(value: &Value, name: &str, expected_key: &str) -> Result<(String, i64), String> {
    let part = value.get(name).ok_or_else(|| format!("Missing {name} in cloud manifest"))?;
    let key = field(part, "key")?;
    if key != expected_key { return Err(format!("Unexpected {name} object key")); }
    let bytes = part.get("bytes").and_then(Value::as_i64).filter(|bytes| *bytes > 0)
        .ok_or_else(|| format!("Invalid {name} size"))?;
    Ok((key.to_string(), bytes))
}

fn import_manifest(db: &Connection, prefix: &str, key: &str, bytes: &[u8]) -> Result<bool, String> {
    if bytes.len() > MAX_MANIFEST_BYTES { return Err("Cloud manifest is too large".into()); }
    let value: Value = serde_json::from_slice(bytes).map_err(|_| "Invalid cloud manifest JSON".to_string())?;
    let id = field(&value, "id")?;
    if !valid_id(id) || key != format!("{prefix}catalog/assets/{id}.json") { return Err("Cloud manifest ID does not match its key".into()); }
    let version = value.get("version").and_then(Value::as_i64).unwrap_or(0);
    if version != 2 { return Err(format!("Unsupported cloud manifest version {version}")); }
    let filename = field(&value, "filename")?;
    let taken_at = field(&value, "takenAt")?;
    let collection = field(&value, "collection")?;
    let (original_key, original_bytes) = {
        let object = value.get("original").ok_or("Missing original")?;
        let object_key = field(object, "key")?;
        let expected_prefix = format!("{prefix}originals/{id}.");
        if !object_key.starts_with(&expected_prefix) || object_key.len() <= expected_prefix.len() {
            return Err("Unexpected original object key".into());
        }
        let size = object.get("bytes").and_then(Value::as_i64).filter(|size| *size > 0)
            .ok_or("Invalid original size")?;
        (object_key.to_string(), size)
    };
    let (preview_key, preview_bytes) = media(&value, "preview", &format!("{prefix}previews/{id}.jpg"))?;
    let (thumbnail_key, thumbnail_bytes) = media(&value, "thumbnail", &format!("{prefix}thumbnails/{id}.jpg"))?;
    let inserted = db.execute("INSERT OR IGNORE INTO assets
        (id,filename,source_path,preview_path,taken_at,collection,favorite,description,latitude,longitude,altitude)
        VALUES (?1,?2,'','',?3,?4,?5,?6,?7,?8,?9)", params![
        id, filename, taken_at, collection, value.get("favorite").and_then(Value::as_bool).unwrap_or(false) as i64,
        value.get("description").and_then(Value::as_str), value.get("latitude").and_then(Value::as_f64),
        value.get("longitude").and_then(Value::as_f64), value.get("altitude").and_then(Value::as_f64)
    ]).map_err(|error| error.to_string())?;
    if inserted == 0 {
        db.execute("UPDATE assets SET filename=?2, taken_at=?3, collection=?4,
            favorite=CASE WHEN favorite_modified=0 THEN ?5 ELSE favorite END,
            description=?6,latitude=?7,longitude=?8,altitude=?9 WHERE id=?1 AND source_path=''", params![
            id, filename, taken_at, collection, value.get("favorite").and_then(Value::as_bool).unwrap_or(false) as i64,
            value.get("description").and_then(Value::as_str), value.get("latitude").and_then(Value::as_f64),
            value.get("longitude").and_then(Value::as_f64), value.get("altitude").and_then(Value::as_f64)
        ]).map_err(|error| error.to_string())?;
    }
    db.execute("INSERT INTO remote_assets (asset_id,original_key,original_bytes,preview_key,preview_bytes,thumbnail_key,thumbnail_bytes,manifest_version)
        VALUES (?1,?2,?3,?4,?5,?6,?7,?8)
        ON CONFLICT(asset_id) DO UPDATE SET original_key=excluded.original_key,original_bytes=excluded.original_bytes,
        preview_key=excluded.preview_key,preview_bytes=excluded.preview_bytes,
        thumbnail_key=excluded.thumbnail_key,thumbnail_bytes=excluded.thumbnail_bytes,manifest_version=excluded.manifest_version",
        params![id,original_key,original_bytes,preview_key,preview_bytes,thumbnail_key,thumbnail_bytes,version])
        .map_err(|error| error.to_string())?;
    Ok(inserted > 0)
}

fn begin_manifest_listing(db: &Connection) -> Result<(), String> {
    db.execute_batch("CREATE TEMP TABLE IF NOT EXISTS seen_remote_manifests (asset_id TEXT PRIMARY KEY);
        DELETE FROM seen_remote_manifests")
        .map_err(|error| format!("Could not start cloud catalogue refresh: {error}"))
}

fn note_manifest_listed(db: &Connection, id: &str) -> Result<(), String> {
    db.execute("INSERT OR IGNORE INTO seen_remote_manifests(asset_id) VALUES (?1)", params![id])
        .map_err(|error| format!("Could not record cloud catalogue entry: {error}"))?;
    Ok(())
}

fn finish_manifest_listing(db: &Connection, config: &cloud::S3Config, etag_target: &str) -> Result<(), String> {
    let transaction = db.unchecked_transaction()
        .map_err(|error| format!("Could not finish cloud catalogue refresh: {error}"))?;
    let sync_target = format!("{}/{}", config.bucket, config.prefix);
    // The complete S3 listing is authoritative. Preserve local source photos, but
    // queue them again when their cloud manifest has disappeared.
    transaction.execute("UPDATE sync_items SET state='not_synced',original_done=0,preview_done=0,
        thumbnail_done=0,manifest_done=0,synced_at=NULL,error=NULL
        WHERE target=?1 AND state='synced' AND asset_id NOT IN
            (SELECT asset_id FROM seen_remote_manifests)
        AND asset_id IN (SELECT id FROM assets WHERE source_path<>'')", params![sync_target])
        .map_err(|error| format!("Could not update removed cloud backups: {error}"))?;
    transaction.execute("DELETE FROM remote_manifest_etags WHERE target=?1 AND asset_id NOT IN
        (SELECT asset_id FROM seen_remote_manifests)", params![etag_target])
        .map_err(|error| format!("Could not remove stale cloud ETags: {error}"))?;
    transaction.execute("DELETE FROM remote_assets WHERE asset_id NOT IN
        (SELECT asset_id FROM seen_remote_manifests)", [])
        .map_err(|error| format!("Could not remove stale cloud photos: {error}"))?;
    transaction.execute("DELETE FROM assets WHERE source_path='' AND id NOT IN
        (SELECT asset_id FROM seen_remote_manifests)", [])
        .map_err(|error| format!("Could not remove stale cloud-only photos: {error}"))?;
    transaction.commit().map_err(|error| format!("Could not save cloud catalogue refresh: {error}"))
}

#[tauri::command]
pub async fn refresh_remote(app: AppHandle) -> Result<RemoteRefreshResult, String> {
    tauri::async_runtime::spawn_blocking(move || tauri::async_runtime::block_on(refresh_remote_worker(app)))
        .await.map_err(|error| error.to_string())?
}

async fn refresh_remote_worker(app: AppHandle) -> Result<RemoteRefreshResult, String> {
    let db = database(&app)?;
    let (config, client) = cloud::upload_connection(&db)?;
    events::upload_pending(&db, &client, &config).await?;
    let mut result = RemoteRefreshResult { scanned: 0, added: 0, updated: 0, unchanged: 0, errors: Vec::new() };
    let listing_prefix = format!("{}catalog/assets/", config.prefix);
    let target = manifest_target(&config);
    begin_manifest_listing(&db)?;
    let mut continuation: Option<String> = None;
    loop {
        let mut request = client.list_objects_v2().bucket(&config.bucket)
            .prefix(&listing_prefix);
        if let Some(token) = &continuation { request = request.continuation_token(token); }
        let page = request.send().await.map_err(|error| format!("Could not list cloud photos: {error}"))?;
        for object in page.contents() {
            let Some(key) = object.key() else { continue };
            if !key.ends_with(".json") { continue; }
            result.scanned += 1;
            let Some(id) = listed_manifest_id(&listing_prefix, key) else {
                result.errors.push(format!("{key}: invalid cloud manifest key"));
                continue;
            };
            note_manifest_listed(&db, id)?;
            if manifest_unchanged(&db, &target, id, object.e_tag())? {
                result.unchanged += 1;
                continue;
            }
            let outcome = async {
                let response = client.get_object().bucket(&config.bucket).key(key).send().await
                    .map_err(|error| format!("Could not read cloud manifest: {error}"))?;
                if response.content_length().unwrap_or(0) > MAX_MANIFEST_BYTES as i64 {
                    return Err("Cloud manifest is too large".to_string());
                }
                let body = response.body.collect().await.map_err(|error| format!("Could not download cloud manifest: {error}"))?;
                let added = import_manifest(&db, &config.prefix, key, body.into_bytes().as_ref())?;
                record_manifest_etag(&db, &target, id, object.e_tag())?;
                Ok::<bool, String>(added)
            }.await;
            match outcome {
                Ok(true) => result.added += 1,
                Ok(false) => result.updated += 1,
                Err(error) => result.errors.push(format!("{key}: {error}")),
            }
        }
        continuation = page.next_continuation_token().map(str::to_string);
        if continuation.is_none() { break; }
    }
    finish_manifest_listing(&db, &config, &target)?;
    events::replay(&db, &client, &config).await?;
    Ok(result)
}

fn cache_root(app: &AppHandle) -> Result<PathBuf, String> {
    Ok(app.path().app_cache_dir().map_err(|error| error.to_string())?.join("cloud-media"))
}

fn publish_cached_media(path: &Path, bytes: &[u8]) -> Result<(), String> {
    fs::create_dir_all(path.parent().ok_or("Invalid cache path")?).map_err(|error| error.to_string())?;
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|error| error.to_string())?.as_nanos();
    let temporary = path.with_extension(format!("{}.{}.partial", std::process::id(), stamp));
    let result = (|| -> Result<(), String> {
        fs::write(&temporary, bytes).map_err(|error| format!("Could not cache photo: {error}"))?;
        if path.exists() { fs::remove_file(path).map_err(|error| error.to_string())?; }
        fs::rename(&temporary, path).map_err(|error| error.to_string())
    })();
    if result.is_err() { let _ = fs::remove_file(&temporary); }
    result
}

#[tauri::command]
pub fn get_cache_status(app: AppHandle) -> Result<media_cache::CacheStatus, String> {
    media_cache::status(&database(&app)?)
}

#[tauri::command]
pub fn set_cache_limit(app: AppHandle, bytes: i64) -> Result<media_cache::CacheStatus, String> {
    media_cache::set_limit(&database(&app)?, &cache_root(&app)?, bytes)
}

#[tauri::command]
pub async fn ensure_media(app: AppHandle, id: String, variant: String) -> Result<String, String> {
    if variant != "thumbnail" && variant != "preview" { return Err("Choose thumbnail or preview".into()); }
    let phone_app = app.clone();
    let phone_id = id.clone();
    let phone_variant = variant.clone();
    if let Some(path) = tauri::async_runtime::spawn_blocking(move ||
        crate::phone_media::ensure(&phone_app, &phone_id, &phone_variant))
        .await.map_err(|error| error.to_string())?? { return Ok(path); }
    if !valid_id(&id) { return Err("Invalid photo ID".into()); }
    let db = database(&app)?;
    let (key, expected): (String, i64) = db.query_row(
        if variant == "thumbnail" { "SELECT thumbnail_key,thumbnail_bytes FROM remote_assets WHERE asset_id=?1" }
        else { "SELECT preview_key,preview_bytes FROM remote_assets WHERE asset_id=?1" },
        params![id], |row| Ok((row.get(0)?,row.get(1)?)))
        .optional().map_err(|error| error.to_string())?.ok_or("Photo is not in the cloud catalogue")?;
    let maximum = if variant == "thumbnail" { MAX_THUMBNAIL_BYTES } else { MAX_PREVIEW_BYTES };
    if expected <= 0 || expected > maximum { return Err("Cloud photo derivative is unexpectedly large".into()); }
    let root = cache_root(&app)?;
    if let Some(path) = media_cache::lookup(&db, &root, &id, &variant, expected)? {
        return Ok(path.to_string_lossy().into_owned());
    }
    let (config, client) = cloud::upload_connection(&db)?;
    drop(db);
    if !key.starts_with(&config.prefix) { return Err("Cloud photo is outside the configured prefix".into()); }
    let response = client.get_object().bucket(&config.bucket).key(&key).send().await
        .map_err(|error| format!("Could not download photo: {error}"))?;
    if response.content_length().unwrap_or(expected) != expected { return Err("Cloud photo size changed; refresh the catalogue".into()); }
    let body = response.body.collect().await.map_err(|error| format!("Could not download photo: {error}"))?;
    let bytes = body.into_bytes();
    if bytes.len() as i64 != expected { return Err("Cloud photo download was incomplete".into()); }
    let db = database(&app)?;
    if let Some(path) = media_cache::lookup(&db, &root, &id, &variant, expected)? {
        return Ok(path.to_string_lossy().into_owned());
    }
    media_cache::reserve(&db, &root, expected, (&id, &variant))?;
    let path = media_cache::path(&root, &id, &variant);
    publish_cached_media(&path, &bytes)?;
    media_cache::record(&db, &id, &variant, expected)?;
    Ok(path.to_string_lossy().into_owned())
}

#[tauri::command]
pub async fn download_original(app: AppHandle, id: String, destination: String) -> Result<(), String> {
    if !valid_id(&id) { return Err("Invalid photo ID".into()); }
    let target = PathBuf::from(destination);
    if target.as_os_str().is_empty() || target.is_dir() || target.exists() {
        return Err("Choose a new file name for the original photo".into());
    }
    let db = database(&app)?;
    let source: String = db.query_row("SELECT source_path FROM assets WHERE id=?1", params![id], |row| row.get(0))
        .optional().map_err(|error| error.to_string())?.ok_or("Photo not found")?;
    let remote: Option<String> = db.query_row("SELECT original_key FROM remote_assets WHERE asset_id=?1", params![id], |row| row.get(0))
        .optional().map_err(|error| error.to_string())?;
    let connection = if Path::new(&source).is_file() { None } else { Some(cloud::upload_connection(&db)?) };
    drop(db);
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|error| error.to_string())?.as_nanos();
    let temporary = target.with_extension(format!("gallery-{}.{}.partial", std::process::id(), stamp));
    let outcome = async {
        let mut output = fs::OpenOptions::new().write(true).create_new(true).open(&temporary)
            .map_err(|error| format!("Could not create download: {error}"))?;
        let mut hash = Sha256::new();
        if Path::new(&source).is_file() {
            let mut input = fs::File::open(&source).map_err(|error| error.to_string())?;
            let mut buffer = [0u8; 64 * 1024];
            loop {
                let count = input.read(&mut buffer).map_err(|error| error.to_string())?;
                if count == 0 { break; }
                hash.update(&buffer[..count]);
                output.write_all(&buffer[..count]).map_err(|error| error.to_string())?;
            }
        } else {
            let (config, client) = connection.ok_or("Cloud connection unavailable")?;
            let key = remote.ok_or("Original photo is not backed up")?;
            if !key.starts_with(&config.prefix) { return Err("Original is outside the configured cloud prefix".into()); }
            let mut body = client.get_object().bucket(&config.bucket).key(key).send().await
                .map_err(|error| format!("Could not download original: {error}"))?.body;
            while let Some(chunk) = body.try_next().await.map_err(|error| format!("Original download failed: {error}"))? {
                hash.update(&chunk);
                output.write_all(&chunk).map_err(|error| error.to_string())?;
            }
        }
        output.sync_all().map_err(|error| error.to_string())?;
        drop(output);
        if format!("{:x}", hash.finalize()) != id { return Err("Original photo failed integrity verification".into()); }
        if target.exists() { return Err("Destination already exists".into()); }
        fs::rename(&temporary, &target).map_err(|error| format!("Could not save original: {error}"))?;
        Ok(())
    }.await;
    if outcome.is_err() { let _ = fs::remove_file(&temporary); }
    outcome
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn failed_cache_publish_cleans_temporary_file() {
        let root = std::env::temp_dir().join(format!("gallery-cache-publish-{}",std::process::id()));
        fs::create_dir_all(root.join("preview.jpg")).unwrap();
        assert!(publish_cached_media(&root.join("preview.jpg"),b"preview").is_err());
        let files: Vec<_> = fs::read_dir(&root).unwrap().map(Result::unwrap).collect();
        assert_eq!(files.len(),1);
        assert_eq!(files[0].file_name(),"preview.jpg");
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn manifest_etag_skips_only_known_unchanged_object_in_same_target() {
        let db = Connection::open_in_memory().unwrap();
        db.execute_batch("CREATE TABLE assets(id TEXT PRIMARY KEY)").unwrap();
        prepare(&db).unwrap();
        let id = "a".repeat(64);
        let key = format!("gallery/catalog/assets/{id}.json");
        assert_eq!(listed_manifest_id("gallery/catalog/assets/", &key), Some(id.as_str()));
        assert!(listed_manifest_id("gallery/catalog/assets/", "gallery/catalog/assets/bad.json").is_none());
        let target = "bucket|region|endpoint|gallery/";
        assert!(!manifest_unchanged(&db, target, &id, Some("etag-1")).unwrap());
        record_manifest_etag(&db, target, &id, Some("etag-1")).unwrap();
        assert!(!manifest_unchanged(&db, target, &id, Some("etag-1")).unwrap());
        db.execute("INSERT INTO remote_assets(asset_id,original_key,original_bytes,preview_key,preview_bytes,
            thumbnail_key,thumbnail_bytes,manifest_version) VALUES (?1,'original',1,'preview',1,'thumbnail',1,2)",
            params![id]).unwrap();
        assert!(!manifest_unchanged(&db, target, &id, Some("etag-1")).unwrap());
        db.execute("INSERT INTO assets(id) VALUES (?1)",params![id]).unwrap();
        assert!(manifest_unchanged(&db, target, &id, Some("etag-1")).unwrap());
        assert!(!manifest_unchanged(&db, target, &id, Some("etag-2")).unwrap());
        assert!(!manifest_unchanged(&db, "other-bucket|region|endpoint|gallery/", &id, Some("etag-1")).unwrap());
        assert!(!manifest_unchanged(&db, target, &id, None).unwrap());
        record_manifest_etag(&db, target, &id, Some("etag-2")).unwrap();
        assert!(manifest_unchanged(&db, target, &id, Some("etag-2")).unwrap());
    }

    #[test]
    fn completed_listing_removes_deleted_backups_without_deleting_local_photos() {
        let root = std::env::temp_dir().join(format!("gallery-prune-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let db = crate::open_database(&root.join("catalogue.sqlite")).unwrap();
        let config = cloud::S3Config { bucket: "bucket".into(), region: "us-east-1".into(),
            endpoint: String::new(), prefix: "gallery/".into() };
        let etag_target = manifest_target(&config);
        db.execute_batch("INSERT INTO assets(id,filename,source_path,preview_path,taken_at,collection)
            VALUES ('local-gone','one.jpg','local','preview','2024-01-01','test'),
                   ('local-kept','two.jpg','local','preview','2024-01-01','test'),
                   ('remote-only','three.jpg','','','2024-01-01','test');
            INSERT INTO sync_items(asset_id,target,state,original_done,preview_done,thumbnail_done,
                manifest_done,synced_at) VALUES
                ('local-gone','bucket/gallery/','synced',1,1,1,1,'yesterday'),
                ('local-kept','bucket/gallery/','synced',1,1,1,1,'yesterday');
            INSERT INTO remote_assets(asset_id,original_key,original_bytes,preview_key,preview_bytes,
                thumbnail_key,thumbnail_bytes,manifest_version) VALUES
                ('local-gone','a',1,'b',1,'c',1,2),
                ('local-kept','a',1,'b',1,'c',1,2),
                ('remote-only','a',1,'b',1,'c',1,2);") .unwrap();
        for id in ["local-gone","local-kept","remote-only"] {
            record_manifest_etag(&db, &etag_target, id, Some("etag")).unwrap();
        }
        begin_manifest_listing(&db).unwrap();
        note_manifest_listed(&db,"local-kept").unwrap();
        finish_manifest_listing(&db,&config,&etag_target).unwrap();
        let local: Vec<(String,String)> = db.prepare("SELECT a.id,s.state FROM assets a JOIN sync_items s
            ON s.asset_id=a.id ORDER BY a.id").unwrap()
            .query_map([], |row| Ok((row.get(0)?,row.get(1)?))).unwrap()
            .collect::<rusqlite::Result<_>>().unwrap();
        assert_eq!(local,vec![("local-gone".into(),"not_synced".into()),
            ("local-kept".into(),"synced".into())]);
        let remote_count: i64 = db.query_row("SELECT COUNT(*) FROM remote_assets",[],|row|row.get(0)).unwrap();
        let etag_count: i64 = db.query_row("SELECT COUNT(*) FROM remote_manifest_etags",[],|row|row.get(0)).unwrap();
        assert_eq!((remote_count,etag_count),(1,1));
        begin_manifest_listing(&db).unwrap();
        finish_manifest_listing(&db,&config,&etag_target).unwrap();
        let still_local: i64 = db.query_row("SELECT COUNT(*) FROM assets",[],|row|row.get(0)).unwrap();
        let still_synced: i64 = db.query_row("SELECT COUNT(*) FROM sync_items WHERE state='synced'",[],|row|row.get(0)).unwrap();
        assert_eq!((still_local,still_synced),(2,0));
        drop(db);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn imports_remote_manifest_without_local_original() {
        let db = Connection::open_in_memory().unwrap();
        db.execute_batch("CREATE TABLE assets (id TEXT PRIMARY KEY,filename TEXT NOT NULL,source_path TEXT NOT NULL,
            preview_path TEXT NOT NULL,taken_at TEXT NOT NULL,collection TEXT NOT NULL,favorite INTEGER NOT NULL DEFAULT 0,
            favorite_modified INTEGER NOT NULL DEFAULT 0,description TEXT,latitude REAL,longitude REAL,altitude REAL)").unwrap();
        prepare(&db).unwrap();
        let id = "a".repeat(64);
        let prefix = "gallery/";
        let key = format!("{prefix}catalog/assets/{id}.json");
        let manifest = json!({"version":2,"id":id,"filename":"one.jpg","takenAt":"2020-01-01T00:00:00Z",
            "collection":"Best of Poe 2","favorite":true,
            "original":{"key":format!("{prefix}originals/{id}.jpg"),"bytes":100},
            "preview":{"key":format!("{prefix}previews/{id}.jpg"),"bytes":50},
            "thumbnail":{"key":format!("{prefix}thumbnails/{id}.jpg"),"bytes":10}});
        let bytes = serde_json::to_vec(&manifest).unwrap();
        assert!(import_manifest(&db, prefix, &key, &bytes).unwrap());
        assert!(!import_manifest(&db, prefix, &key, &bytes).unwrap());
        let (source, favorite): (String, i64) = db.query_row("SELECT source_path,favorite FROM assets WHERE id=?1", params![id],
            |row| Ok((row.get(0)?,row.get(1)?))).unwrap();
        assert_eq!(source, "");
        assert_eq!(favorite, 1);
        assert!(import_manifest(&db, prefix, "gallery/catalog/assets/wrong.json", &bytes).is_err());
    }

    #[test]
    #[ignore = "requires GALLERY_LIVE_SYNC=1 and the configured personal S3 bucket"]
    fn reads_real_remote_catalogue_into_fresh_database() {
        assert_eq!(std::env::var("GALLERY_LIVE_SYNC").as_deref(), Ok("1"));
        let roaming = PathBuf::from(std::env::var_os("APPDATA").unwrap());
        let original = crate::open_database(&roaming.join("com.pshand.gallery/gallery.sqlite")).unwrap();
        let (config, client) = cloud::upload_connection(&original).unwrap();
        let root = std::env::temp_dir().join(format!("gallery-remote-test-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let fresh = crate::open_database(&root.join("fresh.sqlite")).unwrap();
        let list = tauri::async_runtime::block_on(client.list_objects_v2().bucket(&config.bucket)
            .prefix(format!("{}catalog/assets/",config.prefix)).send()).unwrap();
        let manifests: Vec<(String,String)> = list.contents().iter().filter_map(|object| {
            Some((object.key()?.to_string(), object.e_tag()?.to_string()))
        }).collect();
        assert!(manifests.len() >= 111);
        let target = manifest_target(&config);
        for (key,etag) in &manifests {
            let bytes = tauri::async_runtime::block_on(async {
                client.get_object().bucket(&config.bucket).key(key).send().await.unwrap().body.collect().await.unwrap().into_bytes()
            });
            assert!(import_manifest(&fresh, &config.prefix, key, &bytes).unwrap());
            let id = listed_manifest_id(&format!("{}catalog/assets/",config.prefix),key).unwrap();
            record_manifest_etag(&fresh,&target,id,Some(etag)).unwrap();
        }
        assert_eq!(fresh.query_row("SELECT COUNT(*) FROM assets", [], |row| row.get::<_, i64>(0)).unwrap(), manifests.len() as i64);
        let again = tauri::async_runtime::block_on(client.list_objects_v2().bucket(&config.bucket)
            .prefix(format!("{}catalog/assets/",config.prefix)).send()).unwrap();
        assert_eq!(again.contents().len(),manifests.len());
        for object in again.contents() {
            let id = listed_manifest_id(&format!("{}catalog/assets/",config.prefix),object.key().unwrap()).unwrap();
            assert!(manifest_unchanged(&fresh,&target,id,object.e_tag()).unwrap());
        }
        let (id, thumbnail, preview, original, original_size): (String, String, String, String, i64) = fresh.query_row(
            "SELECT asset_id,thumbnail_key,preview_key,original_key,original_bytes FROM remote_assets LIMIT 1", [],
            |row| Ok((row.get(0)?,row.get(1)?,row.get(2)?,row.get(3)?,row.get(4)?))).unwrap();
        let thumbnail_bytes = tauri::async_runtime::block_on(async {
            client.get_object().bucket(&config.bucket).key(thumbnail).send().await.unwrap().body.collect().await.unwrap().into_bytes()
        });
        assert!(image::load_from_memory(&thumbnail_bytes).is_ok());
        assert!(valid_id(&id));
        let preview_bytes = tauri::async_runtime::block_on(async {
            client.get_object().bucket(&config.bucket).key(preview).send().await.unwrap().body.collect().await.unwrap().into_bytes()
        });
        assert!(image::load_from_memory(&preview_bytes).is_ok());
        let original_bytes = tauri::async_runtime::block_on(async {
            client.get_object().bucket(&config.bucket).key(original).send().await.unwrap().body.collect().await.unwrap().into_bytes()
        });
        assert_eq!(original_bytes.len() as i64, original_size);
        assert_eq!(format!("{:x}", Sha256::digest(&original_bytes)), id);
        drop(fresh);
        fs::remove_dir_all(root).unwrap();
    }
}
