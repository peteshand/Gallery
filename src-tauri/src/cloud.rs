use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};
use aws_sdk_s3::config::{BehaviorVersion, Credentials, Region};
use aws_sdk_s3::config::timeout::TimeoutConfig;
use aws_sdk_s3::error::ProvideErrorMetadata;
use aws_smithy_async::rt::sleep::TokioSleep;
#[cfg(target_os = "android")]
use aws_smithy_http_client::{tls::{self, rustls_provider::CryptoMode}, Builder as HttpClientBuilder};
use std::time::Duration;

const CREDENTIAL_TARGET: &str = "com.pshand.gallery/s3";

#[cfg(target_os = "android")]
fn android_http_client() -> Result<aws_sdk_s3::config::SharedHttpClient, String> {
    let trust_store = tls::TrustStore::empty()
        .with_pem_certificate(include_bytes!("../certs/cacert.pem").as_slice());
    let context = tls::TlsContext::builder()
        .with_trust_store(trust_store)
        .build()
        .map_err(|_| "Could not prepare Android HTTPS certificates".to_string())?;
    Ok(HttpClientBuilder::new()
        .tls_provider(tls::Provider::Rustls(CryptoMode::AwsLc))
        .tls_context(context)
        .build_https())
}

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct S3ConnectionInput {
    bucket: String,
    region: String,
    endpoint: String,
    prefix: String,
    access_key_id: String,
    secret_access_key: String,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct S3ConnectionStatus {
    configured: bool,
    credentials_available: bool,
    bucket: String,
    region: String,
    endpoint: String,
    prefix: String,
    masked_key_id: String,
    last_verified_at: Option<i64>,
}

#[derive(Clone)]
pub(crate) struct S3Config {
    pub(crate) bucket: String,
    pub(crate) region: String,
    pub(crate) endpoint: String,
    pub(crate) prefix: String,
}

fn config_database(app: &AppHandle) -> Result<Connection, String> {
    let directory = app.path().app_data_dir().map_err(|_| "Could not locate app data".to_string())?;
    std::fs::create_dir_all(&directory).map_err(|_| "Could not create app data".to_string())?;
    let connection = Connection::open(directory.join("gallery.sqlite"))
        .map_err(|_| "Could not open app data".to_string())?;
    connection.execute_batch("CREATE TABLE IF NOT EXISTS s3_connection (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        bucket TEXT NOT NULL,
        region TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        prefix TEXT NOT NULL,
        last_verified_at INTEGER
    )").map_err(|_| "Could not prepare S3 settings".to_string())?;
    let has_verified_column: bool = connection.prepare("PRAGMA table_info(s3_connection)")
        .map_err(|_| "Could not inspect S3 settings".to_string())?
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|_| "Could not inspect S3 settings".to_string())?
        .filter_map(Result::ok)
        .any(|name| name == "last_verified_at");
    if !has_verified_column {
        connection.execute("ALTER TABLE s3_connection ADD COLUMN last_verified_at INTEGER", [])
            .map_err(|_| "Could not update S3 settings".to_string())?;
    }
    Ok(connection)
}

fn stored_config(connection: &Connection) -> Result<Option<S3Config>, String> {
    connection.query_row(
        "SELECT bucket, region, endpoint, prefix FROM s3_connection WHERE id = 1",
        [],
        |row| Ok(S3Config { bucket: row.get(0)?, region: row.get(1)?, endpoint: row.get(2)?, prefix: row.get(3)? }),
    ).optional().map_err(|_| "Could not read S3 settings".to_string())
}

pub(crate) fn upload_connection(connection: &Connection) -> Result<(S3Config, aws_sdk_s3::Client), String> {
    let config = stored_config(connection)?.ok_or_else(|| "Save S3 connection settings first".to_string())?;
    let (key, secret) = credential_store::read(CREDENTIAL_TARGET)?
        .ok_or_else(|| "Saved S3 credentials are missing".to_string())?;
    let mut builder = aws_sdk_s3::Config::builder()
        .behavior_version(BehaviorVersion::latest())
        .region(Region::new(config.region.clone()))
        .sleep_impl(TokioSleep::new())
        .timeout_config(TimeoutConfig::builder()
            .operation_timeout(Duration::from_secs(120))
            .operation_attempt_timeout(Duration::from_secs(60))
            .build())
        .credentials_provider(Credentials::new(key, secret, None, None, "Gallery protected store"));
    #[cfg(target_os = "android")]
    { builder = builder.http_client(android_http_client()?); }
    if !config.endpoint.is_empty() {
        builder = builder.endpoint_url(config.endpoint.clone()).force_path_style(true);
    }
    Ok((config, aws_sdk_s3::Client::from_conf(builder.build())))
}

fn status(connection: &Connection) -> Result<S3ConnectionStatus, String> {
    let config = stored_config(connection)?;
    let credential = credential_store::read(CREDENTIAL_TARGET)?;
    let available = credential.is_some();
    let (bucket, region, endpoint, prefix) = match &config {
        Some(value) => (value.bucket.clone(), value.region.clone(), value.endpoint.clone(), value.prefix.clone()),
        None => (String::new(), String::new(), String::new(), String::new()),
    };
    let masked_key_id = credential.map(|value| mask_key(&value.0)).unwrap_or_default();
    let last_verified_at = connection.query_row(
        "SELECT last_verified_at FROM s3_connection WHERE id = 1", [], |row| row.get(0),
    ).optional().map_err(|_| "Could not read S3 verification status".to_string())?.flatten();
    Ok(S3ConnectionStatus {
        configured: config.is_some() && available,
        credentials_available: available,
        bucket, region, endpoint, prefix, masked_key_id, last_verified_at,
    })
}

fn mask_key(key: &str) -> String {
    let tail: String = key.chars().rev().take(4).collect::<Vec<_>>().into_iter().rev().collect();
    format!("••••{tail}")
}

fn validated(input: &S3ConnectionInput) -> Result<S3Config, String> {
    let bucket = input.bucket.trim();
    let region = input.region.trim();
    let endpoint = input.endpoint.trim().trim_end_matches('/');
    let prefix = input.prefix.trim().trim_matches('/');
    if bucket.len() < 3 || bucket.len() > 63 || !bucket.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'.' || c == b'-') {
        return Err("Enter a valid S3 bucket name (lowercase letters, numbers, dots or hyphens)".into());
    }
    if region.is_empty() || !region.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-') {
        return Err("Enter a valid S3 region".into());
    }
    if !endpoint.is_empty() && (!endpoint.starts_with("https://") || endpoint.len() <= 8 || endpoint.contains(['@', '?', '#', ' ', '\\'])) {
        return Err("The optional endpoint must be an HTTPS URL without credentials or query parameters".into());
    }
    if prefix.split('/').any(|part| part == "." || part == "..") || prefix.contains('\\') || prefix.chars().any(char::is_control) {
        return Err("Enter an object prefix without path traversal or control characters".into());
    }
    if input.access_key_id.trim().is_empty() || input.secret_access_key.is_empty() {
        return Err("Enter both the access key ID and secret access key".into());
    }
    if input.access_key_id.chars().any(char::is_control) || input.secret_access_key.chars().any(char::is_control) {
        return Err("Credentials cannot contain control characters".into());
    }
    Ok(S3Config {
        bucket: bucket.into(), region: region.into(), endpoint: endpoint.into(),
        prefix: if prefix.is_empty() { String::new() } else { format!("{prefix}/") },
    })
}

#[tauri::command]
pub fn get_s3_connection(app: AppHandle) -> Result<S3ConnectionStatus, String> {
    status(&config_database(&app)?)
}

#[tauri::command]
pub fn save_s3_connection(app: AppHandle, input: S3ConnectionInput) -> Result<S3ConnectionStatus, String> {
    let config = validated(&input)?;
    let connection = config_database(&app)?;
    let previous_target = stored_config(&connection)?.map(|saved| format!("{}/{}", saved.bucket, saved.prefix));
    let new_target = format!("{}/{}", config.bucket, config.prefix);
    let previous = credential_store::read(CREDENTIAL_TARGET)?;
    credential_store::write(CREDENTIAL_TARGET, &input.access_key_id, &input.secret_access_key)?;
    if connection.execute("INSERT INTO s3_connection (id, bucket, region, endpoint, prefix)
        VALUES (1, ?1, ?2, ?3, ?4)
        ON CONFLICT(id) DO UPDATE SET bucket=excluded.bucket, region=excluded.region,
            endpoint=excluded.endpoint, prefix=excluded.prefix, last_verified_at=NULL",
        params![config.bucket, config.region, config.endpoint, config.prefix]).is_err() {
        match previous {
            Some((key, secret)) => { let _ = credential_store::write(CREDENTIAL_TARGET, &key, &secret); }
            None => { let _ = credential_store::delete(CREDENTIAL_TARGET); }
        }
        return Err("Could not save S3 settings".into());
    }
    if previous_target.as_deref() != Some(new_target.as_str()) {
        let sync_table_exists = connection.query_row(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='sync_items'", [], |_| Ok(true))
            .optional().map_err(|_| "Could not inspect local sync state".to_string())?.unwrap_or(false);
        if sync_table_exists {
            connection.execute("UPDATE sync_items SET target=?1, state='not_synced', original_done=0,
                preview_done=0, thumbnail_done=0, manifest_done=0, synced_at=NULL, error=NULL", params![new_target])
                .map_err(|_| "S3 settings were saved, but local sync state could not be reset".to_string())?;
        }
        let exists = |name: &str| connection.query_row(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1", params![name], |_| Ok(true))
            .optional().map(|value| value.unwrap_or(false)).map_err(|error| error.to_string());
        if exists("favorite_events")? {
            connection.execute("UPDATE favorite_events SET uploaded=0", [])
                .map_err(|error| error.to_string())?;
        }
        if exists("applied_events")? {
            connection.execute("DELETE FROM applied_events", []).map_err(|error| error.to_string())?;
        }
        if exists("remote_assets")? {
            connection.execute("DELETE FROM remote_assets", []).map_err(|error| error.to_string())?;
        }
        if exists("assets")? {
            connection.execute("DELETE FROM assets WHERE source_path=''", []).map_err(|error| error.to_string())?;
        }
        if exists("media_cache")? {
            connection.execute("DELETE FROM media_cache", []).map_err(|error| error.to_string())?;
            let root = app.path().app_cache_dir().map_err(|error| error.to_string())?.join("cloud-media");
            if root.is_dir() { std::fs::remove_dir_all(&root).map_err(|error| error.to_string())?; }
        }
    }
    status(&connection)
}

#[tauri::command]
pub fn remove_s3_connection(app: AppHandle) -> Result<S3ConnectionStatus, String> {
    let connection = config_database(&app)?;
    credential_store::delete(CREDENTIAL_TARGET)?;
    connection.execute("DELETE FROM s3_connection WHERE id = 1", [])
        .map_err(|_| "Credentials were removed, but the local S3 settings could not be cleared".to_string())?;
    status(&connection)
}

#[tauri::command]
pub async fn test_s3_connection(app: AppHandle) -> Result<bool, String> {
    let (config, key, secret) = {
        let connection = config_database(&app)?;
        connection.execute("UPDATE s3_connection SET last_verified_at = NULL WHERE id = 1", [])
            .map_err(|_| "Could not update S3 verification status".to_string())?;
        let config = stored_config(&connection)?
            .ok_or_else(|| "Save S3 connection settings first".to_string())?;
        let (key, secret) = credential_store::read(CREDENTIAL_TARGET)?
            .ok_or_else(|| "Saved S3 credentials are missing".to_string())?;
        (config, key, secret)
    };
    let mut builder = aws_sdk_s3::Config::builder()
        .behavior_version(BehaviorVersion::latest())
        .region(Region::new(config.region))
        .sleep_impl(TokioSleep::new())
        .timeout_config(TimeoutConfig::builder()
            .operation_timeout(Duration::from_secs(20))
            .operation_attempt_timeout(Duration::from_secs(8))
            .build())
        .credentials_provider(Credentials::new(key, secret, None, None, "Gallery protected store"));
    #[cfg(target_os = "android")]
    { builder = builder.http_client(android_http_client()?); }
    if !config.endpoint.is_empty() {
        builder = builder.endpoint_url(config.endpoint).force_path_style(true);
    }
    let client = aws_sdk_s3::Client::from_conf(builder.build());
    let request = client.list_objects_v2()
        .bucket(config.bucket)
        .prefix(config.prefix)
        .max_keys(1)
        .send();
    let response = tokio::time::timeout(Duration::from_secs(25), request).await
        .map_err(|_| "S3 did not respond within 25 seconds. Check the phone network and try again.".to_string())?;
    response.map_err(|error| match error.as_service_error().and_then(|value| value.code()) {
        Some(code) => format!("S3 rejected the connection ({code}). Check the bucket, region, access key and IAM policy."),
        None => "S3 could not be reached. Check the phone network and bucket region.".to_string(),
    })?;
    let connection = config_database(&app)?;
    connection.execute("UPDATE s3_connection SET last_verified_at = ?1 WHERE id = 1",
        params![chrono::Utc::now().timestamp_millis()])
        .map_err(|_| "S3 access succeeded, but its verification time could not be saved".to_string())?;
    Ok(true)
}

#[cfg(target_os = "windows")]
mod credential_store {
    use std::{ffi::c_void, ptr};

    const CRED_TYPE_GENERIC: u32 = 1;
    const CRED_PERSIST_LOCAL_MACHINE: u32 = 2;
    const ERROR_NOT_FOUND: i32 = 1168;

    #[repr(C)]
    struct FileTime { low: u32, high: u32 }

    #[repr(C)]
    struct CredentialW {
        flags: u32,
        kind: u32,
        target_name: *mut u16,
        comment: *mut u16,
        last_written: FileTime,
        credential_blob_size: u32,
        credential_blob: *mut u8,
        persist: u32,
        attribute_count: u32,
        attributes: *mut c_void,
        target_alias: *mut u16,
        user_name: *mut u16,
    }

    #[link(name = "Advapi32")]
    extern "system" {
        fn CredWriteW(credential: *const CredentialW, flags: u32) -> i32;
        fn CredReadW(target: *const u16, kind: u32, flags: u32, credential: *mut *mut CredentialW) -> i32;
        fn CredDeleteW(target: *const u16, kind: u32, flags: u32) -> i32;
        fn CredFree(buffer: *mut c_void);
    }

    fn wide(value: &str) -> Vec<u16> { value.encode_utf16().chain(std::iter::once(0)).collect() }

    unsafe fn from_wide(value: *const u16) -> String {
        if value.is_null() { return String::new(); }
        let mut length = 0;
        while *value.add(length) != 0 { length += 1; }
        String::from_utf16_lossy(std::slice::from_raw_parts(value, length))
    }

    pub fn read(target: &str) -> Result<Option<(String, String)>, String> {
        let target = wide(target);
        let mut pointer: *mut CredentialW = ptr::null_mut();
        if unsafe { CredReadW(target.as_ptr(), CRED_TYPE_GENERIC, 0, &mut pointer) } == 0 {
            return if std::io::Error::last_os_error().raw_os_error() == Some(ERROR_NOT_FOUND) {
                Ok(None)
            } else { Err("Could not read Windows Credential Manager".into()) };
        }
        let result = unsafe {
            let credential = &*pointer;
            let key = from_wide(credential.user_name);
            let secret = if credential.credential_blob_size == 0 || credential.credential_blob.is_null() {
                Err("Stored S3 secret is empty".to_string())
            } else {
                let bytes = std::slice::from_raw_parts(credential.credential_blob, credential.credential_blob_size as usize);
                String::from_utf8(bytes.to_vec()).map_err(|_| "Stored S3 secret is invalid UTF-8".to_string())
            };
            CredFree(pointer.cast());
            secret.map(|secret| (key, secret))
        };
        result.map(Some)
    }

    pub fn write(target: &str, key: &str, secret: &str) -> Result<(), String> {
        let mut target = wide(target);
        let mut key = wide(key);
        let mut secret = secret.as_bytes().to_vec();
        if secret.len() > 2560 { return Err("S3 secret is too long for Windows Credential Manager".into()); }
        let credential = CredentialW {
            flags: 0, kind: CRED_TYPE_GENERIC, target_name: target.as_mut_ptr(), comment: ptr::null_mut(),
            last_written: FileTime { low: 0, high: 0 }, credential_blob_size: secret.len() as u32,
            credential_blob: secret.as_mut_ptr(), persist: CRED_PERSIST_LOCAL_MACHINE,
            attribute_count: 0, attributes: ptr::null_mut(), target_alias: ptr::null_mut(), user_name: key.as_mut_ptr(),
        };
        if unsafe { CredWriteW(&credential, 0) } == 0 { Err(format!("Could not save credentials in Windows Credential Manager (Windows error {})", std::io::Error::last_os_error().raw_os_error().unwrap_or_default())) }
        else { Ok(()) }
    }

    pub fn delete(target: &str) -> Result<(), String> {
        let target = wide(target);
        if unsafe { CredDeleteW(target.as_ptr(), CRED_TYPE_GENERIC, 0) } != 0 ||
            std::io::Error::last_os_error().raw_os_error() == Some(ERROR_NOT_FOUND) { Ok(()) }
        else { Err("Could not remove credentials from Windows Credential Manager".into()) }
    }
}

#[cfg(any(target_os = "macos", target_os = "android"))]
mod credential_store {
    use keyring_core::{Entry, Error};
    use std::sync::OnceLock;

    static INITIALIZED: OnceLock<Result<(), String>> = OnceLock::new();

    fn entry(target: &str) -> Result<Entry, String> {
        INITIALIZED.get_or_init(|| {
            #[cfg(target_os = "macos")]
            let store = apple_native_keyring_store::keychain::Store::new()
                .map_err(|_| "Could not open macOS Keychain".to_string())?;
            #[cfg(target_os = "android")]
            let store = android_native_keyring_store::Store::new()
                .map_err(|_| "Could not open Android Keystore".to_string())?;
            keyring_core::set_default_store(store);
            Ok(())
        }).clone()?;
        Entry::new(target, "s3").map_err(|_| "Could not access protected credential entry".into())
    }

    pub fn read(target: &str) -> Result<Option<(String, String)>, String> {
        match entry(target)?.get_password() {
            Ok(json) => serde_json::from_str(&json).map(Some)
                .map_err(|_| "Stored S3 credentials are invalid".into()),
            Err(Error::NoEntry) => Ok(None),
            Err(_) => Err("Could not read protected S3 credentials".into()),
        }
    }

    pub fn write(target: &str, key: &str, secret: &str) -> Result<(), String> {
        let json = serde_json::to_string(&(key, secret)).map_err(|_| "Could not encode credentials".to_string())?;
        entry(target)?.set_password(&json).map_err(|_| "Could not save protected S3 credentials".into())
    }

    pub fn delete(target: &str) -> Result<(), String> {
        match entry(target)?.delete_credential() {
            Ok(()) | Err(Error::NoEntry) => Ok(()),
            Err(_) => Err("Could not remove protected S3 credentials".into()),
        }
    }
}

#[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "android")))]
mod credential_store {
    pub fn read(_target: &str) -> Result<Option<(String, String)>, String> { Ok(None) }
    pub fn write(_target: &str, _key: &str, _secret: &str) -> Result<(), String> { Err("Protected credential storage is unavailable".into()) }
    pub fn delete(_target: &str) -> Result<(), String> { Ok(()) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_unsafe_connection_values() {
        let mut input = S3ConnectionInput {
            bucket: "my-gallery-bucket".into(), region: "ap-southeast-2".into(),
            endpoint: String::new(), prefix: "gallery".into(),
            access_key_id: "EXAMPLEKEY".into(), secret_access_key: "example-secret".into(),
        };
        assert_eq!(validated(&input).unwrap().prefix, "gallery/");
        input.endpoint = "http://example.com".into();
        assert!(validated(&input).is_err());
        input.endpoint = String::new();
        input.prefix = "gallery/../private".into();
        assert!(validated(&input).is_err());
    }

    #[test]
    fn masks_access_key_id() {
        assert_eq!(mask_key("AKIAEXAMPLE1234"), "••••1234");
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn windows_credential_round_trip_uses_disposable_target() {
        let target = format!("com.pshand.gallery/test-{}", std::process::id());
        assert!(credential_store::read(&target).unwrap().is_none());
        credential_store::write(&target, "EXAMPLEKEY", "example-secret").unwrap();
        assert_eq!(credential_store::read(&target).unwrap(), Some(("EXAMPLEKEY".into(), "example-secret".into())));
        credential_store::delete(&target).unwrap();
        assert!(credential_store::read(&target).unwrap().is_none());
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn macos_keychain_round_trip_uses_disposable_target() {
        let target = format!("com.pshand.gallery/test-{}", std::process::id());
        assert!(credential_store::read(&target).unwrap().is_none());
        credential_store::write(&target, "EXAMPLEKEY", "example-secret").unwrap();
        assert_eq!(credential_store::read(&target).unwrap(), Some(("EXAMPLEKEY".into(), "example-secret".into())));
        credential_store::delete(&target).unwrap();
        assert!(credential_store::read(&target).unwrap().is_none());
    }
}
