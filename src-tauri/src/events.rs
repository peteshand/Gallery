use crate::cloud;
use aws_sdk_s3::primitives::ByteStream;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct FavoriteEvent {
    version: u32,
    event_id: String,
    asset_id: String,
    favorite: bool,
    clock: i64,
    device_id: String,
}

pub fn prepare(db: &Connection) -> Result<(), String> {
    db.execute_batch("CREATE TABLE IF NOT EXISTS favorite_events (
        event_id TEXT PRIMARY KEY, asset_id TEXT NOT NULL, favorite INTEGER NOT NULL,
        clock INTEGER NOT NULL, device_id TEXT NOT NULL, uploaded INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS applied_events (event_id TEXT PRIMARY KEY);")
        .map_err(|error| format!("Could not prepare catalogue events: {error}"))
}

fn device_id(db: &Connection) -> Result<String, String> {
    let stored: Option<String> = db.query_row("SELECT value FROM app_settings WHERE key='device_id'", [], |row| row.get(0))
        .optional().map_err(|error| error.to_string())?;
    if let Some(id) = stored { return Ok(id); }
    let seed = format!("{}:{}:{}", SystemTime::now().duration_since(UNIX_EPOCH).map_err(|error| error.to_string())?.as_nanos(),
        std::process::id(), db as *const Connection as usize);
    let id = format!("{:x}", Sha256::digest(seed.as_bytes()));
    db.execute("INSERT OR IGNORE INTO app_settings (key,value) VALUES ('device_id',?1)", params![id])
        .map_err(|error| error.to_string())?;
    db.query_row("SELECT value FROM app_settings WHERE key='device_id'", [], |row| row.get(0))
        .map_err(|error| error.to_string())
}

pub fn record_favorite(db: &Connection, asset_id: &str, favorite: bool) -> Result<(), String> {
    prepare(db)?;
    let current: Option<i64> = db.query_row("SELECT favorite_clock FROM assets WHERE id=?1", params![asset_id], |row| row.get(0))
        .optional().map_err(|error| error.to_string())?;
    let clock = current.ok_or("Photo not found")? + 1;
    let device = device_id(db)?;
    let event_id = format!("{device}-{clock}-{}", SystemTime::now().duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?.as_nanos());
    db.execute("UPDATE assets SET favorite=?2,favorite_modified=1,favorite_clock=?3,favorite_device=?4 WHERE id=?1",
        params![asset_id,favorite as i64,clock,device]).map_err(|error| error.to_string())?;
    db.execute("INSERT INTO favorite_events (event_id,asset_id,favorite,clock,device_id) VALUES (?1,?2,?3,?4,?5)",
        params![event_id,asset_id,favorite as i64,clock,device]).map_err(|error| error.to_string())?;
    Ok(())
}

pub async fn upload_pending(db: &Connection, client: &aws_sdk_s3::Client, config: &cloud::S3Config) -> Result<(), String> {
    prepare(db)?;
    let mut statement = db.prepare("SELECT event_id,asset_id,favorite,clock,device_id FROM favorite_events WHERE uploaded=0 ORDER BY rowid")
        .map_err(|error| error.to_string())?;
    let events = statement.query_map([], |row| Ok(FavoriteEvent {
        version: 1, event_id: row.get(0)?, asset_id: row.get(1)?, favorite: row.get::<_, i64>(2)? != 0,
        clock: row.get(3)?, device_id: row.get(4)?,
    })).map_err(|error| error.to_string())?
        .collect::<rusqlite::Result<Vec<_>>>().map_err(|error| error.to_string())?;
    drop(statement);
    for event in events {
        let key = format!("{}catalog/events/{}/{}.json", config.prefix, event.device_id, event.event_id);
        let bytes = serde_json::to_vec(&event).map_err(|error| error.to_string())?;
        client.put_object().bucket(&config.bucket).key(key).content_type("application/json")
            .body(ByteStream::from(bytes)).send().await
            .map_err(|error| format!("Could not upload catalogue change: {error}"))?;
        db.execute("UPDATE favorite_events SET uploaded=1 WHERE event_id=?1", params![event.event_id])
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn apply(db: &Connection, key: &str, prefix: &str, bytes: &[u8]) -> Result<(), String> {
    if bytes.len() > 8192 { return Err("Catalogue event is too large".into()); }
    let event: FavoriteEvent = serde_json::from_slice(bytes).map_err(|_| "Invalid catalogue event".to_string())?;
    if event.version != 1 || event.clock <= 0 || event.asset_id.len() != 64 ||
        !event.asset_id.bytes().all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase()) ||
        event.device_id.len() != 64 || !event.device_id.bytes().all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase()) ||
        key != format!("{prefix}catalog/events/{}/{}.json", event.device_id, event.event_id) {
        return Err("Invalid catalogue event identity".into());
    }
    let seen = db.query_row("SELECT 1 FROM applied_events WHERE event_id=?1", params![event.event_id], |_| Ok(true))
        .optional().map_err(|error| error.to_string())?.unwrap_or(false);
    if seen { return Ok(()); }
    db.execute("UPDATE assets SET favorite=?2,favorite_modified=1,favorite_clock=?3,favorite_device=?4
        WHERE id=?1 AND (favorite_clock<?3 OR (favorite_clock=?3 AND favorite_device<?4))",
        params![event.asset_id,event.favorite as i64,event.clock,event.device_id])
        .map_err(|error| error.to_string())?;
    db.execute("INSERT OR IGNORE INTO applied_events (event_id) VALUES (?1)", params![event.event_id])
        .map_err(|error| error.to_string())?;
    Ok(())
}

pub async fn replay(db: &Connection, client: &aws_sdk_s3::Client, config: &cloud::S3Config) -> Result<(), String> {
    prepare(db)?;
    let prefix = format!("{}catalog/events/", config.prefix);
    let mut continuation: Option<String> = None;
    loop {
        let mut request = client.list_objects_v2().bucket(&config.bucket).prefix(&prefix);
        if let Some(token) = &continuation { request = request.continuation_token(token); }
        let page = request.send().await.map_err(|error| format!("Could not list catalogue changes: {error}"))?;
        for item in page.contents() {
            let Some(key) = item.key() else { continue };
            if !key.ends_with(".json") { continue; }
            let event_id = key.rsplit('/').next().unwrap_or("").trim_end_matches(".json");
            let seen = db.query_row("SELECT 1 FROM applied_events WHERE event_id=?1", params![event_id], |_| Ok(true))
                .optional().map_err(|error| error.to_string())?.unwrap_or(false);
            if seen { continue; }
            let response = client.get_object().bucket(&config.bucket).key(key).send().await
                .map_err(|error| format!("Could not read catalogue change: {error}"))?;
            if response.content_length().unwrap_or(0) > 8192 { return Err("Catalogue event is too large".into()); }
            let bytes = response.body.collect().await.map_err(|error| format!("Could not download catalogue change: {error}"))?.into_bytes();
            apply(db, key, &config.prefix, &bytes)?;
        }
        continuation = page.next_continuation_token().map(str::to_string);
        if continuation.is_none() { break; }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn favorite_events_converge_in_any_arrival_order() {
        let db = Connection::open_in_memory().unwrap();
        db.execute_batch("CREATE TABLE app_settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
            CREATE TABLE assets(id TEXT PRIMARY KEY,favorite INTEGER NOT NULL DEFAULT 0,favorite_modified INTEGER NOT NULL DEFAULT 0,
            favorite_clock INTEGER NOT NULL DEFAULT 0,favorite_device TEXT NOT NULL DEFAULT '')").unwrap();
        prepare(&db).unwrap();
        let asset = "a".repeat(64);
        db.execute("INSERT INTO assets(id) VALUES (?1)", params![asset]).unwrap();
        let make = |device: &str, favorite: bool| FavoriteEvent {
            version: 1, event_id: format!("{device}-1"), asset_id: asset.clone(), favorite, clock: 1, device_id: device.to_string(),
        };
        let a = make(&"a".repeat(64), true);
        let b = make(&"b".repeat(64), false);
        let prefix = "gallery/";
        let key = |event: &FavoriteEvent| format!("{prefix}catalog/events/{}/{}.json", event.device_id,event.event_id);
        apply(&db, &key(&b), prefix, &serde_json::to_vec(&b).unwrap()).unwrap();
        apply(&db, &key(&a), prefix, &serde_json::to_vec(&a).unwrap()).unwrap();
        let favorite: i64 = db.query_row("SELECT favorite FROM assets", [], |row| row.get(0)).unwrap();
        assert_eq!(favorite, 0);
    }

    #[test]
    #[ignore = "requires GALLERY_LIVE_SYNC=1 and writes isolated test events to the configured S3 bucket"]
    fn two_simulated_devices_converge_through_real_s3() {
        assert_eq!(std::env::var("GALLERY_LIVE_SYNC").as_deref(), Ok("1"));
        let roaming = std::path::PathBuf::from(std::env::var_os("APPDATA").unwrap());
        let local = crate::open_database(&roaming.join("com.pshand.gallery/gallery.sqlite")).unwrap();
        let (mut config, client) = cloud::upload_connection(&local).unwrap();
        let nonce = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        config.prefix = format!("{}tests/favorite-events-{nonce}/", config.prefix);
        let make_device = || {
            let db = Connection::open_in_memory().unwrap();
            db.execute_batch("CREATE TABLE app_settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                CREATE TABLE assets(id TEXT PRIMARY KEY,favorite INTEGER NOT NULL DEFAULT 0,favorite_modified INTEGER NOT NULL DEFAULT 0,
                favorite_clock INTEGER NOT NULL DEFAULT 0,favorite_device TEXT NOT NULL DEFAULT '')").unwrap();
            prepare(&db).unwrap();
            db.execute("INSERT INTO assets(id) VALUES (?1)", params!["a".repeat(64)]).unwrap();
            db
        };
        let a = make_device();
        let b = make_device();
        let asset = "a".repeat(64);
        let value = |db: &Connection| db.query_row("SELECT favorite FROM assets WHERE id=?1", params![asset], |row| row.get::<_,i64>(0)).unwrap();
        record_favorite(&a, &asset, true).unwrap();
        tauri::async_runtime::block_on(upload_pending(&a, &client, &config)).unwrap();
        tauri::async_runtime::block_on(replay(&b, &client, &config)).unwrap();
        assert_eq!(value(&b), 1);
        record_favorite(&b, &asset, false).unwrap();
        tauri::async_runtime::block_on(upload_pending(&b, &client, &config)).unwrap();
        tauri::async_runtime::block_on(replay(&a, &client, &config)).unwrap();
        assert_eq!(value(&a), 0);
        record_favorite(&a, &asset, true).unwrap();
        record_favorite(&b, &asset, false).unwrap();
        tauri::async_runtime::block_on(upload_pending(&a, &client, &config)).unwrap();
        tauri::async_runtime::block_on(upload_pending(&b, &client, &config)).unwrap();
        tauri::async_runtime::block_on(replay(&a, &client, &config)).unwrap();
        tauri::async_runtime::block_on(replay(&b, &client, &config)).unwrap();
        assert_eq!(value(&a), value(&b));
    }
}
