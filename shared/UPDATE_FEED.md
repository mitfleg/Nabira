# Nabira signed update feed v1

Every update feed keeps the legacy top-level `version`, `url`, `notes`, and `sha256` fields so an
older client can discover the transition release. New clients ignore those fields until they have
verified the signed payload.

The trusted fields are stored as compact UTF-8 JSON, then standard Base64 encoded in
`signed_payload`. The decoded object contains exactly:

```json
{"schema":1,"platform":"macos","version":"3.4.0","url":"https://nabira.site/downloads/Nabira-macOS.dmg?version=3.4.0","notes":"...","sha256":"..."}
```

`signature` is standard Base64 containing an ASN.1 DER ECDSA P-256/SHA-256 signature over the raw
decoded payload bytes. `signature_algorithm` is `ecdsa-p256-sha256`. `key_id` is the first 16
hexadecimal characters of SHA-256 over the DER SubjectPublicKeyInfo.

Clients must:

1. decode `signed_payload` and `signature` with strict standard Base64;
2. verify the signature with the embedded public key before using any payload field;
3. require `schema == 1` and the exact platform (`macos` or `windows`);
4. require HTTPS on `nabira.site` and the platform-specific download path;
5. verify the downloaded file's SHA-256 before replacing the installed application;
6. verify the bundle/executable identity before restart.

The private key never belongs in Git, an application bundle, or on the web server. The controlled
release automation receives it only through the encrypted GitHub Actions secret
`NABIRA_UPDATE_SIGNING_KEY_PEM`, writes a temporary copy, and deletes it in a `finally` block. The
maintainer copy lives outside the repository at
`~/Library/Application Support/NabiraRelease/update-signing-private.pem`. Back it up offline:
losing it makes existing clients unable to trust future releases.

Sign and verify feeds with `scripts/update_feed.py`.
