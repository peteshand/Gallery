# Android HTTPS certificate roots

`cacert.pem` is curl's PEM conversion of the Mozilla CA certificate store, downloaded from
https://curl.se/ca/cacert.pem on 2026-09-23. The corresponding curl SHA-256 file is
`cacert.pem.sha256`; the bundle hash is
`f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9`.

curl states that the source bundle is licensed under MPL 2.0. Update the bundle regularly
because trusted roots change. Android uses this bundle for the AWS SDK's rustls client because
that client could not parse roots from the phone's native certificate store. TLS verification
remains enabled.
