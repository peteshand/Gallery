use tauri::{
  plugin::{Builder, TauriPlugin},
  Manager, Runtime,
};

pub use models::*;

#[cfg(desktop)]
mod desktop;
#[cfg(mobile)]
mod mobile;

mod error;
mod models;

pub use error::{Error, Result};

#[cfg(desktop)]
use desktop::GalleryMedia;
#[cfg(mobile)]
use mobile::GalleryMedia;

/// Extensions to [`tauri::App`], [`tauri::AppHandle`] and [`tauri::Window`] to access the gallery-media APIs.
pub trait GalleryMediaExt<R: Runtime> {
  fn gallery_media(&self) -> &GalleryMedia<R>;
}

impl<R: Runtime, T: Manager<R>> crate::GalleryMediaExt<R> for T {
  fn gallery_media(&self) -> &GalleryMedia<R> {
    self.state::<GalleryMedia<R>>().inner()
  }
}

/// Initializes the plugin.
pub fn init<R: Runtime>() -> TauriPlugin<R> {
  Builder::new("gallery-media")
    .setup(|app, api| {
      #[cfg(mobile)]
      let gallery_media = mobile::init(app, api)?;
      #[cfg(desktop)]
      let gallery_media = desktop::init(app, api)?;
      app.manage(gallery_media);
      Ok(())
    })
    .build()
}
