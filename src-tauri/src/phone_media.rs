use crate::{Asset, database};
use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use std::{fs, path::{Path, PathBuf}, time::{SystemTime, UNIX_EPOCH}};
use tauri::{AppHandle, Manager};
use tauri_plugin_gallery_media::GalleryMediaExt;

const PREFIX: &str = "phone-";

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PhoneStatus { pub access: String, pub count: i64 }

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PhoneRefresh { pub access: String, pub found: i64, pub added: i64 }

pub fn prepare(db: &Connection) -> Result<(), String> {
    db.execute_batch("CREATE TABLE IF NOT EXISTS phone_media (
        media_id INTEGER PRIMARY KEY, filename TEXT NOT NULL, taken_at TEXT NOT NULL,
        mime_type TEXT NOT NULL, bytes INTEGER NOT NULL, asset_id TEXT,
        scan_epoch INTEGER NOT NULL DEFAULT 0,
        device_folder TEXT NOT NULL DEFAULT 'Other'
    ); CREATE INDEX IF NOT EXISTS phone_media_asset_idx ON phone_media(asset_id);")
        .map_err(|error| format!("Could not prepare phone catalogue: {error}"))?;
    let has_folder = db.prepare("PRAGMA table_info(phone_media)").map_err(|error| error.to_string())?
        .query_map([], |row| row.get::<_, String>(1)).map_err(|error| error.to_string())?
        .any(|column| matches!(column, Ok(name) if name == "device_folder"));
    if !has_folder {
        db.execute("ALTER TABLE phone_media ADD COLUMN device_folder TEXT NOT NULL DEFAULT 'Other'", [])
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

pub fn folder_name(path: &str) -> String {
    let path = path.replace('\\', "/");
    let lower = path.to_ascii_lowercase();
    if lower.contains("whatsapp") { return "WhatsApp".into(); }
    if lower.contains("screenshot") { return "Screenshots".into(); }
    if lower.contains("telegram") { return "Telegram".into(); }
    if lower.contains("instagram") { return "Instagram".into(); }
    if lower.contains("signal") { return "Signal".into(); }
    if lower.starts_with("dcim/") || lower == "dcim" || lower == "camera" || lower.starts_with("pictures/camera") {
        return "Camera".into();
    }
    let last = path.split('/').filter(|part| !part.is_empty()).last().unwrap_or("Other").trim();
    if last.is_empty() { return "Other".into(); }
    last.chars().filter(|character| !character.is_control()).take(50).collect()
}

pub fn device_collection(folder: &str) -> String { format!("On this phone / {}", folder_name(folder)) }

fn media_id(id: &str) -> Option<i64> {
    let suffix = id.strip_prefix(PREFIX)?;
    if suffix.is_empty() || !suffix.bytes().all(|byte| byte.is_ascii_digit()) { return None; }
    suffix.parse::<i64>().ok().filter(|value| *value > 0)
}

pub fn source_media_id(path: &Path) -> Option<i64> {
    path.to_str()?.strip_prefix("phone:")?.parse::<i64>().ok().filter(|value| *value > 0)
}

fn cache_root(app: &AppHandle) -> Result<PathBuf, String> {
    Ok(app.path().app_cache_dir().map_err(|error| error.to_string())?.join("phone-media"))
}

fn derivative(app: &AppHandle, media_id: i64, variant: &str) -> Result<PathBuf, String> {
    Ok(cache_root(app)?.join(media_id.to_string()).join(format!("{variant}.jpg")))
}

pub fn list_assets(app: &AppHandle, db: &Connection) -> Result<Vec<Asset>, String> {
    prepare(db)?;
    let mut statement = db.prepare("SELECT media_id, filename, taken_at, device_folder FROM phone_media WHERE asset_id IS NULL ORDER BY taken_at DESC, media_id DESC")
        .map_err(|error| error.to_string())?;
    let rows = statement.query_map([], |row| Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?, row.get::<_, String>(2)?, row.get::<_, String>(3)?)))
        .map_err(|error| error.to_string())?;
    let mut assets = Vec::new();
    for row in rows {
        let (id, filename, taken_at, folder) = row.map_err(|error| error.to_string())?;
        let preview = derivative(app, id, "preview")?;
        let thumbnail = derivative(app, id, "thumbnail")?;
        assets.push(Asset {
            id: format!("{PREFIX}{id}"), filename, taken_at, collection: device_collection(&folder),
            favorite: false, media_url: if preview.is_file() { preview.to_string_lossy().into_owned() } else { String::new() },
            thumbnail_url: thumbnail.is_file().then(|| thumbnail.to_string_lossy().into_owned()),
            description: None, latitude: None, longitude: None, altitude: None,
            sync_state: "not_synced".into(), synced_at: None, sync_error: None,
        });
    }
    Ok(assets)
}

fn count(db: &Connection) -> Result<i64, String> {
    db.query_row("SELECT COUNT(*) FROM phone_media", [], |row| row.get(0)).map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn get_phone_status(app: AppHandle) -> Result<PhoneStatus, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let db = database(&app)?;
        let access = app.gallery_media().check_access().map_err(|error| error.to_string())?.access;
        Ok(PhoneStatus { access, count: count(&db)? })
    }).await.map_err(|error| error.to_string())?
}

#[tauri::command]
pub async fn request_phone_access(app: AppHandle) -> Result<PhoneStatus, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let db = database(&app)?;
        let access = app.gallery_media().request_access().map_err(|error| error.to_string())?.access;
        Ok(PhoneStatus { access, count: count(&db)? })
    }).await.map_err(|error| error.to_string())?
}

#[tauri::command]
pub async fn refresh_phone_media(app: AppHandle) -> Result<PhoneRefresh, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let result = refresh(&app)?;
        if result.access == "full" { app.gallery_media().run_auto_backup().map_err(|error| error.to_string())?; }
        Ok(result)
    }).await.map_err(|error| error.to_string())?
}

fn refresh(app: &AppHandle) -> Result<PhoneRefresh, String> {
    let plugin = app.gallery_media();
    let access = plugin.check_access().map_err(|error| error.to_string())?.access;
    if access == "none" || access == "unsupported" { return Ok(PhoneRefresh { access, found: 0, added: 0 }); }
    let mut db = database(app)?;
    prepare(&db)?;
    let epoch = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|error| error.to_string())?.as_millis() as i64;
    let mut offset = 0;
    let mut found = 0;
    let mut added = 0;
    loop {
        let page = plugin.list_media(offset, 200).map_err(|error| error.to_string())?;
        if page.next_offset <= offset { break; }
        let transaction = db.transaction().map_err(|error| error.to_string())?;
        for entry in page.items {
            let taken = DateTime::<Utc>::from_timestamp_millis(entry.taken_at_millis)
                .unwrap_or_else(Utc::now).to_rfc3339();
            let collection = device_collection(&entry.folder);
            added += transaction.execute("INSERT OR IGNORE INTO phone_media (media_id,filename,taken_at,mime_type,bytes,scan_epoch,device_folder)
                VALUES (?1,?2,?3,?4,?5,?6,?7)", params![entry.media_id,entry.filename,taken,entry.mime_type,entry.bytes,epoch,entry.folder])
                .map_err(|error| error.to_string())? as i64;
            transaction.execute("UPDATE phone_media SET filename=?2,taken_at=?3,mime_type=?4,bytes=?5,scan_epoch=?6,device_folder=?7 WHERE media_id=?1",
                params![entry.media_id,entry.filename,taken,entry.mime_type,entry.bytes,epoch,entry.folder])
                .map_err(|error| error.to_string())?;
            let changed = transaction.execute("UPDATE assets SET collection=?2 WHERE id=(SELECT asset_id FROM phone_media WHERE media_id=?1)
                AND collection<>?2 AND (collection='On this phone' OR collection LIKE 'On this phone / %')",
                params![entry.media_id,collection]).map_err(|error| error.to_string())?;
            if changed > 0 {
                transaction.execute("UPDATE sync_items SET state='not_synced',manifest_done=0,synced_at=NULL
                    WHERE asset_id=(SELECT asset_id FROM phone_media WHERE media_id=?1)", params![entry.media_id])
                    .map_err(|error| error.to_string())?;
            }
            found += 1;
        }
        transaction.commit().map_err(|error| error.to_string())?;
        offset = page.next_offset;
        if offset >= page.total { break; }
    }
    db.execute("DELETE FROM phone_media WHERE scan_epoch<>?1", params![epoch])
        .map_err(|error| error.to_string())?;
    Ok(PhoneRefresh { access, found, added })
}

pub fn resolve_media_id(db: &Connection, id: &str) -> Result<Option<i64>, String> {
    if let Some(id) = media_id(id) { return Ok(Some(id)); }
    db.query_row("SELECT media_id FROM phone_media WHERE asset_id=?1 LIMIT 1", params![id], |row| row.get(0))
        .optional().map_err(|error| error.to_string())
}

pub fn ensure(app: &AppHandle, id: &str, variant: &str) -> Result<Option<String>, String> {
    let db = database(app)?;
    let Some(media_id) = resolve_media_id(&db, id)? else { return Ok(None) };
    let path = derivative(app, media_id, variant)?;
    if !path.is_file() {
        fs::create_dir_all(path.parent().ok_or("Invalid phone media path")?).map_err(|error| error.to_string())?;
        let destination = path.to_str().ok_or("Invalid phone media path")?;
        (if variant == "thumbnail" { app.gallery_media().make_thumbnail(media_id, destination) }
        else { app.gallery_media().make_preview(media_id, destination) })
            .map_err(|error| error.to_string())?;
    }
    Ok(Some(path.to_string_lossy().into_owned()))
}

pub fn has_phone_id(db: &Connection, id: &str) -> Result<bool, String> {
    let Some(media_id) = media_id(id) else { return Ok(false) };
    db.query_row("SELECT 1 FROM phone_media WHERE media_id=?1", params![media_id], |_| Ok(true))
        .optional().map(|value| value.unwrap_or(false)).map_err(|error| error.to_string())
}

pub fn prepare_for_backup(app: &AppHandle, db: &Connection, id: &str) -> Result<String, String> {
    let Some(media_id) = media_id(id) else { return Ok(id.to_string()) };
    let (filename, taken_at, folder): (String, String, String) = db.query_row("SELECT filename,taken_at,device_folder FROM phone_media WHERE media_id=?1",
        params![media_id], |row| Ok((row.get(0)?,row.get(1)?,row.get(2)?))).map_err(|error| error.to_string())?;
    let hash = app.gallery_media().hash_original(media_id).map_err(|error| error.to_string())?.sha256;
    if hash.len() != 64 || !hash.bytes().all(|value| value.is_ascii_hexdigit() && !value.is_ascii_uppercase()) {
        return Err("Phone photo hash is invalid".into());
    }
    let existing: bool = db.query_row("SELECT 1 FROM assets WHERE id=?1", params![hash], |_| Ok(true))
        .optional().map_err(|error| error.to_string())?.unwrap_or(false);
    if !existing {
        db.execute("INSERT INTO assets (id,filename,source_path,preview_path,taken_at,collection,favorite)
            VALUES (?1,?2,?3,'',?4,?5,0)", params![hash,filename,format!("phone:{media_id}"),taken_at,device_collection(&folder)])
            .map_err(|error| error.to_string())?;
    }
    db.execute("UPDATE phone_media SET asset_id=?2 WHERE media_id=?1", params![media_id,hash])
        .map_err(|error| error.to_string())?;
    Ok(hash)
}

pub struct StagedOriginal(pub PathBuf);
impl Drop for StagedOriginal { fn drop(&mut self) { let _ = fs::remove_file(&self.0); } }

pub fn stage_original(app: &AppHandle, media_id: i64, hash: &str) -> Result<StagedOriginal, String> {
    let path = cache_root(app)?.join("stage").join(format!("{hash}.original"));
    fs::create_dir_all(path.parent().ok_or("Invalid staging path")?).map_err(|error| error.to_string())?;
    if path.exists() { fs::remove_file(&path).map_err(|error| error.to_string())?; }
    let copied = app.gallery_media().copy_original(media_id, path.to_str().ok_or("Invalid staging path")?)
        .map_err(|error| error.to_string())?;
    if copied.sha256 != hash { let _ = fs::remove_file(&path); return Err("Phone photo changed since it was queued; refresh and retry".into()); }
    Ok(StagedOriginal(path))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn phone_identifiers_cannot_escape_the_media_catalogue() {
        assert_eq!(media_id("phone-42"), Some(42));
        for value in ["phone-", "phone-0", "phone--1", "phone-1/../2", "phone-1abc", "42"] {
            assert_eq!(media_id(value), None);
        }
        assert_eq!(source_media_id(Path::new("phone:42")), Some(42));
        assert_eq!(source_media_id(Path::new("phone:../../42")), None);
    }

    #[test]
    fn scan_catalogue_persists_phone_to_cloud_identity() {
        let db = Connection::open_in_memory().unwrap();
        prepare(&db).unwrap();
        db.execute("INSERT INTO phone_media (media_id,filename,taken_at,mime_type,bytes,asset_id)
            VALUES (7,'image.jpg','2026-09-23T00:00:00Z','image/jpeg',10,'abc')", []).unwrap();
        assert_eq!(resolve_media_id(&db, "abc").unwrap(), Some(7));
        assert!(has_phone_id(&db, "phone-7").unwrap());
    }

    #[test]
    fn phone_folders_keep_app_images_in_separate_collections() {
        assert_eq!(device_collection("DCIM/Camera"), "On this phone / Camera");
        assert_eq!(device_collection("Pictures/WhatsApp Images"), "On this phone / WhatsApp");
        assert_eq!(device_collection("Pictures/Screenshots"), "On this phone / Screenshots");
    }
}
