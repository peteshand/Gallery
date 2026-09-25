use serde::de::DeserializeOwned;
use tauri::{plugin::PluginApi, AppHandle, Runtime};

use crate::models::*;

pub fn init<R: Runtime, C: DeserializeOwned>(
  app: &AppHandle<R>,
  _api: PluginApi<R, C>,
) -> crate::Result<GalleryMedia<R>> {
  Ok(GalleryMedia(app.clone()))
}

/// Access to the gallery-media APIs.
pub struct GalleryMedia<R: Runtime>(AppHandle<R>);

impl<R: Runtime> GalleryMedia<R> {
  pub fn check_access(&self) -> crate::Result<AccessResponse> { Ok(AccessResponse { access: "unsupported".into() }) }
  pub fn request_access(&self) -> crate::Result<AccessResponse> { self.check_access() }
  pub fn list_media(&self, _offset: usize, _limit: usize) -> crate::Result<MediaPage> {
    Ok(MediaPage { items: Vec::new(), offset: 0, count: 0, next_offset: 0, total: 0 })
  }
  pub fn copy_original(&self, _media_id: i64, _destination: &str) -> crate::Result<CopiedPhoto> {
    Err(crate::Error::Unsupported)
  }
  pub fn hash_original(&self, _media_id: i64) -> crate::Result<PhotoHash> {
    Err(crate::Error::Unsupported)
  }
  pub fn make_thumbnail(&self, _media_id: i64, _destination: &str) -> crate::Result<Thumbnail> {
    Err(crate::Error::Unsupported)
  }
  pub fn make_preview(&self, _media_id: i64, _destination: &str) -> crate::Result<Thumbnail> {
    Err(crate::Error::Unsupported)
  }
  pub fn configure_background(&self, _auto_backup: bool, _wifi_only: bool, _background_backup: bool,
    _database_path: String, _cache_path: String) -> crate::Result<()> { Ok(()) }
  pub fn run_auto_backup(&self) -> crate::Result<()> { Ok(()) }
}
