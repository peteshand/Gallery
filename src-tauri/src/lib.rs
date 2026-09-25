use chrono::{DateTime, Utc};
use rusqlite::{params, Connection};
use serde::Serialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::{BufReader, Read};
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Manager};

mod cloud;
mod backup_policy;
mod archive_import;
mod events;
mod media_cache;
mod phone_media;
#[cfg(target_os = "android")]
mod android_background;
mod remote;
mod sync;

pub fn sync_once_cli() -> Result<String, String> {
    let status = sync::run_cli()?;
    Ok(format!("{} of {} photos synced; {} failed; {} remaining", status.synced, status.total, status.failed, status.not_synced))
}

struct StderrLogger;

impl log::Log for StderrLogger {
    fn enabled(&self, metadata: &log::Metadata<'_>) -> bool {
        metadata.level() <= log::Level::Error
    }

    fn log(&self, record: &log::Record<'_>) {
        if self.enabled(record.metadata()) {
            eprintln!("Gallery native error: {}", record.args());
        }
    }

    fn flush(&self) {}
}

static STDERR_LOGGER: StderrLogger = StderrLogger;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Asset {
    pub(crate) id: String,
    pub(crate) filename: String,
    pub(crate) taken_at: String,
    pub(crate) collection: String,
    pub(crate) favorite: bool,
    pub(crate) media_url: String,
    pub(crate) thumbnail_url: Option<String>,
    pub(crate) description: Option<String>,
    pub(crate) latitude: Option<f64>,
    pub(crate) longitude: Option<f64>,
    pub(crate) altitude: Option<f64>,
    pub(crate) sync_state: String,
    pub(crate) synced_at: Option<String>,
    pub(crate) sync_error: Option<String>,
}

pub(crate) struct TakeoutMetadata {
    pub(crate) taken_at: Option<String>,
    pub(crate) description: Option<String>,
    pub(crate) latitude: Option<f64>,
    pub(crate) longitude: Option<f64>,
    pub(crate) altitude: Option<f64>,
    pub(crate) favorite: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ImportResult {
    scanned: usize,
    added: usize,
    existing: usize,
    errors: Vec<String>,
}

fn database(app: &AppHandle) -> Result<Connection, String> {
    let directory = app.path().app_data_dir().map_err(|error| error.to_string())?;
    open_database(&directory.join("gallery.sqlite"))
}

fn open_database(path: &Path) -> Result<Connection, String> {
    if let Some(directory) = path.parent() {
        fs::create_dir_all(directory).map_err(|error| error.to_string())?;
    }
    let connection = Connection::open(path).map_err(|error| error.to_string())?;
    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS assets (
                id TEXT PRIMARY KEY,
                filename TEXT NOT NULL,
                source_path TEXT NOT NULL,
                preview_path TEXT NOT NULL,
                taken_at TEXT NOT NULL,
                collection TEXT NOT NULL,
                favorite INTEGER NOT NULL DEFAULT 0,
                favorite_modified INTEGER NOT NULL DEFAULT 0,
                taken_at_source INTEGER NOT NULL DEFAULT 0,
                description TEXT,
                latitude REAL,
                longitude REAL,
                altitude REAL
            );",
        )
        .map_err(|error| error.to_string())?;
    connection.execute_batch("CREATE TABLE IF NOT EXISTS sync_items (
        asset_id TEXT PRIMARY KEY, target TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'not_synced',
        original_done INTEGER NOT NULL DEFAULT 0, preview_done INTEGER NOT NULL DEFAULT 0,
        thumbnail_done INTEGER NOT NULL DEFAULT 0, manifest_done INTEGER NOT NULL DEFAULT 0,
        synced_at TEXT, error TEXT, derivative_version INTEGER NOT NULL DEFAULT 2);").map_err(|error| error.to_string())?;
    connection.execute_batch("CREATE TABLE IF NOT EXISTS import_errors (
        path TEXT PRIMARY KEY, error TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 1,
        last_attempt_at TEXT NOT NULL);").map_err(|error| error.to_string())?;
    remote::prepare(&connection)?;
    media_cache::prepare(&connection)?;
    events::prepare(&connection)?;
    phone_media::prepare(&connection)?;
    backup_policy::prepare(&connection)?;
    let columns: HashSet<String> = connection
        .prepare("PRAGMA table_info(assets)")
        .map_err(|error| error.to_string())?
        .query_map([], |row| row.get(1))
        .map_err(|error| error.to_string())?
        .collect::<rusqlite::Result<_>>()
        .map_err(|error| error.to_string())?;
    for (name, definition) in [
        ("description", "TEXT"),
        ("latitude", "REAL"),
        ("longitude", "REAL"),
        ("altitude", "REAL"),
        ("favorite_modified", "INTEGER NOT NULL DEFAULT 0"),
        ("taken_at_source", "INTEGER NOT NULL DEFAULT 0"),
        ("favorite_clock", "INTEGER NOT NULL DEFAULT 0"),
        ("favorite_device", "TEXT NOT NULL DEFAULT ''"),
    ] {
        if !columns.contains(name) {
            connection
                .execute(&format!("ALTER TABLE assets ADD COLUMN {name} {definition}"), [])
                .map_err(|error| error.to_string())?;
        }
    }
    Ok(connection)
}

fn row_asset(row: &rusqlite::Row<'_>) -> rusqlite::Result<Asset> {
    Ok(Asset {
        id: row.get(0)?,
        filename: row.get(1)?,
        taken_at: row.get(2)?,
        collection: row.get(3)?,
        favorite: row.get::<_, i64>(4)? != 0,
        media_url: row.get(5)?,
        thumbnail_url: None,
        description: row.get(6)?,
        latitude: row.get(7)?,
        longitude: row.get(8)?,
        altitude: row.get(9)?,
        sync_state: row.get(10)?,
        synced_at: row.get(11)?,
        sync_error: row.get(12)?,
    })
}

fn local_derivatives(app: &AppHandle, asset: &mut Asset) -> Result<(), String> {
    if asset.media_url.is_empty() { return Ok(()); }
    let directory = app.path().app_cache_dir().map_err(|error| error.to_string())?
        .join("sync-derivatives").join(&asset.id);
    let preview = directory.join("preview.jpg");
    let thumbnail = directory.join("thumbnail-v2.jpg");
    if preview.is_file() { asset.media_url = preview.to_string_lossy().into_owned(); }
    if thumbnail.is_file() { asset.thumbnail_url = Some(thumbnail.to_string_lossy().into_owned()); }
    if asset.thumbnail_url.is_none() {
        let archive_thumbnail = Path::new(&asset.media_url).parent().map(|parent| parent.join("thumbnail-v2.jpg"));
        if let Some(path) = archive_thumbnail.filter(|path| path.is_file()) {
            asset.thumbnail_url = Some(path.to_string_lossy().into_owned());
        }
    }
    Ok(())
}

#[tauri::command]
fn list_assets(app: AppHandle) -> Result<Vec<Asset>, String> {
    let connection = database(&app)?;
    let mut statement = connection
        .prepare("SELECT id, filename, taken_at, collection, favorite, preview_path, description, latitude, longitude, altitude,
            COALESCE((SELECT state FROM sync_items WHERE asset_id=assets.id), CASE WHEN source_path='' AND NOT EXISTS
                (SELECT 1 FROM favorite_events WHERE asset_id=assets.id AND uploaded=0) THEN 'synced' ELSE 'not_synced' END),
            (SELECT synced_at FROM sync_items WHERE asset_id=assets.id),
            (SELECT error FROM sync_items WHERE asset_id=assets.id)
            FROM assets ORDER BY taken_at DESC, filename")
        .map_err(|error| error.to_string())?;
    let rows = statement.query_map([], row_asset).map_err(|error| error.to_string())?;
    let mut assets = rows.collect::<rusqlite::Result<Vec<Asset>>>().map_err(|error| error.to_string())?;
    for asset in &mut assets { local_derivatives(&app, asset)?; }
    assets.extend(phone_media::list_assets(&app, &connection)?);
    assets.sort_by(|a, b| b.taken_at.cmp(&a.taken_at).then_with(|| a.filename.cmp(&b.filename)));
    Ok(assets)
}

#[tauri::command]
fn set_favorite(app: AppHandle, id: String, favorite: bool) -> Result<Asset, String> {
    let mut connection = database(&app)?;
    let transaction = connection.transaction().map_err(|error| error.to_string())?;
    events::record_favorite(&transaction, &id, favorite)?;
    transaction.execute("UPDATE sync_items SET state='not_synced', manifest_done=0, synced_at=NULL
        WHERE asset_id=?1", params![id]).map_err(|error| error.to_string())?;
    transaction.commit().map_err(|error| error.to_string())?;
    let mut asset = connection
        .query_row(
            "SELECT id, filename, taken_at, collection, favorite, preview_path, description, latitude, longitude, altitude,
                COALESCE((SELECT state FROM sync_items WHERE asset_id=assets.id), CASE WHEN source_path='' AND NOT EXISTS
                    (SELECT 1 FROM favorite_events WHERE asset_id=assets.id AND uploaded=0) THEN 'synced' ELSE 'not_synced' END),
                (SELECT synced_at FROM sync_items WHERE asset_id=assets.id),
                (SELECT error FROM sync_items WHERE asset_id=assets.id)
                FROM assets WHERE id = ?1",
            params![id],
            row_asset,
        )
        .map_err(|error| error.to_string())?;
    local_derivatives(&app, &mut asset)?;
    Ok(asset)
}

pub(crate) fn sidecar_metadata(directory: &Path) -> HashMap<String, TakeoutMetadata> {
    let mut result = HashMap::new();
    let Ok(entries) = fs::read_dir(directory) else { return result };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        let Some(prefix) = name.strip_suffix(".json") else { continue };
        let (original, number) = if let Some(base) = prefix.strip_suffix(')') {
            let Some((before, number)) = base.rsplit_once(".supplemental-metadata(") else { continue };
            (before, Some(number))
        } else {
            let Some(before) = prefix.strip_suffix(".supplemental-metadata") else { continue };
            (before, None)
        };
        let media_name = if let Some(number) = number {
            let extension = Path::new(original).extension().and_then(|value| value.to_str()).unwrap_or("");
            let stem = original.strip_suffix(&format!(".{extension}")).unwrap_or(original);
            format!("{stem}({number}).{extension}")
        } else {
            original.to_string()
        };
        let Ok(bytes) = fs::read(entry.path()) else { continue };
        let Ok(json) = serde_json::from_slice::<Value>(&bytes) else { continue };
        let taken_at = json.pointer("/photoTakenTime/timestamp")
            .and_then(Value::as_str)
            .and_then(|value| value.parse::<i64>().ok())
            .and_then(|seconds| DateTime::<Utc>::from_timestamp(seconds, 0))
            .map(|date| date.to_rfc3339());
        let location = json.get("geoDataExif").or_else(|| json.get("geoData"));
        result.insert(media_name.to_lowercase(), TakeoutMetadata {
            taken_at,
            description: json.get("description").and_then(Value::as_str).filter(|value| !value.is_empty()).map(str::to_string),
            latitude: location.and_then(|value| value.get("latitude")).and_then(Value::as_f64),
            longitude: location.and_then(|value| value.get("longitude")).and_then(Value::as_f64),
            altitude: location.and_then(|value| value.get("altitude")).and_then(Value::as_f64),
            favorite: json.get("favorited").and_then(Value::as_bool).unwrap_or(false),
        });
    }
    result
}

pub(crate) fn file_hash(path: &Path) -> Result<String, String> {
    let file = File::open(path).map_err(|error| error.to_string())?;
    let mut reader = BufReader::new(file);
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let count = reader.read(&mut buffer).map_err(|error| error.to_string())?;
        if count == 0 { break; }
        hasher.update(&buffer[..count]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn import_directory(app: AppHandle, source: PathBuf) -> Result<ImportResult, String> {
    let cache = app.path().app_cache_dir().map_err(|error| error.to_string())?.join("previews");
    fs::create_dir_all(&cache).map_err(|error| error.to_string())?;
    app.asset_protocol_scope()
        .allow_directory(&cache, true)
        .map_err(|error| error.to_string())?;
    let database_path = app.path().app_data_dir().map_err(|error| error.to_string())?.join("gallery.sqlite");
    let runner = app.state::<archive_import::ImportRunner>();
    archive_import::import_archive(&source, &cache, &database_path, &runner)
}

#[tauri::command]
async fn import_source(app: AppHandle, source: Option<String>) -> Result<ImportResult, String> {
    let source = source
        .map(PathBuf::from)
        .or_else(configured_source)
        .ok_or_else(|| "Choose a photo folder in Settings before importing".to_string())?;
    let runner = app.state::<archive_import::ImportRunner>();
    if !runner.begin() { return Err("An import is already running".into()); }
    tauri::async_runtime::spawn_blocking(move || {
        let runner = app.state::<archive_import::ImportRunner>();
        let result = import_directory(app.clone(), source);
        runner.finish();
        result
    })
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
fn get_import_progress(app: AppHandle) -> archive_import::ImportProgress {
    app.state::<archive_import::ImportRunner>().status()
}

#[tauri::command]
fn cancel_import(app: AppHandle) {
    app.state::<archive_import::ImportRunner>().cancel();
}

#[tauri::command]
fn list_import_errors(app: AppHandle) -> Result<Vec<archive_import::ImportError>, String> {
    let directory = app.path().app_data_dir().map_err(|error| error.to_string())?;
    archive_import::list_errors(&directory.join("gallery.sqlite"))
}

fn configured_source() -> Option<PathBuf> {
    std::env::var_os("GALLERY_SOURCE").map(PathBuf::from).or_else(|| {
        if cfg!(target_os = "windows") { Some(PathBuf::from(r"I:\Photos\Best of Poe 2")) }
        else { None }
    })
}

#[tauri::command]
fn get_default_source() -> Option<String> {
    configured_source().map(|path| path.to_string_lossy().into_owned())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let _ = log::set_logger(&STDERR_LOGGER);
    log::set_max_level(log::LevelFilter::Error);
    tauri::Builder::default()
        .manage(sync::SyncRunner::default())
        .manage(archive_import::ImportRunner::default())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_gallery_media::init())
        .setup(|app| {
            let cache = app.path().app_cache_dir()?.join("previews");
            fs::create_dir_all(&cache)?;
            app.asset_protocol_scope().allow_directory(&cache, true)?;
            let derivatives = app.path().app_cache_dir()?.join("sync-derivatives");
            fs::create_dir_all(&derivatives)?;
            app.asset_protocol_scope().allow_directory(&derivatives, true)?;
            let cloud_media = app.path().app_cache_dir()?.join("cloud-media");
            fs::create_dir_all(&cloud_media)?;
            app.asset_protocol_scope().allow_directory(&cloud_media, true)?;
            let phone_media = app.path().app_cache_dir()?.join("phone-media");
            fs::create_dir_all(&phone_media)?;
            app.asset_protocol_scope().allow_directory(&phone_media, true)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![list_assets, import_source, get_import_progress, cancel_import, list_import_errors, set_favorite, get_default_source,
            cloud::get_s3_connection, cloud::save_s3_connection, cloud::remove_s3_connection,
            cloud::test_s3_connection, sync::get_sync_status, sync::start_sync, sync::cancel_sync, sync::start_sync_selected,
            remote::refresh_remote, remote::ensure_media, remote::download_original,
            remote::get_cache_status, remote::set_cache_limit,
            phone_media::get_phone_status, phone_media::request_phone_access, phone_media::refresh_phone_media,
            backup_policy::get_backup_preferences, backup_policy::set_backup_preferences])
        .run(tauri::generate_context!())
        .expect("error while running Gallery");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn imports_real_takeout_folder_when_requested() {
        let Ok(source) = std::env::var("GALLERY_REAL_SOURCE") else { return };
        let source = PathBuf::from(source);
        assert!(source.is_dir(), "real Takeout source must exist");
        let nonce = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        let root = std::env::temp_dir().join(format!("gallery-real-import-{nonce}"));
        let cache = root.join("cache");
        let database_path = root.join("catalogue.sqlite");
        let source_files = || -> Vec<(String, u64, SystemTime)> {
            let mut files: Vec<_> = fs::read_dir(&source).unwrap().filter_map(Result::ok)
                .filter_map(|entry| {
                    let metadata = entry.metadata().ok()?;
                    let modified = metadata.modified().ok()?;
                    metadata.is_file().then(|| (entry.file_name().to_string_lossy().into_owned(), metadata.len(), modified))
                }).collect();
            files.sort_by(|a, b| a.0.cmp(&b.0));
            files
        };
        let before = source_files();
        let first = archive_import::import_archive(&source, &cache, &database_path, &archive_import::ImportRunner::default()).unwrap();
        assert_eq!((first.scanned, first.added, first.existing, first.errors.len()), (111, 111, 0, 0));
        let second = archive_import::import_archive(&source, &cache, &database_path, &archive_import::ImportRunner::default()).unwrap();
        assert_eq!((second.scanned, second.added, second.existing, second.errors.len()), (111, 0, 111, 0));
        let connection = open_database(&database_path).unwrap();
        let counts: (i64, i64, i64, i64) = connection.query_row(
            "SELECT COUNT(*), SUM(favorite), COUNT(latitude), SUM(taken_at_source) FROM assets", [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        ).unwrap();
        assert_eq!(counts, (111, 74, 111, 111));
        let mut previews = connection.prepare("SELECT source_path, preview_path FROM assets").unwrap();
        let paths = previews.query_map([], |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))).unwrap();
        for path in paths {
            let (original, preview) = path.unwrap();
            let original = Path::new(&original);
            let preview = Path::new(&preview);
            assert!(original.is_file() && preview.is_file());
            assert!(preview.starts_with(&cache));
            assert!(image::image_dimensions(preview).unwrap().0 <= 1920);
        }
        drop(previews);
        assert_eq!(before, source_files(), "source files must remain unchanged");
        drop(connection);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn imports_takeout_metadata_into_an_older_catalogue_without_duplicates() {
        let nonce = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        let root = std::env::temp_dir().join(format!("gallery-native-smoke-{nonce}"));
        let source = root.join("photos");
        let cache = root.join("cache");
        let database_path = root.join("catalogue.sqlite");
        fs::create_dir_all(&source).unwrap();
        let first_image = image::RgbImage::from_pixel(64, 48, image::Rgb([1, 2, 3]));
        first_image.save(source.join("copy.jpg")).unwrap();
        first_image.save(source.join("one.jpg")).unwrap();
        image::RgbImage::from_pixel(64, 48, image::Rgb([4, 5, 6])).save(source.join("two.jpg")).unwrap();
        fs::write(source.join("one.jpg.supplemental-metadata.json"), r#"{
            "photoTakenTime":{"timestamp":"1585452449"},
            "description":"Poe at home",
            "geoDataExif":{"latitude":-33.87,"longitude":151.18,"altitude":34.8},
            "favorited":true
        }"#).unwrap();
        let photo_id = file_hash(&source.join("one.jpg")).unwrap();
        fs::create_dir_all(&cache).unwrap();
        fs::write(cache.join(format!("{photo_id}.jpg")), b"bad").unwrap();
        {
            let old = Connection::open(&database_path).unwrap();
            old.execute_batch("CREATE TABLE assets (
                id TEXT PRIMARY KEY, filename TEXT NOT NULL, source_path TEXT NOT NULL,
                preview_path TEXT NOT NULL, taken_at TEXT NOT NULL, collection TEXT NOT NULL,
                favorite INTEGER NOT NULL DEFAULT 0
            )").unwrap();
            old.execute("INSERT INTO assets (id, filename, source_path, preview_path, taken_at, collection)
                VALUES (?1, 'copy.jpg', 'old source', 'old preview', '2025-01-01T00:00:00Z', 'photos')",
                params![photo_id]).unwrap();
        }
        let first = archive_import::import_archive(&source, &cache, &database_path, &archive_import::ImportRunner::default()).unwrap();
        assert_eq!((first.scanned, first.added, first.existing, first.errors.len()), (3, 1, 2, 0));
        let connection = open_database(&database_path).unwrap();
        let asset: (String, i64, Option<String>, Option<f64>) = connection.query_row(
            "SELECT taken_at, favorite, description, latitude FROM assets WHERE id = ?1",
            params![photo_id], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        ).unwrap();
        assert!(asset.0.starts_with("2020-03-29"));
        assert_eq!(asset.1, 1);
        assert_eq!(asset.2.as_deref(), Some("Poe at home"));
        assert_eq!(asset.3, Some(-33.87));
        let stored_paths: (String, String) = connection.query_row(
            "SELECT source_path, preview_path FROM assets WHERE id = ?1", params![photo_id],
            |row| Ok((row.get(0)?, row.get(1)?))
        ).unwrap();
        assert!(Path::new(&stored_paths.0).is_file());
        assert!(Path::new(&stored_paths.1).is_file());
        assert!(Path::new(&stored_paths.1).starts_with(&cache));
        assert_eq!(image::image_dimensions(&stored_paths.1).unwrap(), (64, 48));
        assert_eq!(fs::read_dir(&cache).unwrap().filter_map(Result::ok)
            .filter(|entry| entry.file_name().to_string_lossy().ends_with(".partial")).count(), 0);
        assert_eq!(connection.query_row("SELECT COUNT(*) FROM assets", [], |row| row.get::<_, i64>(0)).unwrap(), 2);
        assert_eq!(fs::read(source.join("one.jpg")).unwrap(), fs::read(source.join("copy.jpg")).unwrap());
        let second = archive_import::import_archive(&source, &cache, &database_path, &archive_import::ImportRunner::default()).unwrap();
        assert_eq!((second.added, second.existing), (0, 3));
        connection.execute("UPDATE assets SET favorite = 0, favorite_modified = 1 WHERE id = ?1", params![photo_id]).unwrap();
        archive_import::import_archive(&source, &cache, &database_path, &archive_import::ImportRunner::default()).unwrap();
        assert_eq!(connection.query_row("SELECT favorite FROM assets WHERE id = ?1", params![photo_id], |row| row.get::<_, i64>(0)).unwrap(), 0);
        drop(connection);
        assert_eq!(root.parent().unwrap().canonicalize().unwrap(), std::env::temp_dir().canonicalize().unwrap());
        fs::remove_dir_all(root).unwrap();
    }
}
