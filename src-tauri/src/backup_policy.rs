use crate::database;
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};
use tauri_plugin_gallery_media::GalleryMediaExt;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupPreferences {
    pub auto_backup: bool,
    pub wifi_only: bool,
    pub background_backup: bool,
}

impl Default for BackupPreferences {
    fn default() -> Self { Self { auto_backup: false, wifi_only: true, background_backup: false } }
}

pub fn prepare(db: &Connection) -> Result<(), String> {
    db.execute_batch("CREATE TABLE IF NOT EXISTS backup_preferences (
        singleton INTEGER PRIMARY KEY CHECK(singleton=1),
        auto_backup INTEGER NOT NULL DEFAULT 0,
        wifi_only INTEGER NOT NULL DEFAULT 1,
        background_backup INTEGER NOT NULL DEFAULT 0
    ); INSERT OR IGNORE INTO backup_preferences(singleton) VALUES (1);")
        .map_err(|error| error.to_string())
}

fn read(db: &Connection) -> Result<BackupPreferences, String> {
    prepare(db)?;
    db.query_row("SELECT auto_backup,wifi_only,background_backup FROM backup_preferences WHERE singleton=1", [],
        |row| Ok(BackupPreferences {
            auto_backup: row.get::<_, i64>(0)? != 0,
            wifi_only: row.get::<_, i64>(1)? != 0,
            background_backup: row.get::<_, i64>(2)? != 0,
        }))
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn get_backup_preferences(app: AppHandle) -> Result<BackupPreferences, String> {
    read(&database(&app)?)
}

#[tauri::command]
pub fn set_backup_preferences(app: AppHandle, preferences: BackupPreferences) -> Result<BackupPreferences, String> {
    let db = database(&app)?;
    prepare(&db)?;
    let previous = read(&db)?;
    db.execute("UPDATE backup_preferences SET auto_backup=?1,wifi_only=?2,background_backup=?3 WHERE singleton=1",
        params![preferences.auto_backup as i64,preferences.wifi_only as i64,preferences.background_backup as i64])
        .map_err(|error| error.to_string())?;
    let data = app.path().app_data_dir().map_err(|error| error.to_string())?;
    let cache = app.path().app_cache_dir().map_err(|error| error.to_string())?;
    if let Err(error) = app.gallery_media().configure_background(
        preferences.auto_backup, preferences.wifi_only, preferences.background_backup,
        data.join("gallery.sqlite").to_string_lossy().into_owned(),
        cache.join("sync-derivatives").to_string_lossy().into_owned()) {
        let _ = db.execute("UPDATE backup_preferences SET auto_backup=?1,wifi_only=?2,background_backup=?3 WHERE singleton=1",
            params![previous.auto_backup as i64,previous.wifi_only as i64,previous.background_backup as i64]);
        return Err(error.to_string());
    }
    Ok(preferences)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_are_opt_in_and_survive_restart() {
        let path = std::env::temp_dir().join(format!("gallery-backup-prefs-{}.sqlite",std::process::id()));
        let _ = std::fs::remove_file(&path);
        let db = Connection::open(&path).unwrap();
        assert_eq!(serde_json::to_value(read(&db).unwrap()).unwrap(), serde_json::json!({
            "autoBackup":false,"wifiOnly":true,"backgroundBackup":false
        }));
        db.execute("UPDATE backup_preferences SET auto_backup=1,background_backup=1 WHERE singleton=1", []).unwrap();
        drop(db);
        let db = Connection::open(&path).unwrap();
        assert!(read(&db).unwrap().auto_backup);
        assert!(read(&db).unwrap().background_backup);
        drop(db);
        std::fs::remove_file(path).unwrap();
    }
}
