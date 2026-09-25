use chrono::Utc;
use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use std::{fs, path::{Path, PathBuf}};

const DEFAULT_LIMIT: i64 = 2 * 1024 * 1024 * 1024;
const MIN_LIMIT: i64 = 64 * 1024 * 1024;
const MAX_LIMIT: i64 = 50 * 1024 * 1024 * 1024;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CacheStatus {
    limit_bytes: i64,
    used_bytes: i64,
    item_count: i64,
}

pub fn prepare(db: &Connection) -> Result<(), String> {
    db.execute_batch("CREATE TABLE IF NOT EXISTS media_cache (
        asset_id TEXT NOT NULL, variant TEXT NOT NULL, bytes INTEGER NOT NULL,
        last_access_ms INTEGER NOT NULL, PRIMARY KEY(asset_id, variant));
        CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);")
        .map_err(|error| format!("Could not prepare media cache: {error}"))
}

fn limit(db: &Connection) -> Result<i64, String> {
    prepare(db)?;
    let value: Option<String> = db.query_row("SELECT value FROM app_settings WHERE key='cache_limit_bytes'", [], |row| row.get(0))
        .optional().map_err(|error| error.to_string())?;
    Ok(value.and_then(|value| value.parse::<i64>().ok()).unwrap_or(DEFAULT_LIMIT))
}

pub fn status(db: &Connection) -> Result<CacheStatus, String> {
    prepare(db)?;
    let (used_bytes, item_count) = db.query_row(
        "SELECT COALESCE(SUM(bytes),0), COUNT(*) FROM media_cache", [],
        |row| Ok((row.get(0)?, row.get(1)?))
    ).map_err(|error| error.to_string())?;
    Ok(CacheStatus { limit_bytes: limit(db)?, used_bytes, item_count })
}

pub fn set_limit(db: &Connection, cache_root: &Path, bytes: i64) -> Result<CacheStatus, String> {
    if !(MIN_LIMIT..=MAX_LIMIT).contains(&bytes) { return Err("Choose a cache limit from 64 MB to 50 GB".into()); }
    prepare(db)?;
    db.execute("INSERT INTO app_settings (key,value) VALUES ('cache_limit_bytes',?1)
        ON CONFLICT(key) DO UPDATE SET value=excluded.value", params![bytes.to_string()])
        .map_err(|error| error.to_string())?;
    evict(db, cache_root, 0, bytes, None)?;
    status(db)
}

pub fn path(cache_root: &Path, id: &str, variant: &str) -> PathBuf {
    cache_root.join(id).join(match variant { "thumbnail" => "thumbnail.jpg", _ => "preview.jpg" })
}

pub fn lookup(db: &Connection, cache_root: &Path, id: &str, variant: &str, expected: i64) -> Result<Option<PathBuf>, String> {
    prepare(db)?;
    let path = path(cache_root, id, variant);
    let valid = fs::metadata(&path).map(|value| value.is_file() && value.len() == expected as u64).unwrap_or(false);
    if valid {
        record(db, id, variant, expected)?;
        return Ok(Some(path));
    }
    db.execute("DELETE FROM media_cache WHERE asset_id=?1 AND variant=?2", params![id,variant])
        .map_err(|error| error.to_string())?;
    Ok(None)
}

pub fn record(db: &Connection, id: &str, variant: &str, bytes: i64) -> Result<(), String> {
    prepare(db)?;
    db.execute("INSERT INTO media_cache (asset_id,variant,bytes,last_access_ms) VALUES (?1,?2,?3,?4)
        ON CONFLICT(asset_id,variant) DO UPDATE SET bytes=excluded.bytes,last_access_ms=excluded.last_access_ms",
        params![id,variant,bytes,Utc::now().timestamp_millis()])
        .map_err(|error| error.to_string())?;
    Ok(())
}

pub fn reserve(db: &Connection, cache_root: &Path, incoming: i64, keep: (&str, &str)) -> Result<(), String> {
    let maximum = limit(db)?;
    if incoming > maximum { return Err("This photo exceeds the configured cache limit".into()); }
    evict(db, cache_root, incoming, maximum, Some(keep))
}

fn evict(db: &Connection, cache_root: &Path, incoming: i64, maximum: i64, keep: Option<(&str, &str)>) -> Result<(), String> {
    let mut used = status(db)?.used_bytes;
    if used + incoming <= maximum { return Ok(()); }
    let mut statement = db.prepare("SELECT asset_id,variant,bytes FROM media_cache ORDER BY last_access_ms,asset_id,variant")
        .map_err(|error| error.to_string())?;
    let entries = statement.query_map([], |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?, row.get::<_, i64>(2)?)))
        .map_err(|error| error.to_string())?
        .collect::<rusqlite::Result<Vec<_>>>().map_err(|error| error.to_string())?;
    drop(statement);
    for (id, variant, bytes) in entries {
        if keep == Some((id.as_str(), variant.as_str())) { continue; }
        let path = path(cache_root, &id, &variant);
        if path.exists() { fs::remove_file(&path).map_err(|error| format!("Could not free cache space: {error}"))?; }
        db.execute("DELETE FROM media_cache WHERE asset_id=?1 AND variant=?2", params![id,variant])
            .map_err(|error| error.to_string())?;
        used -= bytes;
        if used + incoming <= maximum { return Ok(()); }
    }
    Err("Not enough cache space for this photo".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn evicts_oldest_cached_media_and_keeps_recent_item() {
        let root = std::env::temp_dir().join(format!("gallery-cache-test-{}", std::process::id()));
        fs::create_dir_all(root.join("a")).unwrap();
        fs::create_dir_all(root.join("b")).unwrap();
        fs::write(path(&root, "a", "thumbnail"), [1u8; 6]).unwrap();
        fs::write(path(&root, "b", "preview"), [2u8; 6]).unwrap();
        let db = Connection::open_in_memory().unwrap();
        prepare(&db).unwrap();
        record(&db, "a", "thumbnail", 6).unwrap();
        record(&db, "b", "preview", 6).unwrap();
        db.execute("UPDATE media_cache SET last_access_ms=1 WHERE asset_id='a'", []).unwrap();
        db.execute("UPDATE media_cache SET last_access_ms=2 WHERE asset_id='b'", []).unwrap();
        evict(&db, &root, 4, 10, Some(("b", "preview"))).unwrap();
        assert!(!path(&root, "a", "thumbnail").exists());
        assert!(path(&root, "b", "preview").exists());
        assert_eq!(status(&db).unwrap().used_bytes, 6);
        fs::remove_dir_all(root).unwrap();
    }
}
