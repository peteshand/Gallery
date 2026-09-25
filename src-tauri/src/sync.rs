use crate::{cloud, events, open_database, phone_media};
use aws_sdk_s3::primitives::ByteStream;
use chrono::Utc;
use image::{codecs::jpeg::JpegEncoder, imageops::FilterType, metadata::Orientation, DynamicImage, ImageDecoder, ImageReader};
use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use serde_json::json;
use std::{collections::HashSet, fs, path::{Path, PathBuf}, sync::Mutex};
use tauri::{AppHandle, Manager, State};

#[derive(Default)]
pub struct SyncRunner(Mutex<RunnerState>);

#[derive(Default)]
struct RunnerState {
    running: bool,
    cancelling: bool,
    cancelled: bool,
}

impl SyncRunner {
    fn begin(&self) -> bool {
        let mut state = self.0.lock().unwrap();
        if state.running { return false; }
        *state = RunnerState { running: true, ..RunnerState::default() };
        true
    }

    fn request_cancel(&self) {
        let mut state = self.0.lock().unwrap();
        if state.running { state.cancelling = true; }
    }

    fn cancellation_requested(&self) -> bool { self.0.lock().unwrap().cancelling }

    fn finish(&self) {
        let mut state = self.0.lock().unwrap();
        state.cancelled = state.cancelling;
        state.cancelling = false;
        state.running = false;
    }

    fn status(&self) -> (bool, bool, bool) {
        let state = self.0.lock().unwrap();
        (state.running, state.cancelling, state.cancelled)
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncStatus {
    pub running: bool,
    pub cancelling: bool,
    pub cancelled: bool,
    pub total: i64,
    pub not_synced: i64,
    pub preparing: i64,
    pub uploading: i64,
    pub synced: i64,
    pub failed: i64,
    pub current_name: Option<String>,
    pub last_error: Option<String>,
}

struct Item {
    filename: String,
    source_path: PathBuf,
    preview_path: PathBuf,
    taken_at: String,
    collection: String,
    favorite: bool,
    description: Option<String>,
    latitude: Option<f64>,
    longitude: Option<f64>,
    altitude: Option<f64>,
    takeout: Option<serde_json::Value>,
}

fn prepare_schema(db: &Connection) -> Result<(), String> {
    db.execute_batch("CREATE TABLE IF NOT EXISTS sync_items (
        asset_id TEXT PRIMARY KEY,
        target TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'not_synced',
        original_done INTEGER NOT NULL DEFAULT 0,
        preview_done INTEGER NOT NULL DEFAULT 0,
        thumbnail_done INTEGER NOT NULL DEFAULT 0,
        manifest_done INTEGER NOT NULL DEFAULT 0,
        synced_at TEXT,
        error TEXT,
        derivative_version INTEGER NOT NULL DEFAULT 2,
        layout_version INTEGER NOT NULL DEFAULT 3
    );").map_err(|_| "Could not prepare local sync state".to_string())?;
    let has_derivative_version = db.prepare("PRAGMA table_info(sync_items)")
        .map_err(|_| "Could not inspect local sync state".to_string())?
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|_| "Could not inspect local sync state".to_string())?
        .any(|column| matches!(column, Ok(name) if name == "derivative_version"));
    if !has_derivative_version {
        db.execute_batch("ALTER TABLE sync_items ADD COLUMN derivative_version INTEGER NOT NULL DEFAULT 1")
            .map_err(|_| "Could not upgrade local sync state".to_string())?;
    }
    db.execute("UPDATE sync_items SET state=CASE WHEN state='synced' THEN 'not_synced' ELSE state END,
        thumbnail_done=0, manifest_done=0, synced_at=NULL, derivative_version=2
        WHERE derivative_version<2", [])
        .map_err(|_| "Could not queue updated thumbnails".to_string())?;
    let has_layout_version = db.prepare("PRAGMA table_info(sync_items)")
        .map_err(|error| error.to_string())?
        .query_map([], |row| row.get::<_, String>(1)).map_err(|error| error.to_string())?
        .any(|column| matches!(column, Ok(name) if name == "layout_version"));
    if !has_layout_version {
        db.execute_batch("ALTER TABLE sync_items ADD COLUMN layout_version INTEGER NOT NULL DEFAULT 2")
            .map_err(|error| error.to_string())?;
    }
    db.execute("UPDATE sync_items SET state='not_synced',original_done=0,preview_done=0,
        thumbnail_done=0,manifest_done=0,synced_at=NULL,error=NULL,layout_version=3
        WHERE layout_version<3", []).map_err(|error| error.to_string())?;
    Ok(())
}

fn target(config: &cloud::S3Config) -> String { format!("{}/{}", config.bucket, config.prefix) }

fn reconcile_remote(db: &Connection, target: &str) -> Result<(), String> {
    // A cloud manifest is written last, after all three media objects. A matching
    // version-3 manifest proves that this exact content hash is already backed up.
    db.execute("INSERT OR IGNORE INTO sync_items
        (asset_id,target,state,original_done,preview_done,thumbnail_done,manifest_done,synced_at,derivative_version,layout_version)
        SELECT a.id,?1,'synced',1,1,1,1,datetime('now'),2,3
        FROM assets a JOIN remote_assets r ON r.asset_id=a.id
        WHERE a.source_path<>'' AND r.manifest_version=3", params![target])
        .map_err(|error| format!("Could not reconcile cloud backups: {error}"))?;
    db.execute("UPDATE sync_items SET state='synced',original_done=1,preview_done=1,
        thumbnail_done=1,manifest_done=1,synced_at=datetime('now'),error=NULL,derivative_version=2,layout_version=3
        WHERE target=?1 AND state='not_synced' AND original_done=0 AND preview_done=0
        AND thumbnail_done=0 AND manifest_done=0
        AND asset_id IN (SELECT a.id FROM assets a JOIN remote_assets r ON r.asset_id=a.id
            WHERE a.source_path<>'' AND r.manifest_version=3)", params![target])
        .map_err(|error| format!("Could not reconcile cloud backups: {error}"))?;
    Ok(())
}

fn active_target(db: &Connection) -> Result<Option<String>, String> {
    let exists: bool = db.query_row("SELECT 1 FROM sqlite_master WHERE type='table' AND name='s3_connection'",
        [], |_| Ok(true)).optional().map_err(|error| error.to_string())?.unwrap_or(false);
    if !exists { return Ok(None); }
    db.query_row("SELECT bucket || '/' || prefix FROM s3_connection WHERE id=1", [], |row| row.get(0))
        .optional().map_err(|error| error.to_string())
}

fn enqueue(db: &Connection, target: &str) -> Result<(), String> {
    prepare_schema(db)?;
    reconcile_remote(db, target)?;
    db.execute("INSERT OR IGNORE INTO sync_items (asset_id, target, state)
        SELECT id, ?1, 'not_synced' FROM assets WHERE source_path<>''", params![target])
        .map_err(|_| "Could not queue imported photos".to_string())?;
    db.execute("UPDATE sync_items SET target=?1, state='not_synced', original_done=0,
        preview_done=0, thumbnail_done=0, manifest_done=0, synced_at=NULL, error=NULL
        WHERE target<>?1", params![target])
        .map_err(|_| "Could not reset sync state for this bucket".to_string())?;
    db.execute("UPDATE sync_items SET state='not_synced' WHERE state IN ('preparing','uploading')", [])
        .map_err(|_| "Could not resume interrupted sync".to_string())?;
    Ok(())
}

fn read_status(db: &Connection, running: bool) -> Result<SyncStatus, String> {
    prepare_schema(db)?;
    if let Some(target) = active_target(db)? { reconcile_remote(db, &target)?; }
    let (mut total, mut not_synced, preparing, uploading, synced, failed): (i64,i64,i64,i64,i64,i64) = db.query_row(
        "SELECT COUNT(*),
          COALESCE(SUM(CASE WHEN COALESCE(s.state,'not_synced')='not_synced' THEN 1 ELSE 0 END),0),
          COALESCE(SUM(CASE WHEN s.state='preparing' THEN 1 ELSE 0 END),0),
          COALESCE(SUM(CASE WHEN s.state='uploading' THEN 1 ELSE 0 END),0),
          COALESCE(SUM(CASE WHEN s.state='synced' THEN 1 ELSE 0 END),0),
          COALESCE(SUM(CASE WHEN s.state='failed' THEN 1 ELSE 0 END),0)
         FROM assets a LEFT JOIN sync_items s ON s.asset_id=a.id WHERE a.source_path<>''", [],
        |row| Ok((row.get(0)?,row.get(1)?,row.get(2)?,row.get(3)?,row.get(4)?,row.get(5)?))
    ).map_err(|_| "Could not read sync progress".to_string())?;
    let phone_waiting: i64 = db.query_row("SELECT COUNT(*) FROM phone_media WHERE asset_id IS NULL", [], |row| row.get(0))
        .map_err(|_| "Could not read phone backup progress".to_string())?;
    total += phone_waiting;
    not_synced += phone_waiting;
    let current_name = db.query_row("SELECT a.filename FROM assets a JOIN sync_items s ON s.asset_id=a.id
        WHERE s.state IN ('preparing','uploading') ORDER BY a.filename LIMIT 1", [], |row| row.get(0))
        .optional().map_err(|_| "Could not read current photo".to_string())?;
    let last_error = db.query_row("SELECT error FROM sync_items WHERE state='failed' AND error IS NOT NULL LIMIT 1", [], |row| row.get(0))
        .optional().map_err(|_| "Could not read sync error".to_string())?;
    Ok(SyncStatus { running, cancelling: false, cancelled: false, total, not_synced, preparing, uploading, synced, failed, current_name, last_error })
}

fn item(db: &Connection, id: &str) -> Result<Item, String> {
    db.query_row("SELECT id, filename, source_path, preview_path, taken_at, collection, favorite,
        description, latitude, longitude, altitude, takeout_json FROM assets WHERE id=?1", params![id], |row| Ok(Item {
        filename: row.get(1)?, source_path: PathBuf::from(row.get::<_, String>(2)?),
        preview_path: PathBuf::from(row.get::<_, String>(3)?), taken_at: row.get(4)?, collection: row.get(5)?,
        favorite: row.get::<_, i64>(6)? != 0, description: row.get(7)?, latitude: row.get(8)?,
        longitude: row.get(9)?, altitude: row.get(10)?,
        takeout: row.get::<_, Option<String>>(11)?.and_then(|text| serde_json::from_str(&text).ok()),
    })).map_err(|_| "Could not read queued photo".to_string())
}

fn source_records(db: &Connection, id: &str, item: &Item) -> Result<Vec<serde_json::Value>, String> {
    let exists = db.query_row("SELECT 1 FROM sqlite_master WHERE type='table' AND name='import_sources'",
        [], |_| Ok(true)).optional().map_err(|error| error.to_string())?.unwrap_or(false);
    let mut sources = Vec::new();
    if exists {
        let mut statement = db.prepare("SELECT source_id,source_label,relative_path,takeout_json,metadata_version FROM import_sources
            WHERE asset_id=?1 ORDER BY source_label,relative_path").map_err(|error| error.to_string())?;
        let rows = statement.query_map(params![id], |row| Ok((
            row.get::<_, String>(0)?, row.get::<_, String>(1)?, row.get::<_, String>(2)?, row.get::<_, Option<String>>(3)?, row.get::<_, i64>(4)?
        ))).map_err(|error| error.to_string())?;
        for row in rows {
            let (source_id, label, path, takeout, version) = row.map_err(|error| error.to_string())?;
            if version < 1 { return Err("Scan all photo folders in Settings → Photos before backing up, so their Takeout metadata and folder paths are preserved.".into()); }
            sources.push(json!({"sourceId":source_id, "sourceLabel":label, "relativePath":path,
                "takeout":takeout.and_then(|value| serde_json::from_str::<serde_json::Value>(&value).ok())}));
        }
    }
    if sources.is_empty() && phone_media::source_media_id(&item.source_path).is_none() {
        return Err("Scan all photo folders in Settings → Photos before backing up, so their Takeout metadata and folder paths are preserved.".into());
    }
    if sources.is_empty() && phone_media::source_media_id(&item.source_path).is_some() {
        sources.push(json!({"sourceLabel":item.collection, "relativePath":item.filename}));
    }
    Ok(sources)
}

fn set_state(db: &Connection, id: &str, state: &str, error: Option<&str>) -> Result<(), String> {
    db.execute("UPDATE sync_items SET state=?2, error=?3 WHERE asset_id=?1", params![id,state,error])
        .map_err(|_| "Could not save sync progress".to_string())?;
    Ok(())
}

fn jpeg(image: &DynamicImage, path: &Path, quality: u8) -> Result<(), String> {
    let temporary = path.with_extension("jpg.partial");
    let result = (|| -> Result<(), String> {
        let mut output = fs::File::create(&temporary).map_err(|_| "Could not create local derivative".to_string())?;
        JpegEncoder::new_with_quality(&mut output, quality).encode_image(&image.to_rgb8())
            .map_err(|_| "Could not encode JPEG derivative".to_string())?;
        output.sync_all().map_err(|_| "Could not finish local derivative".to_string())?;
        drop(output);
        fs::rename(&temporary, path).map_err(|_| "Could not publish local derivative".to_string())
    })();
    if result.is_err() { let _ = fs::remove_file(&temporary); }
    result
}

fn copy_small_jpeg(source: &Path, preview: &Path) -> Result<(), String> {
    let temporary = preview.with_extension("jpg.partial");
    let result = (|| -> Result<(), String> {
        fs::copy(source, &temporary).map_err(|_| "Could not copy small JPEG preview".to_string())?;
        fs::OpenOptions::new().write(true).open(&temporary).and_then(|file| file.sync_all())
            .map_err(|_| "Could not finish small JPEG preview".to_string())?;
        fs::rename(&temporary, preview).map_err(|_| "Could not publish small JPEG preview".to_string())
    })();
    if result.is_err() { let _ = fs::remove_file(&temporary); }
    result
}

fn thumbnail_dimensions(width: u32, height: u32) -> (u32, u32) {
    let short = width.min(height);
    if short == 0 { return (width, height); }
    let scaled = |long: u32| ((u64::from(long) * 320 + u64::from(short) / 2) / u64::from(short)) as u32;
    if width <= height { (320, scaled(height)) } else { (scaled(width), 320) }
}

pub(crate) fn derivatives(source: &Path, directory: &Path) -> Result<(PathBuf, PathBuf, u32, u32), String> {
    fs::create_dir_all(directory).map_err(|_| "Could not create derivative cache".to_string())?;
    let preview = directory.join("preview.jpg");
    let thumbnail = directory.join("thumbnail-v2.jpg");
    let (source_width, source_height) = image::image_dimensions(source)
        .map_err(|_| "Could not read image dimensions".to_string())?;
    if u64::from(source_width) * u64::from(source_height) > 100_000_000 {
        return Err("Photo exceeds the 100-megapixel safety limit".into());
    }
    let decoder = ImageReader::open(source).map_err(|_| "Could not open photo for preview".to_string())?
        .into_decoder().map_err(|_| "Unsupported photo format for preview".to_string())?;
    let mut decoder = decoder;
    let orientation = decoder.orientation().map_err(|_| "Could not read photo orientation".to_string())?;
    let mut image = DynamicImage::from_decoder(decoder).map_err(|_| "Could not decode photo".to_string())?;
    image.apply_orientation(orientation);
    let (width, height) = (image.width(), image.height());
    if !preview.is_file() {
        let small_jpeg = matches!(source.extension().and_then(|value| value.to_str()).map(str::to_ascii_lowercase).as_deref(), Some("jpg" | "jpeg"))
            && fs::metadata(source).map(|value| value.len() <= 512 * 1024).unwrap_or(false)
            && width <= 1920 && height <= 1920 && orientation == Orientation::NoTransforms;
        if small_jpeg { copy_small_jpeg(source, &preview)?; }
        else { jpeg(&image.resize(1920, 1920, FilterType::Lanczos3), &preview, 82)?; }
    }
    if !thumbnail.is_file() {
        let (thumb_width, thumb_height) = thumbnail_dimensions(width, height);
        jpeg(&image.resize_exact(thumb_width, thumb_height, FilterType::Triangle), &thumbnail, 76)?;
    }
    Ok((preview, thumbnail, width, height))
}

async fn put_file(client: &aws_sdk_s3::Client, bucket: &str, key: &str, path: &Path, mime: &str) -> Result<(), String> {
    let body = ByteStream::from_path(path).await.map_err(|_| "Could not open photo for upload".to_string())?;
    client.put_object().bucket(bucket).key(key).content_type(mime).body(body).send().await
        .map_err(|_| "S3 upload failed. Check network access and PutObject permission, then retry.".to_string())?;
    Ok(())
}

async fn put_json(client: &aws_sdk_s3::Client, bucket: &str, key: &str, value: serde_json::Value) -> Result<(), String> {
    let bytes = serde_json::to_vec(&value).map_err(|_| "Could not encode photo manifest".to_string())?;
    client.put_object().bucket(bucket).key(key).content_type("application/json")
        .body(ByteStream::from(bytes)).send().await
        .map_err(|_| "S3 manifest upload failed. Check PutObject permission, then retry.".to_string())?;
    Ok(())
}

fn stop_if_requested(db: &Connection, id: &str, should_cancel: &dyn Fn() -> bool) -> Result<bool, String> {
    if !should_cancel() { return Ok(false); }
    set_state(db, id, "not_synced", None)?;
    Ok(true)
}

async fn upload_one(db: &Connection, cache: &Path, client: &aws_sdk_s3::Client,
    config: &cloud::S3Config, id: &str, should_cancel: &dyn Fn() -> bool,
    app: Option<&AppHandle>) -> Result<bool, String> {
    let item = item(db, id)?;
    let sources = source_records(db, id, &item)?;
    set_state(db, id, "preparing", None)?;
    if stop_if_requested(db, id, should_cancel)? { return Ok(false); }
    let staged = if let Some(media_id) = phone_media::source_media_id(&item.source_path) {
        Some(phone_media::stage_original(app.ok_or("Phone photo access is unavailable")?, media_id, id)?)
    } else { None };
    let source = if let Some(staged) = &staged { staged.0.as_path() }
        else if item.source_path.is_file() { &item.source_path } else { &item.preview_path };
    if !source.is_file() { return Err("Original photo is missing on this device".into()); }
    if crate::file_hash(source)? != id { return Err("Original photo changed since import; reimport before syncing".into()); }
    let extension = item.filename.rsplit('.').next().unwrap_or("jpg").to_ascii_lowercase();
    let mime = match extension.as_str() { "png" => "image/png", "gif" => "image/gif", "webp" => "image/webp", _ => "image/jpeg" };
    let asset_prefix = format!("{}assets/{}/{}/", config.prefix, &id[..2], id);
    let original_key = format!("{asset_prefix}original.{extension}");
    let preview_key = format!("{asset_prefix}preview.jpg");
    let thumbnail_key = format!("{asset_prefix}thumbnail.jpg");
    let manifest_key = format!("{}catalog/assets/{}.json", config.prefix, id);
    let (preview, thumbnail, width, height) = derivatives(source, &cache.join(id))?;
    if stop_if_requested(db, id, should_cancel)? { return Ok(false); }
    set_state(db, id, "uploading", None)?;
    let flags: (i64,i64,i64,i64) = db.query_row("SELECT original_done, preview_done, thumbnail_done, manifest_done
        FROM sync_items WHERE asset_id=?1", params![id], |row| Ok((row.get(0)?,row.get(1)?,row.get(2)?,row.get(3)?)))
        .map_err(|_| "Could not read upload progress".to_string())?;
    if flags.0 == 0 {
        put_file(client, &config.bucket, &original_key, source, mime).await?;
        db.execute("UPDATE sync_items SET original_done=1 WHERE asset_id=?1", params![id]).map_err(|_| "Could not record original upload".to_string())?;
    }
    if stop_if_requested(db, id, should_cancel)? { return Ok(false); }
    if flags.1 == 0 {
        put_file(client, &config.bucket, &preview_key, &preview, "image/jpeg").await?;
        db.execute("UPDATE sync_items SET preview_done=1 WHERE asset_id=?1", params![id]).map_err(|_| "Could not record preview upload".to_string())?;
    }
    if stop_if_requested(db, id, should_cancel)? { return Ok(false); }
    if flags.2 == 0 {
        put_file(client, &config.bucket, &thumbnail_key, &thumbnail, "image/jpeg").await?;
        db.execute("UPDATE sync_items SET thumbnail_done=1 WHERE asset_id=?1", params![id]).map_err(|_| "Could not record thumbnail upload".to_string())?;
    }
    if stop_if_requested(db, id, should_cancel)? { return Ok(false); }
    let original_size = fs::metadata(source).map_err(|_| "Could not measure original".to_string())?.len();
    let preview_size = fs::metadata(&preview).map_err(|_| "Could not measure preview".to_string())?.len();
    let thumbnail_size = fs::metadata(&thumbnail).map_err(|_| "Could not measure thumbnail".to_string())?.len();
    let (thumb_width, thumb_height) = image::image_dimensions(&thumbnail)
        .map_err(|_| "Could not measure thumbnail dimensions".to_string())?;
    if flags.3 == 0 {
        put_json(client, &config.bucket, &manifest_key, json!({
            "version": 3, "id": id, "filename": item.filename, "takenAt": item.taken_at,
            "sources": sources, "takeout": item.takeout,
            "collection": item.collection, "favorite": item.favorite, "description": item.description,
            "latitude": item.latitude, "longitude": item.longitude, "altitude": item.altitude,
            "width": width, "height": height,
            "original": {"key": original_key, "bytes": original_size, "mime": mime},
            "preview": {"key": preview_key, "bytes": preview_size, "mime": "image/jpeg"},
            "thumbnail": {"key": thumbnail_key, "bytes": thumbnail_size, "mime": "image/jpeg",
                "width": thumb_width, "height": thumb_height}
        })).await?;
        db.execute("UPDATE sync_items SET manifest_done=1 WHERE asset_id=?1", params![id]).map_err(|_| "Could not record manifest upload".to_string())?;
    }
    let committed = db.execute("UPDATE sync_items SET state='synced', error=NULL, synced_at=?2 WHERE asset_id=?1
        AND (SELECT favorite FROM assets WHERE id=?1)=?3",
        params![id, Utc::now().to_rfc3339(), item.favorite as i64])
        .map_err(|_| "Could not record completed photo".to_string())?;
    if committed == 0 {
        db.execute("UPDATE sync_items SET state='not_synced', manifest_done=0 WHERE asset_id=?1", params![id])
            .map_err(|_| "Could not queue updated metadata".to_string())?;
    }
    Ok(true)
}

fn validated_selection(db: &Connection, ids: &[String]) -> Result<Vec<String>, String> {
    if ids.is_empty() || ids.len() > 5000 { return Err("Select between 1 and 5000 photos".into()); }
    let mut seen = HashSet::new();
    let mut selected = Vec::new();
    for id in ids {
        let hash = id.len() == 64 && id.bytes().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase());
        let phone = phone_media::has_phone_id(db, id)?;
        if !hash && !phone {
            return Err("A selected photo ID is invalid".into());
        }
        if !seen.insert(id.clone()) { continue; }
        let exists = phone || db.query_row("SELECT 1 FROM assets WHERE id=?1", params![id], |_| Ok(true))
            .optional().map_err(|_| "Could not check the selected photos".to_string())?.unwrap_or(false);
        if !exists { return Err("A selected photo is no longer in the library".into()); }
        selected.push(id.clone());
    }
    Ok(selected)
}

async fn run_selected_with_cancel(database_path: &Path, cache: &Path, selected: Option<Vec<String>>,
    should_cancel: &dyn Fn() -> bool, app: Option<&AppHandle>) -> Result<SyncStatus, String> {
    let db = open_database(database_path)?;
    prepare_schema(&db)?;
    let (config, client) = cloud::upload_connection(&db)?;
    let ids = if let Some(selected) = selected {
        let mut queued = Vec::new();
        for id in validated_selection(&db, &selected)? {
            if should_cancel() { break; }
            let id = if id.starts_with("phone-") {
                phone_media::prepare_for_backup(app.ok_or("Phone photo access is unavailable")?, &db, &id)?
            } else { id };
            enqueue(&db, &target(&config))?;
            let state: Option<String> = db.query_row("SELECT state FROM sync_items WHERE asset_id=?1", params![id], |row| row.get(0))
                .optional().map_err(|_| "Could not read selected backup state".to_string())?;
            if matches!(state.as_deref(), Some(state) if state != "synced") { queued.push(id); }
        }
        queued
    } else {
        enqueue(&db, &target(&config))?;
        let mut statement = db.prepare("SELECT asset_id FROM sync_items WHERE state<>'synced' ORDER BY asset_id")
            .map_err(|_| "Could not read sync queue".to_string())?;
        let queued = statement.query_map([], |row| row.get(0))
            .map_err(|_| "Could not read sync queue".to_string())?
            .collect::<rusqlite::Result<Vec<String>>>().map_err(|_| "Could not read sync queue".to_string())?;
        queued
    };
    for id in ids {
        if should_cancel() { break; }
        match upload_one(&db, cache, &client, &config, &id, should_cancel, app).await {
            Ok(true) => {},
            Ok(false) => break,
            Err(error) => {
                set_state(&db, &id, "failed", Some(&error))?;
                if error.starts_with("S3 ") || error.starts_with("Scan all photo folders") { break; }
            }
        }
    }
    if !should_cancel() { events::upload_pending(&db, &client, &config).await?; }
    read_status(&db, false)
}

pub async fn run_selected(database_path: &Path, cache: &Path, selected: Option<Vec<String>>) -> Result<SyncStatus, String> {
    run_selected_with_cancel(database_path, cache, selected, &|| false, None).await
}

pub async fn run_once(database_path: &Path, cache: &Path) -> Result<SyncStatus, String> {
    run_selected(database_path, cache, None).await
}

fn paths(app: &AppHandle) -> Result<(PathBuf, PathBuf), String> {
    let data = app.path().app_data_dir().map_err(|_| "Could not locate app data".to_string())?;
    let cache = app.path().app_cache_dir().map_err(|_| "Could not locate app cache".to_string())?;
    Ok((data.join("gallery.sqlite"), cache.join("sync-derivatives")))
}

#[tauri::command]
pub fn get_sync_status(app: AppHandle, runner: State<'_, SyncRunner>) -> Result<SyncStatus, String> {
    let (database, _) = paths(&app)?;
    let (running, cancelling, cancelled) = runner.status();
    let mut status = read_status(&open_database(&database)?, running)?;
    status.cancelling = cancelling;
    status.cancelled = cancelled;
    Ok(status)
}

#[tauri::command]
pub fn start_sync(app: AppHandle, runner: State<'_, SyncRunner>) -> Result<SyncStatus, String> {
    if !runner.begin() { return get_sync_status(app, runner); }
    let (database, cache) = match paths(&app) {
        Ok(paths) => paths,
        Err(error) => { runner.finish(); return Err(error); }
    };
    let app_for_task = app.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let runner = app_for_task.state::<SyncRunner>();
        if let Err(error) = tauri::async_runtime::block_on(run_selected_with_cancel(&database, &cache, None,
            &|| runner.cancellation_requested(), Some(&app_for_task))) { eprintln!("Gallery sync error: {error}"); }
        runner.finish();
    });
    get_sync_status(app, runner)
}

#[tauri::command]
pub fn cancel_sync(app: AppHandle, runner: State<'_, SyncRunner>) -> Result<SyncStatus, String> {
    runner.request_cancel();
    get_sync_status(app, runner)
}

#[tauri::command]
pub fn start_sync_selected(app: AppHandle, runner: State<'_, SyncRunner>, ids: Vec<String>) -> Result<SyncStatus, String> {
    let (database, cache) = paths(&app)?;
    let connection = open_database(&database)?;
    let ids = validated_selection(&connection, &ids)?;
    let _ = cloud::upload_connection(&connection)?;
    drop(connection);
    if !runner.begin() { return Err("A backup is already running. Try again when it finishes.".into()); }
    let app_for_task = app.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let runner = app_for_task.state::<SyncRunner>();
        if let Err(error) = tauri::async_runtime::block_on(run_selected_with_cancel(&database, &cache, Some(ids),
            &|| runner.cancellation_requested(), Some(&app_for_task))) {
            eprintln!("Gallery selected sync error: {error}");
        }
        runner.finish();
    });
    get_sync_status(app, runner)
}

pub fn run_cli() -> Result<SyncStatus, String> {
    let roaming = std::env::var_os("APPDATA").ok_or_else(|| "Windows app data is unavailable".to_string())?;
    let local = std::env::var_os("LOCALAPPDATA").ok_or_else(|| "Windows local app data is unavailable".to_string())?;
    let database = PathBuf::from(roaming).join("com.pshand.gallery").join("gallery.sqlite");
    let cache = PathBuf::from(local).join("com.pshand.gallery").join("sync-derivatives");
    tauri::async_runtime::block_on(run_once(&database, &cache))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn failed_derivative_publish_cleans_temporary_file() {
        let root = std::env::temp_dir().join(format!("gallery-jpeg-cleanup-{}",std::process::id()));
        fs::create_dir_all(root.join("preview.jpg")).unwrap();
        assert!(jpeg(&DynamicImage::new_rgb8(16,16),&root.join("preview.jpg"),82).is_err());
        assert!(!root.join("preview.jpg.partial").exists());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn small_unrotated_jpeg_is_reused_as_preview() {
        let root = std::env::temp_dir().join(format!("gallery-small-preview-{}",std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let source = root.join("source.jpg");
        DynamicImage::new_rgb8(600,400).save(&source).unwrap();
        let cache = root.join("cache");
        let (preview,thumbnail,width,height) = derivatives(&source,&cache).unwrap();
        assert_eq!((width,height),(600,400));
        assert_eq!(fs::read(&preview).unwrap(),fs::read(&source).unwrap());
        assert_eq!(image::image_dimensions(thumbnail).unwrap(),(480,320));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn generates_bounded_jpegs_without_changing_source() {
        let root = std::env::temp_dir().join(format!("gallery-derivatives-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let source = root.join("source.png");
        let image = DynamicImage::new_rgb8(2400, 1200);
        image.save(&source).unwrap();
        let original = fs::read(&source).unwrap();
        let cache = root.join("cache");
        fs::create_dir_all(&cache).unwrap();
        DynamicImage::new_rgb8(320, 320).save(cache.join("thumbnail.jpg")).unwrap();
        let (preview, thumb, width, height) = derivatives(&source, &cache).unwrap();
        assert_eq!((width, height), (2400, 1200));
        assert_eq!(image::image_dimensions(&preview).unwrap(), (1920, 960));
        assert_eq!(image::image_dimensions(&thumb).unwrap(), (640, 320));
        assert_eq!(image::image_dimensions(cache.join("thumbnail.jpg")).unwrap(), (320, 320));
        assert_eq!(thumbnail_dimensions(1200, 2400), (320, 640));
        assert_eq!(thumbnail_dimensions(200, 100), (640, 320));
        assert_eq!(fs::read(&source).unwrap(), original);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn old_sync_state_requeues_only_thumbnail_and_manifest() {
        let db = Connection::open_in_memory().unwrap();
        db.execute_batch("CREATE TABLE sync_items (
            asset_id TEXT PRIMARY KEY, target TEXT NOT NULL, state TEXT NOT NULL,
            original_done INTEGER NOT NULL, preview_done INTEGER NOT NULL,
            thumbnail_done INTEGER NOT NULL, manifest_done INTEGER NOT NULL,
            synced_at TEXT, error TEXT);
            INSERT INTO sync_items VALUES ('abc','bucket/gallery/','synced',1,1,1,1,'yesterday',NULL);")
            .unwrap();
        prepare_schema(&db).unwrap();
        let row: (String, i64, i64, i64, i64, i64) = db.query_row(
            "SELECT state, original_done, preview_done, thumbnail_done, manifest_done, derivative_version
             FROM sync_items WHERE asset_id='abc'", [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?, row.get(5)?))
        ).unwrap();
        assert_eq!(row, ("not_synced".into(), 0, 0, 0, 0, 2));
        prepare_schema(&db).unwrap();
        let pending: i64 = db.query_row("SELECT COUNT(*) FROM sync_items WHERE state='not_synced'", [], |row| row.get(0)).unwrap();
        assert_eq!(pending, 1);
    }

    #[test]
    fn old_import_source_schema_upgrades_before_backup() {
        let root = std::env::temp_dir().join(format!("gallery-source-schema-{}",std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let path = root.join("gallery.sqlite");
        let legacy = Connection::open(&path).unwrap();
        legacy.execute_batch("CREATE TABLE import_sources (
            path TEXT PRIMARY KEY, bytes INTEGER NOT NULL, modified_ns INTEGER NOT NULL,
            asset_id TEXT NOT NULL);
            INSERT INTO import_sources VALUES ('C:/Photos/one.jpg',100,1,'asset');").unwrap();
        drop(legacy);
        let db = open_database(&path).unwrap();
        db.execute("INSERT INTO assets(id,filename,source_path,preview_path,taken_at,collection)
            VALUES ('asset','one.jpg','C:/Photos/one.jpg','','2020-01-01','Photos')",[]).unwrap();
        let photo = item(&db,"asset").unwrap();
        assert!(source_records(&db,"asset",&photo).unwrap_err().contains("Scan all photo folders"));
        db.execute("UPDATE import_sources SET source_id='root',source_label='Photos',
            relative_path='one.jpg',metadata_version=1 WHERE asset_id='asset'",[]).unwrap();
        let sources = source_records(&db,"asset",&photo).unwrap();
        assert_eq!(sources[0]["relativePath"],"one.jpg");
        drop(db);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn imported_local_photo_reuses_matching_cloud_manifest() {
        let root = std::env::temp_dir().join(format!("gallery-reconcile-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let db = open_database(&root.join("catalogue.sqlite")).unwrap();
        db.execute_batch("CREATE TABLE s3_connection (id INTEGER PRIMARY KEY,bucket TEXT,prefix TEXT);
            INSERT INTO s3_connection VALUES (1,'bucket','gallery/');
            INSERT INTO assets(id,filename,source_path,preview_path,taken_at,collection)
                VALUES ('already','photo.jpg','local','preview','2024-01-01','Photos'),
                       ('new','new.jpg','local','preview','2024-01-01','Photos');
            INSERT INTO remote_assets(asset_id,original_key,original_bytes,preview_key,preview_bytes,
                thumbnail_key,thumbnail_bytes,manifest_version)
                VALUES ('already','gallery/originals/already.jpg',1,'gallery/previews/already.jpg',1,
                    'gallery/thumbnails/already.jpg',1,3);") .unwrap();
        let status = read_status(&db, false).unwrap();
        assert_eq!((status.total,status.synced,status.not_synced),(2,1,1));
        enqueue(&db,"bucket/gallery/").unwrap();
        let states: Vec<(String,String)> = db.prepare("SELECT asset_id,state FROM sync_items ORDER BY asset_id")
            .unwrap().query_map([], |row| Ok((row.get(0)?,row.get(1)?))).unwrap()
            .collect::<rusqlite::Result<_>>().unwrap();
        assert_eq!(states,vec![("already".into(),"synced".into()),("new".into(),"not_synced".into())]);
        drop(db);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn interrupted_queue_keeps_completed_objects_and_new_target_resets_them() {
        let root = std::env::temp_dir().join(format!("gallery-sync-queue-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let db = open_database(&root.join("catalogue.sqlite")).unwrap();
        db.execute("INSERT INTO assets (id, filename, source_path, preview_path, taken_at, collection)
            VALUES ('abc','photo.jpg','source','preview','2024-01-01T00:00:00Z','test')", []).unwrap();
        enqueue(&db, "first/gallery/").unwrap();
        db.execute("UPDATE sync_items SET state='uploading', original_done=1 WHERE asset_id='abc'", []).unwrap();
        enqueue(&db, "first/gallery/").unwrap();
        let state: (String, i64) = db.query_row("SELECT state, original_done FROM sync_items WHERE asset_id='abc'", [],
            |row| Ok((row.get(0)?, row.get(1)?))).unwrap();
        assert_eq!(state, ("not_synced".into(), 1));
        enqueue(&db, "second/gallery/").unwrap();
        let reset: (String, i64) = db.query_row("SELECT target, original_done FROM sync_items WHERE asset_id='abc'", [],
            |row| Ok((row.get(0)?, row.get(1)?))).unwrap();
        assert_eq!(reset, ("second/gallery/".into(), 0));
        drop(db);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn cancelling_preserves_completed_objects_for_resume() {
        let root = std::env::temp_dir().join(format!("gallery-cancel-sync-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let db = open_database(&root.join("catalogue.sqlite")).unwrap();
        db.execute("INSERT INTO assets (id, filename, source_path, preview_path, taken_at, collection)
            VALUES ('abc','photo.jpg','source','preview','2024-01-01T00:00:00Z','test')", []).unwrap();
        enqueue(&db, "first/gallery/").unwrap();
        db.execute("UPDATE sync_items SET state='uploading', original_done=1 WHERE asset_id='abc'", []).unwrap();

        let runner = SyncRunner::default();
        assert!(runner.begin());
        assert!(!runner.begin());
        runner.request_cancel();
        assert_eq!(runner.status(), (true, true, false));
        assert!(stop_if_requested(&db, "abc", &|| runner.cancellation_requested()).unwrap());
        let state: (String, i64) = db.query_row("SELECT state, original_done FROM sync_items WHERE asset_id='abc'", [],
            |row| Ok((row.get(0)?, row.get(1)?))).unwrap();
        assert_eq!(state, ("not_synced".into(), 1));
        runner.finish();
        assert_eq!(runner.status(), (false, false, true));
        assert!(runner.begin());
        assert_eq!(runner.status(), (true, false, false));
        runner.finish();
        drop(db);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn selection_is_deduplicated_and_requires_local_photos() {
        let root = std::env::temp_dir().join(format!("gallery-selected-sync-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let db = open_database(&root.join("catalogue.sqlite")).unwrap();
        let id = "a".repeat(64);
        db.execute("INSERT INTO assets (id, filename, source_path, preview_path, taken_at, collection)
            VALUES (?1,'photo.jpg','source','preview','2024-01-01T00:00:00Z','test')", params![id]).unwrap();
        assert_eq!(validated_selection(&db, &[id.clone(), id.clone()]).unwrap(), vec![id.clone()]);
        assert!(validated_selection(&db, &[]).is_err());
        assert!(validated_selection(&db, &["b".repeat(64)]).is_err());
        assert!(validated_selection(&db, &["../bad".into()]).is_err());
        drop(db);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    #[ignore = "requires GALLERY_LIVE_SYNC=1 and the configured personal S3 bucket"]
    fn uploads_one_real_photo_when_requested() {
        assert_eq!(std::env::var("GALLERY_LIVE_SYNC").as_deref(), Ok("1"));
        let roaming = PathBuf::from(std::env::var_os("APPDATA").unwrap());
        let local = PathBuf::from(std::env::var_os("LOCALAPPDATA").unwrap());
        let db = open_database(&roaming.join("com.pshand.gallery/gallery.sqlite")).unwrap();
        prepare_schema(&db).unwrap();
        let (config, client) = cloud::upload_connection(&db).unwrap();
        enqueue(&db, &target(&config)).unwrap();
        let id: Option<String> = db.query_row("SELECT asset_id FROM sync_items WHERE state<>'synced' ORDER BY asset_id LIMIT 1", [], |row| row.get(0)).optional().unwrap();
        if let Some(id) = id {
            let cache = local.join("com.pshand.gallery/sync-derivatives");
            assert!(tauri::async_runtime::block_on(upload_one(&db, &cache, &client, &config, &id, &|| false, None)).unwrap());
        }
        assert!(read_status(&db, false).unwrap().synced >= 1);
    }

    #[test]
    #[ignore = "requires GALLERY_LIVE_SYNC=1 and the configured personal S3 bucket"]
    fn uploads_real_collection_when_requested() {
        assert_eq!(std::env::var("GALLERY_LIVE_SYNC").as_deref(), Ok("1"));
        let status = run_cli().unwrap();
        println!("{} of {} synced; {} failed; {} remaining", status.synced, status.total, status.failed, status.not_synced);
        assert_eq!(status.total, 111);
        assert_eq!(status.synced, 111);
        assert_eq!(status.failed, 0);
    }

    #[test]
    #[ignore = "requires GALLERY_LIVE_SYNC=1 and the configured personal S3 bucket"]
    fn uploads_only_selected_real_photos_when_requested() {
        assert_eq!(std::env::var("GALLERY_LIVE_SYNC").as_deref(), Ok("1"));
        let roaming = PathBuf::from(std::env::var_os("APPDATA").unwrap());
        let local = PathBuf::from(std::env::var_os("LOCALAPPDATA").unwrap());
        let database_path = roaming.join("com.pshand.gallery/gallery.sqlite");
        let cache = local.join("com.pshand.gallery/sync-derivatives");
        let db = open_database(&database_path).unwrap();
        let mut statement = db.prepare("SELECT id FROM assets ORDER BY id LIMIT 3").unwrap();
        let ids: Vec<String> = statement.query_map([], |row| row.get(0)).unwrap().collect::<rusqlite::Result<_>>().unwrap();
        drop(statement);
        assert_eq!(ids.len(), 3);
        for id in &ids {
            db.execute("UPDATE sync_items SET state='not_synced', manifest_done=0, synced_at=NULL WHERE asset_id=?1", params![id]).unwrap();
        }
        drop(db);
        let first = tauri::async_runtime::block_on(run_selected(&database_path, &cache, Some(vec![ids[0].clone()]))).unwrap();
        assert_eq!((first.synced, first.not_synced, first.failed), (109, 2, 0));
        let finished = tauri::async_runtime::block_on(run_selected(&database_path, &cache, Some(ids[1..].to_vec()))).unwrap();
        assert_eq!((finished.synced, finished.not_synced, finished.failed), (111, 0, 0));
    }

    #[test]
    #[ignore = "requires GALLERY_LIVE_SYNC=1 and the configured personal S3 bucket"]
    fn verifies_remote_collection_when_requested() {
        assert_eq!(std::env::var("GALLERY_LIVE_SYNC").as_deref(), Ok("1"));
        let roaming = PathBuf::from(std::env::var_os("APPDATA").unwrap());
        let local = PathBuf::from(std::env::var_os("LOCALAPPDATA").unwrap());
        let db = open_database(&roaming.join("com.pshand.gallery/gallery.sqlite")).unwrap();
        let (config, client) = cloud::upload_connection(&db).unwrap();
        let response = tauri::async_runtime::block_on(client.list_objects_v2()
            .bucket(&config.bucket).prefix(&config.prefix).max_keys(1000).send()).unwrap();
        let keys: HashSet<String> = response.contents().iter().filter_map(|object| object.key().map(str::to_string)).collect();
        let mut ids = db.prepare("SELECT id FROM assets").unwrap();
        let ids: Vec<String> = ids.query_map([], |row| row.get(0)).unwrap().collect::<rusqlite::Result<_>>().unwrap();
        for id in &ids {
            let item = item(&db, id).unwrap();
            let derivative_dir = local.join("com.pshand.gallery/sync-derivatives").join(id);
            let (preview_width, preview_height) = image::image_dimensions(derivative_dir.join("preview.jpg")).unwrap();
            assert!(preview_width <= 1920 && preview_height <= 1920);
            let (thumb_width, thumb_height) = image::image_dimensions(derivative_dir.join("thumbnail-v2.jpg")).unwrap();
            assert_eq!(thumb_width.min(thumb_height), 320);
            let extension = item.filename.rsplit('.').next().unwrap().to_ascii_lowercase();
            for key in [
                format!("{}originals/{}.{}", config.prefix, id, extension),
                format!("{}previews/{}.jpg", config.prefix, id),
                format!("{}thumbnails/{}.jpg", config.prefix, id),
                format!("{}catalog/assets/{}.json", config.prefix, id),
            ] { assert!(keys.contains(&key), "one of the four objects is missing"); }
        }
        let sample_id = ids.first().unwrap();
        let sample_key = format!("{}catalog/assets/{}.json", config.prefix, sample_id);
        let manifest = tauri::async_runtime::block_on(async {
            let object = client.get_object().bucket(&config.bucket).key(sample_key).send().await.unwrap();
            object.body.collect().await.unwrap().into_bytes()
        });
        let manifest: serde_json::Value = serde_json::from_slice(&manifest).unwrap();
        assert_eq!(manifest["id"], sample_id.as_str());
        assert_eq!(manifest["version"], 2);
        let thumbnail_key = manifest["thumbnail"]["key"].as_str().unwrap();
        let thumbnail = tauri::async_runtime::block_on(async {
            let object = client.get_object().bucket(&config.bucket).key(thumbnail_key).send().await.unwrap();
            object.body.collect().await.unwrap().into_bytes()
        });
        let remote_image = image::load_from_memory(&thumbnail).unwrap();
        assert_eq!(u64::from(remote_image.width()), manifest["thumbnail"]["width"].as_u64().unwrap());
        assert_eq!(u64::from(remote_image.height()), manifest["thumbnail"]["height"].as_u64().unwrap());
        assert!(manifest.get("sourcePath").is_none());
        println!("Verified {} photos and {} required S3 objects", ids.len(), ids.len() * 4);
        assert_eq!(ids.len(), 111);
    }
}
