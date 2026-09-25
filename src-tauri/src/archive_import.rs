use crate::{file_hash, open_database, sidecar_metadata, sync, ImportResult};
use chrono::{DateTime, Utc};
use rusqlite::{params, OptionalExtension};
use serde::Serialize;
use sha2::Digest;
use std::{fs, path::Path, sync::Mutex, time::UNIX_EPOCH};

#[derive(Default)]
pub struct ImportRunner(Mutex<ImportState>);

#[derive(Default)]
struct ImportState {
    running: bool,
    cancelling: bool,
    processed: usize,
    added: usize,
    existing: usize,
    errors: usize,
    current: String,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportProgress {
    running: bool,
    cancelling: bool,
    processed: usize,
    added: usize,
    existing: usize,
    errors: usize,
    current: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportError {
    path: String,
    error: String,
    attempts: i64,
    last_attempt_at: String,
}

pub fn list_errors(database_path: &Path) -> Result<Vec<ImportError>, String> {
    let db = open_database(database_path)?;
    let mut statement = db.prepare("SELECT path,error,attempts,last_attempt_at FROM import_errors
        ORDER BY last_attempt_at DESC,path LIMIT 100")
        .map_err(|error| error.to_string())?;
    let errors = statement.query_map([], |row| Ok(ImportError {
        path: row.get(0)?, error: row.get(1)?, attempts: row.get(2)?, last_attempt_at: row.get(3)?,
    })).map_err(|error| error.to_string())?
        .collect::<rusqlite::Result<Vec<_>>>().map_err(|error| error.to_string())?;
    Ok(errors)
}

impl ImportRunner {
    pub fn begin(&self) -> bool {
        let mut state = self.0.lock().unwrap();
        if state.running { return false; }
        *state = ImportState { running: true, ..ImportState::default() };
        true
    }
    pub fn finish(&self) { self.0.lock().unwrap().running = false; }
    pub fn cancel(&self) { self.0.lock().unwrap().cancelling = true; }
    pub fn cancelled(&self) -> bool { self.0.lock().unwrap().cancelling }
    fn note(&self, current: &Path, added: usize, existing: usize, errors: usize) {
        let mut state = self.0.lock().unwrap();
        state.processed += 1;
        state.added += added;
        state.existing += existing;
        state.errors += errors;
        state.current = current.file_name().unwrap_or_default().to_string_lossy().into_owned();
    }
    pub fn status(&self) -> ImportProgress {
        let state = self.0.lock().unwrap();
        ImportProgress { running:state.running, cancelling:state.cancelling, processed:state.processed,
            added:state.added, existing:state.existing, errors:state.errors, current:state.current.clone() }
    }
}

pub(crate) fn prepare_sources(db: &rusqlite::Connection) -> Result<(), String> {
    db.execute_batch("CREATE TABLE IF NOT EXISTS import_sources (
        path TEXT PRIMARY KEY, bytes INTEGER NOT NULL, modified_ns INTEGER NOT NULL, asset_id TEXT NOT NULL,
        source_id TEXT NOT NULL DEFAULT '', source_label TEXT NOT NULL DEFAULT '', relative_path TEXT NOT NULL DEFAULT '',
        takeout_json TEXT, metadata_version INTEGER NOT NULL DEFAULT 0);")
        .map_err(|error| error.to_string())?;
    for (name, definition) in [("source_id", "TEXT NOT NULL DEFAULT ''"),
        ("source_label", "TEXT NOT NULL DEFAULT ''"),
        ("relative_path", "TEXT NOT NULL DEFAULT ''"), ("takeout_json", "TEXT"),
        ("metadata_version", "INTEGER NOT NULL DEFAULT 0")] {
        let columns = db.prepare("PRAGMA table_info(import_sources)").map_err(|error| error.to_string())?
            .query_map([], |row| row.get::<_, String>(1)).map_err(|error| error.to_string())?
            .collect::<rusqlite::Result<Vec<_>>>().map_err(|error| error.to_string())?;
        if !columns.contains(&name.to_string()) {
            db.execute(&format!("ALTER TABLE import_sources ADD COLUMN {name} {definition}"), [])
                .map_err(|error| error.to_string())?;
        }
    }
    Ok(())
}

pub fn import_archive(source: &Path, cache: &Path, database_path: &Path, runner: &ImportRunner) -> Result<ImportResult, String> {
    if !source.is_dir() { return Err(format!("Import source is missing: {}", source.display())); }
    fs::create_dir_all(cache).map_err(|error| error.to_string())?;
    let db = open_database(database_path)?;
    let mut result = ImportResult { scanned:0, added:0, existing:0, errors:Vec::new() };
    let mut directories = vec![source.to_path_buf()];
    while let Some(directory) = directories.pop() {
        if runner.cancelled() { break; }
        let sidecars = sidecar_metadata(&directory);
        let entries = match fs::read_dir(&directory) {
            Ok(entries) => entries,
            Err(error) => { result.errors.push(format!("{}: {error}", directory.display())); continue; }
        };
        for entry in entries {
            if runner.cancelled() { break; }
            let entry = match entry { Ok(entry) => entry, Err(error) => { result.errors.push(error.to_string()); continue; } };
            let path = entry.path();
            let file_type = match entry.file_type() { Ok(value) => value, Err(error) => { result.errors.push(error.to_string()); continue; } };
            if file_type.is_symlink() { continue; }
            if file_type.is_dir() { directories.push(path); continue; }
            if !file_type.is_file() { continue; }
            let extension = path.extension().and_then(|value| value.to_str()).unwrap_or("").to_ascii_lowercase();
            if !matches!(extension.as_str(), "jpg" | "jpeg" | "png" | "gif" | "webp") { continue; }
            result.scanned += 1;
            let outcome = import_one(&db, source, cache, &path, &sidecars);
            match outcome {
                Ok(true) => {
                    db.execute("DELETE FROM import_errors WHERE path=?1", params![path.to_string_lossy()])
                        .map_err(|error| error.to_string())?;
                    result.added += 1; runner.note(&path, 1, 0, 0);
                }
                Ok(false) => {
                    db.execute("DELETE FROM import_errors WHERE path=?1", params![path.to_string_lossy()])
                        .map_err(|error| error.to_string())?;
                    result.existing += 1; runner.note(&path, 0, 1, 0);
                }
                Err(error) => {
                    db.execute("INSERT INTO import_errors(path,error,attempts,last_attempt_at) VALUES (?1,?2,1,?3)
                        ON CONFLICT(path) DO UPDATE SET error=excluded.error,attempts=attempts+1,
                        last_attempt_at=excluded.last_attempt_at",
                        params![path.to_string_lossy(), error, Utc::now().to_rfc3339()])
                        .map_err(|db_error| db_error.to_string())?;
                    result.errors.push(format!("{}: {error}", path.display())); runner.note(&path, 0, 0, 1);
                }
            }
        }
    }
    Ok(result)
}

fn import_one(db: &rusqlite::Connection, root: &Path, cache: &Path, path: &Path,
    sidecars: &std::collections::HashMap<String, crate::TakeoutMetadata>) -> Result<bool, String> {
    let metadata = fs::metadata(path).map_err(|error| error.to_string())?;
    let modified_ns = metadata.modified().map_err(|error| error.to_string())?
        .duration_since(UNIX_EPOCH).map_err(|error| error.to_string())?.as_nanos() as i64;
    let source_path = path.to_string_lossy().into_owned();
    let source_id = format!("{:x}", sha2::Sha256::digest(root.to_string_lossy().as_bytes()));
    let filename = path.file_name().unwrap_or_default().to_string_lossy().into_owned();
    let sidecar = sidecars.get(&filename.to_lowercase());
    let takeout_json = sidecar.map(|value| value.preserved.to_string());
    let known: Option<(i64, i64, String, i64, Option<String>, String)> = db.query_row("SELECT bytes,modified_ns,asset_id,metadata_version,takeout_json,source_id FROM import_sources WHERE path=?1",
        params![source_path], |row| Ok((row.get(0)?,row.get(1)?,row.get(2)?,row.get(3)?,row.get(4)?,row.get(5)?)))
        .optional().map_err(|error| error.to_string())?;
    if let Some((bytes, modified, id, metadata_version, old_takeout_json, old_source_id)) = known {
        let asset_exists = db.query_row("SELECT 1 FROM assets WHERE id=?1", params![id], |_| Ok(true))
            .optional().map_err(|error| error.to_string())?.unwrap_or(false);
        if metadata_version >= 1 && old_source_id == source_id && old_takeout_json == takeout_json && bytes == metadata.len() as i64 && modified == modified_ns &&
            asset_exists &&
            cache.join(&id).join("preview.jpg").is_file() && cache.join(&id).join("thumbnail-v2.jpg").is_file() {
            return Ok(false);
        }
    }
    let id = file_hash(path)?;
    let (preview, _, _, _) = sync::derivatives(path, &cache.join(&id))?;
    let sidecar_date = sidecar.and_then(|value| value.taken_at.as_deref());
    let taken_at = sidecar_date.map(str::to_string).unwrap_or_else(|| DateTime::<Utc>::from(metadata.modified().unwrap()).to_rfc3339());
    let source_label = root.file_name().unwrap_or_default().to_string_lossy().into_owned();
    let relative_path = path.strip_prefix(root).map_err(|error| error.to_string())?
        .to_string_lossy().replace(std::path::MAIN_SEPARATOR, "/");
    let relative = path.parent().unwrap_or(root).strip_prefix(root).unwrap_or(Path::new(""));
    let collection = if relative.as_os_str().is_empty() { source_label.clone() }
        else { format!("{}/{}", source_label, relative.to_string_lossy().replace(std::path::MAIN_SEPARATOR, "/")) };
    let added = db.execute("INSERT OR IGNORE INTO assets
        (id,filename,source_path,preview_path,taken_at,collection,favorite,taken_at_source,description,latitude,longitude,altitude,takeout_json)
        VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13)", params![
        id,filename,source_path,preview.to_string_lossy(),taken_at,collection,
        sidecar.map(|value| value.favorite as i64).unwrap_or(0),sidecar_date.is_some() as i64,
        sidecar.and_then(|value| value.description.as_deref()),sidecar.and_then(|value| value.latitude),
        sidecar.and_then(|value| value.longitude),sidecar.and_then(|value| value.altitude),takeout_json])
        .map_err(|error| error.to_string())?;
    if added == 0 {
        db.execute("UPDATE assets SET source_path=?2,preview_path=?3,
            taken_at=CASE WHEN taken_at_source=0 AND ?4 IS NOT NULL THEN ?4 ELSE taken_at END,
            taken_at_source=CASE WHEN ?4 IS NOT NULL THEN 1 ELSE taken_at_source END,
            favorite=CASE WHEN favorite_modified=0 AND ?5=1 THEN 1 ELSE favorite END,
            description=COALESCE(description,?6),latitude=COALESCE(latitude,?7),
            longitude=COALESCE(longitude,?8),altitude=COALESCE(altitude,?9),
            takeout_json=COALESCE(?10,takeout_json) WHERE id=?1", params![
            id,source_path,preview.to_string_lossy(),sidecar_date,sidecar.map(|value| value.favorite as i64).unwrap_or(0),
            sidecar.and_then(|value| value.description.as_deref()),sidecar.and_then(|value| value.latitude),
            sidecar.and_then(|value| value.longitude),sidecar.and_then(|value| value.altitude),takeout_json])
            .map_err(|error| error.to_string())?;
    }
    db.execute("UPDATE sync_items SET state='not_synced',manifest_done=0,synced_at=NULL
        WHERE asset_id=?1", params![id]).map_err(|error| error.to_string())?;
    db.execute("INSERT INTO import_sources(path,bytes,modified_ns,asset_id,source_id,source_label,relative_path,takeout_json,metadata_version)
        VALUES (?1,?2,?3,?4,?5,?6,?7,?8,1)
        ON CONFLICT(path) DO UPDATE SET bytes=excluded.bytes,modified_ns=excluded.modified_ns,
        asset_id=excluded.asset_id,source_id=excluded.source_id,source_label=excluded.source_label,relative_path=excluded.relative_path,
        takeout_json=excluded.takeout_json,metadata_version=1",
        params![source_path,metadata.len() as i64,modified_ns,id,source_id,source_label,relative_path,takeout_json]).map_err(|error| error.to_string())?;
    Ok(added > 0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgb, RgbImage};

    #[test]
    fn file_errors_survive_restart_and_clear_after_repair() {
        let root = std::env::temp_dir().join(format!("gallery-import-errors-test-{}", std::process::id()));
        let photos = root.join("photos");
        let cache = root.join("cache");
        let db_path = root.join("gallery.sqlite");
        fs::create_dir_all(&photos).unwrap();
        let photo = photos.join("broken.jpg");
        fs::write(&photo, b"not a JPEG").unwrap();

        let first = import_archive(&photos, &cache, &db_path, &ImportRunner::default()).unwrap();
        assert_eq!((first.scanned, first.added, first.errors.len()), (1, 0, 1));
        let second = import_archive(&photos, &cache, &db_path, &ImportRunner::default()).unwrap();
        assert_eq!(second.errors.len(), 1);
        let db = open_database(&db_path).unwrap();
        let attempts: i64 = db.query_row("SELECT attempts FROM import_errors WHERE path=?1",
            params![photo.to_string_lossy()], |row| row.get(0)).unwrap();
        assert_eq!(attempts, 2);
        let errors = list_errors(&db_path).unwrap();
        assert_eq!(errors.len(), 1);
        assert_eq!((errors[0].path.as_str(), errors[0].attempts), (photo.to_str().unwrap(), 2));

        RgbImage::from_pixel(64, 48, Rgb([8, 9, 10])).save(&photo).unwrap();
        let repaired = import_archive(&photos, &cache, &db_path, &ImportRunner::default()).unwrap();
        assert_eq!((repaired.added, repaired.errors.len()), (1, 0));
        let pending: i64 = db.query_row("SELECT COUNT(*) FROM import_errors", [], |row| row.get(0)).unwrap();
        assert_eq!(pending, 0);
        assert!(list_errors(&db_path).unwrap().is_empty());
        drop(db);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn recursive_import_is_resumable_and_does_not_copy_originals() {
        let root = std::env::temp_dir().join(format!("gallery-archive-test-{}",std::process::id()));
        let photos = root.join("photos");
        let cache = root.join("cache");
        fs::create_dir_all(photos.join("2003")).unwrap();
        fs::create_dir_all(photos.join("2004")).unwrap();
        RgbImage::from_pixel(800,600,Rgb([2,3,4])).save(photos.join("2003/one.jpg")).unwrap();
        RgbImage::from_pixel(800,600,Rgb([5,6,7])).save(photos.join("2004/two.jpg")).unwrap();
        let runner = ImportRunner::default();
        let db = root.join("catalogue.sqlite");
        assert!(runner.begin());
        let first = import_archive(&photos,&cache,&db,&runner).unwrap();
        assert_eq!((first.scanned,first.added,first.errors.len()),(2,2,0));
        runner.finish();
        assert_eq!(runner.status().processed,2);
        let second = import_archive(&photos,&cache,&db,&ImportRunner::default()).unwrap();
        assert_eq!((second.added,second.existing),(0,2));
        let connection = open_database(&db).unwrap();
        let rows: Vec<(String,String)> = connection.prepare("SELECT source_path,preview_path FROM assets").unwrap()
            .query_map([],|row| Ok((row.get(0)?,row.get(1)?))).unwrap().map(Result::unwrap).collect();
        for (source,preview) in rows {
            assert!(Path::new(&source).starts_with(&photos));
            assert!(Path::new(&preview).starts_with(&cache));
            assert_eq!(Path::new(&preview).file_name().unwrap(), "preview.jpg");
            assert!(image::image_dimensions(preview).unwrap().0 <= 1920);
        }
        drop(connection);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn cancelled_archive_can_resume_without_duplicate_rows() {
        let root = std::env::temp_dir().join(format!("gallery-cancel-test-{}",std::process::id()));
        let photos = root.join("photos");
        let cache = root.join("cache");
        fs::create_dir_all(photos.join("year")).unwrap();
        RgbImage::from_pixel(64,48,Rgb([8,9,10])).save(photos.join("year/photo.jpg")).unwrap();
        let db = root.join("catalogue.sqlite");
        let runner = ImportRunner::default();
        assert!(runner.begin());
        runner.cancel();
        let cancelled = import_archive(&photos,&cache,&db,&runner).unwrap();
        assert_eq!((cancelled.scanned,cancelled.added),(0,0));
        runner.finish();
        assert!(runner.begin());
        let resumed = import_archive(&photos,&cache,&db,&runner).unwrap();
        assert_eq!((resumed.scanned,resumed.added,resumed.errors.len()),(1,1,0));
        runner.finish();
        let repeat = import_archive(&photos,&cache,&db,&ImportRunner::default()).unwrap();
        assert_eq!((repeat.added,repeat.existing),(0,1));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn preserves_selected_takeout_fields_and_nested_source_path() {
        let root = std::env::temp_dir().join(format!("gallery-takeout-fields-{}",std::process::id()));
        let photos = root.join("Best of Poe 2").join("2017");
        let cache = root.join("cache");
        let db_path = root.join("gallery.sqlite");
        fs::create_dir_all(&photos).unwrap();
        RgbImage::from_pixel(32,24,Rgb([1,2,3])).save(photos.join("photo.jpg")).unwrap();
        fs::write(photos.join("photo.jpg.supplemental-metadata.json"),
            serde_json::json!({
                "creationTime":{"timestamp":"1500000000","formatted":"Jul 14, 2017"},
                "photoTakenTime":{"timestamp":"1500000001","formatted":"Jul 14, 2017"},
                "people":[{"name":"Poe Shand"}],
                "googlePhotosOrigin":{"composition":{"type":"AUTO"}},
                "geoData":{"latitude":-33.8,"longitude":151.1,"altitude":34.8},
                "url":"https://photos.google.com/private"
            }).to_string()).unwrap();
        import_archive(&root.join("Best of Poe 2"),&cache,&db_path,&ImportRunner::default()).unwrap();
        let db = open_database(&db_path).unwrap();
        let (collection, takeout): (String,String) = db.query_row(
            "SELECT collection,takeout_json FROM assets", [], |row| Ok((row.get(0)?,row.get(1)?))).unwrap();
        assert_eq!(collection,"Best of Poe 2/2017");
        let value: serde_json::Value = serde_json::from_str(&takeout).unwrap();
        for name in ["creationTime","photoTakenTime","people","googlePhotosOrigin","geoData"] {
            assert!(!value[name].is_null(),"{name} was lost");
        }
        assert!(value.get("url").is_none());
        let (label,relative): (String,String) = db.query_row("SELECT source_label,relative_path FROM import_sources",
            [], |row| Ok((row.get(0)?,row.get(1)?))).unwrap();
        assert_eq!(label,"Best of Poe 2");
        assert_eq!(relative,"2017/photo.jpg");
        drop(db);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn imports_real_archive_folder_when_requested() {
        let Ok(source) = std::env::var("GALLERY_ARCHIVE_SOURCE") else { return };
        let source = std::path::PathBuf::from(source);
        let root = std::env::temp_dir().join(format!("gallery-real-archive-test-{}",std::process::id()));
        let cache = root.join("cache");
        fs::create_dir_all(&root).unwrap();
        let db = root.join("catalogue.sqlite");
        let started = std::time::Instant::now();
        let first = import_archive(&source,&cache,&db,&ImportRunner::default()).unwrap();
        println!("Imported {} photos in {:.1}s",first.added,started.elapsed().as_secs_f64());
        assert!(first.scanned > 0);
        assert_eq!((first.scanned,first.added,first.errors.len()),(first.scanned,first.scanned,0));
        let second = import_archive(&source,&cache,&db,&ImportRunner::default()).unwrap();
        assert_eq!((second.added,second.existing),(0,first.scanned));
        let connection = open_database(&db).unwrap();
        let sidecar_dates: i64 = connection.query_row("SELECT SUM(taken_at_source) FROM assets",[],|row| row.get(0)).unwrap();
        assert!(sidecar_dates > 0);
        drop(connection);
        fs::remove_dir_all(root).unwrap();
    }
}
