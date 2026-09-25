//! JNI bridge for WorkManager when the Tauri activity is not running.
use crate::{file_hash, open_database, sync};
use chrono::{DateTime, Utc};
use jni::{objects::{JObject, JString}, sys::{jboolean, jlong}, JNIEnv};
use rusqlite::{params, OptionalExtension};
use std::path::Path;

fn string(env: &mut JNIEnv, value: JString) -> Result<String, String> {
    env.get_string(&value).map(|value| value.into()).map_err(|error| error.to_string())
}

fn yes(result: Result<bool, String>) -> jboolean {
    match result { Ok(true) => 1, Ok(false) => 0, Err(error) => { log::warn!("Background backup: {error}"); 0 } }
}

fn synced(db_path: &str, hash: &str) -> Result<bool, String> {
    let db = open_database(Path::new(db_path))?;
    let local: bool = db.query_row("SELECT state='synced' FROM sync_items WHERE asset_id=?1", params![hash], |row| row.get(0))
        .optional().map_err(|error| error.to_string())?.unwrap_or(false);
    let remote: bool = db.query_row("SELECT 1 FROM remote_assets WHERE asset_id=?1", params![hash], |_| Ok(true))
        .optional().map_err(|error| error.to_string())?.unwrap_or(false);
    Ok(local || remote)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_pshand_gallery_media_GalleryBackupWorker_isMediaSynced(
    mut env: JNIEnv, _this: JObject, database: JString, media_id: jlong,
) -> jboolean {
    yes((|| {
        let database = string(&mut env, database)?;
        let db = open_database(Path::new(&database))?;
        let hash: Option<String> = db.query_row("SELECT asset_id FROM phone_media WHERE media_id=?1", params![media_id], |row| row.get(0))
            .optional().map_err(|error| error.to_string())?.flatten();
        match hash { Some(hash) => synced(&database, &hash), None => Ok(false) }
    })())
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_pshand_gallery_media_GalleryBackupWorker_isHashSynced(
    mut env: JNIEnv, _this: JObject, database: JString, hash: JString,
) -> jboolean {
    yes((|| synced(&string(&mut env, database)?, &string(&mut env, hash)?))())
}

fn record(db_path: &str, media_id: i64, hash: &str, filename: &str, taken: i64, mime: &str, bytes: i64, folder: &str) -> Result<(), String> {
    let db = open_database(Path::new(db_path))?;
    let taken = DateTime::<Utc>::from_timestamp_millis(taken).unwrap_or_else(Utc::now).to_rfc3339();
    db.execute("INSERT INTO phone_media (media_id,filename,taken_at,mime_type,bytes,asset_id,device_folder) VALUES (?1,?2,?3,?4,?5,?6,?7)
        ON CONFLICT(media_id) DO UPDATE SET filename=excluded.filename,taken_at=excluded.taken_at,mime_type=excluded.mime_type,
        bytes=excluded.bytes,asset_id=excluded.asset_id,device_folder=excluded.device_folder",
        params![media_id,filename,taken,mime,bytes,hash,folder]).map_err(|error| error.to_string())?;
    Ok(())
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_pshand_gallery_media_GalleryBackupWorker_recordExistingPhoto(
    mut env: JNIEnv, _this: JObject, database: JString, media_id: jlong, hash: JString,
    filename: JString, taken: jlong, mime: JString, bytes: jlong, folder: JString,
) -> jboolean {
    yes((|| {
        let database = string(&mut env, database)?;
        let hash = string(&mut env, hash)?;
        if !synced(&database, &hash)? { return Ok(false); }
        record(&database, media_id, &hash, &string(&mut env, filename)?, taken, &string(&mut env, mime)?, bytes,
            &string(&mut env, folder)?)?;
        Ok(true)
    })())
}

fn upload(db_path: &str, cache: &str, source: &str, filename: &str, taken: i64, media_id: i64, mime: &str, folder: &str) -> Result<bool, String> {
    let source = Path::new(source);
    let hash = file_hash(source)?;
    let bytes = source.metadata().map_err(|error| error.to_string())?.len() as i64;
    record(db_path, media_id, &hash, filename, taken, mime, bytes, folder)?;
    if synced(db_path, &hash)? { return Ok(true); }
    let db = open_database(Path::new(db_path))?;
    let taken_at = DateTime::<Utc>::from_timestamp_millis(taken).unwrap_or_else(Utc::now).to_rfc3339();
    db.execute("INSERT OR IGNORE INTO assets (id,filename,source_path,preview_path,taken_at,collection,favorite)
        VALUES (?1,?2,?3,'',?4,?5,0)", params![hash,filename,source.to_string_lossy(),taken_at,
            crate::phone_media::device_collection(folder)])
        .map_err(|error| error.to_string())?;
    let current: String = db.query_row("SELECT source_path FROM assets WHERE id=?1", params![hash], |row| row.get(0))
        .map_err(|error| error.to_string())?;
    if current.is_empty() || !Path::new(&current).is_file() {
        db.execute("UPDATE assets SET source_path=?2 WHERE id=?1", params![hash,source.to_string_lossy()])
            .map_err(|error| error.to_string())?;
    }
    drop(db);
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().map_err(|error| error.to_string())?;
    let run = runtime.block_on(sync::run_selected(Path::new(db_path), Path::new(cache), Some(vec![hash.clone()]))) ;
    let db = open_database(Path::new(db_path))?;
    db.execute("UPDATE assets SET source_path=?3 WHERE id=?1 AND source_path=?2",
        params![hash,source.to_string_lossy(),format!("phone:{media_id}")]).map_err(|error| error.to_string())?;
    run?;
    synced(db_path, &hash)
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_pshand_gallery_media_GalleryBackupWorker_uploadStagedPhoto(
    mut env: JNIEnv, _this: JObject, context: JObject, database: JString, cache: JString,
    source: JString, filename: JString, taken: jlong, media_id: jlong, mime: JString, folder: JString,
) -> jboolean {
    // WorkManager may start this process without creating MainActivity first.
    // The temporary JNI handle is used only for this call, before `env` is reused.
    android_native_keyring_store::Java_io_crates_keyring_Keyring_00024Companion_initializeNdkContext(
        unsafe { env.unsafe_clone() }, JObject::null(), context);
    yes((|| upload(&string(&mut env, database)?, &string(&mut env, cache)?,
        &string(&mut env, source)?, &string(&mut env, filename)?, taken, media_id,
        &string(&mut env, mime)?, &string(&mut env, folder)?))())
}
