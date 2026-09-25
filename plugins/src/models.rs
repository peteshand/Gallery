use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct AccessResponse { pub access: String }

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaEntry {
    pub media_id: i64,
    pub filename: String,
    pub taken_at_millis: i64,
    pub mime_type: String,
    pub bytes: i64,
    pub folder: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaPage {
    pub items: Vec<MediaEntry>,
    pub offset: usize,
    pub count: usize,
    pub next_offset: usize,
    pub total: usize,
}

#[derive(Debug, Serialize)]
pub struct PageRequest { pub offset: usize, pub limit: usize }

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaRequest<'a> { pub media_id: i64, pub destination: &'a str }

#[derive(Debug, Deserialize)]
pub struct CopiedPhoto { pub path: String, pub sha256: String }

#[derive(Debug, Deserialize)]
pub struct PhotoHash { pub sha256: String }

#[derive(Debug, Deserialize)]
pub struct Thumbnail { pub path: String }

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackgroundRequest {
    pub auto_backup: bool,
    pub wifi_only: bool,
    pub background_backup: bool,
    pub database_path: String,
    pub cache_path: String,
}

#[derive(Debug, Deserialize)]
pub struct BackgroundResponse { pub configured: bool }
