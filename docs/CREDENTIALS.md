# S3 connection settings

The native app has a **Settings → Cloud storage** form. Windows saves the access key ID and secret in Credential Manager. macOS Keychain and Android Keystore backed adapters are implemented in Rust but await builds and device tests on those platforms. Bucket, region, endpoint, and prefix are stored in the local SQLite catalogue. The app displays only the last four characters of the saved access key ID and a placeholder in the secret field. **Test connection** uses the official AWS Rust SDK to make a read-only `ListObjectsV2` request under the configured prefix. The browser version has no credential form. Saving and testing are local/read-only actions; **Sync now**, a photo's **Back up now** button, and the selection toolbar upload photos separately.

## Settings flow

1. Enter the S3 bucket, region, optional endpoint and object prefix, access key ID, and secret access key.
2. Gallery passes the credentials once from the Haxe form to a Rust command. Rust checks field syntax and writes the access key ID and secret to the operating system's protected credential store. Non-secret bucket settings live in the local catalogue.
3. The UI receives only connection status and a masked access key ID. It never reads a saved secret back. The saved secret field contains a visual placeholder, not the secret. Replacing or removing a connection is an explicit Settings action.
4. Upload commands retrieve credentials inside Rust. Logs, errors, catalogue events, and S3 object metadata exclude both keys.

The platform stores are Windows Credential Manager, macOS Keychain, and Android storage protected by Android Keystore. The Windows implementation calls [Win32 Credential Manager](https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credwritew) directly. The macOS and Android implementations use [Apple Native Keyring Store](https://docs.rs/apple-native-keyring-store/) and [Android Native Keyring Store](https://docs.rs/android-native-keyring-store/). Neither adapter falls back to a plaintext sample store. Platform build and persistence tests remain required.

## Validation and access

The connection check makes a non-mutating `ListObjectsV2` request using the configured prefix and a one-object limit. Success verifies bucket reachability, key authentication, and list permission at the time of the request, including when the prefix contains no objects. The result timestamp is stored locally and cleared when settings change or a later test begins. Failures return a fixed, non-secret message; no AWS SDK error object is sent to the UI. The bucket policy should limit listing to Gallery's prefix and object access to the required media and catalogue keys. Credential replacement preserves the previous stored key if the new write fails.

## Getting the bucket details (AWS S3)

1. In the AWS S3 console, create a private bucket or choose an existing private bucket. Keep **Block Public Access** enabled. Copy its exact name and AWS Region.
2. Choose a dedicated object prefix such as `gallery/`. Gallery's prefix field accepts `gallery` and normalizes it to `gallery/`.
3. In IAM, create a dedicated identity with a policy scoped to that bucket and prefix. Grant `s3:ListBucket` with an `s3:prefix` condition for `gallery/*`, and `s3:GetObject` and `s3:PutObject` on `arn:aws:s3:::YOUR_BUCKET/gallery/*` for backup. Avoid account-wide S3 access and do not create a root access key. AWS has [prefix policy examples](https://docs.aws.amazon.com/AmazonS3/latest/userguide/amazon-s3-policy-keys.html) and [access key guidance](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials-access-keys.html).
4. Create one access key for that IAM identity. Enter the ID and secret **directly in Gallery on your device**. Do not paste the secret into chat, a source file, a command line, or a screenshot. AWS shows the secret only at creation, so store a recovery copy in your password manager if desired.
5. Leave Endpoint empty for AWS S3. S3-compatible providers need their HTTPS endpoint; their permission and region setup may differ.

For AWS, this IAM identity policy is a starting point for prefix `gallery/`. Replace `YOUR_BUCKET` with the new bucket name in both Resource values. It allows the read-only prefix listing needed for connection checks and the object reads/writes used by backup. It grants no bucket administration or object deletion. Check the exact final permissions again when implementing multipart uploads.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListGalleryPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::YOUR_BUCKET",
      "Condition": { "StringLike": { "s3:prefix": "gallery/*" } }
    },
    {
      "Sid": "ReadWriteGalleryObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::YOUR_BUCKET/gallery/*"
    }
  ]
}
```

## Acceptance checks

- Saving a connection survives an app restart on Windows, macOS, and Android. Windows persistence is implemented and tested; macOS and Android need platform verification.
- The UI can show whether a connection exists without returning its secret.
- A repository search, SQLite inspection, and captured logs show no saved access key or secret.
- Wrong credentials, a missing bucket, offline use, replacement, and removal produce clear outcomes without leaking secret text. The user confirmed that the read-only remote check passed against the dedicated bucket.
- A fresh device can configure its own local credentials and sync without copying another device's credential store.
