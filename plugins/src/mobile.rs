use serde::de::DeserializeOwned;
use tauri::{
  plugin::{PluginApi, PluginHandle},
  AppHandle, Runtime,
};

use crate::models::*;

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_gallery_media);

// initializes the Kotlin or Swift plugin classes
pub fn init<R: Runtime, C: DeserializeOwned>(
  _app: &AppHandle<R>,
  api: PluginApi<R, C>,
) -> crate::Result<GalleryMedia<R>> {
  #[cfg(target_os = "android")]
  let handle = api.register_android_plugin("com.pshand.gallery.media", "GalleryMediaPlugin")?;
  #[cfg(target_os = "ios")]
  let handle = api.register_ios_plugin(init_plugin_gallery_media)?;
  Ok(GalleryMedia(handle))
}

/// Access to the gallery-media APIs.
pub struct GalleryMedia<R: Runtime>(PluginHandle<R>);

impl<R: Runtime> GalleryMedia<R> {
  pub fn check_access(&self) -> crate::Result<AccessResponse> {
    self.0.run_mobile_plugin("checkAccess", ()).map_err(Into::into)
  }
  pub fn request_access(&self) -> crate::Result<AccessResponse> {
    self.0.run_mobile_plugin("requestAccess", ()).map_err(Into::into)
  }
  pub fn list_media(&self, offset: usize, limit: usize) -> crate::Result<MediaPage> {
    self.0.run_mobile_plugin("listMedia", PageRequest { offset, limit }).map_err(Into::into)
  }
  pub fn copy_original(&self, media_id: i64, destination: &str) -> crate::Result<CopiedPhoto> {
    self.0.run_mobile_plugin("copyOriginal", MediaRequest { media_id, destination }).map_err(Into::into)
  }
  pub fn hash_original(&self, media_id: i64) -> crate::Result<PhotoHash> {
    self.0.run_mobile_plugin("hashOriginal", MediaRequest { media_id, destination: "" }).map_err(Into::into)
  }
  pub fn make_thumbnail(&self, media_id: i64, destination: &str) -> crate::Result<Thumbnail> {
    self.0.run_mobile_plugin("makeThumbnail", MediaRequest { media_id, destination }).map_err(Into::into)
  }
  pub fn make_preview(&self, media_id: i64, destination: &str) -> crate::Result<Thumbnail> {
    self.0.run_mobile_plugin("makePreview", MediaRequest { media_id, destination }).map_err(Into::into)
  }
  pub fn configure_background(&self, auto_backup: bool, wifi_only: bool, background_backup: bool,
    database_path: String, cache_path: String) -> crate::Result<()> {
    let result: BackgroundResponse = self.0.run_mobile_plugin("configureBackground",
      BackgroundRequest { auto_backup, wifi_only, background_backup, database_path, cache_path }).map_err(crate::Error::from)?;
    if result.configured { Ok(()) } else { Err(crate::Error::Unsupported) }
  }
  pub fn run_auto_backup(&self) -> crate::Result<()> {
    let result: BackgroundResponse = self.0.run_mobile_plugin("runAutoBackup", ()).map_err(crate::Error::from)?;
    if result.configured { Ok(()) } else { Err(crate::Error::Unsupported) }
  }
}
