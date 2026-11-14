# Layer 05 — Backend Security and Secret Protection

**Target branch:** `dev`  
**Audit / implementation:** 2026-11-14  
**Implementation status:** Secure-storage migration implemented; automated and device verification pending.

## Executive summary

No MuziiNap-owned backend was introduced. The inspected InnerTube API key is client-visible public configuration, and BgUtils uses a user-configured provider. Moving those requests behind a new server would add operational cost without protecting a genuinely private credential.

The prior implementation persisted YouTube cookies, identity tokens, and Piped bearer tokens in the unencrypted Hive preferences box. A Piped bearer token was also logged. The logging issue is fixed, and credential persistence has now been migrated to Android Keystore-backed secure storage.

## Sanitized secret inventory

| File / location | Category | Sensitive? | Exposure risk | Current remediation |
|---|---|---:|---|---|
| `lib/services/constant.dart` — InnerTube `key` query parameter | Public configuration | No, by itself | Medium if unrestricted; visible in source/APK | Remains client-side. Owner should verify Google Cloud API restrictions and quotas. Do not treat obfuscation as secrecy. |
| `lib/services/music_service.dart` — shared InnerTube request parameters | Public configuration | No, by itself | Same as above | No backend migration. Visitor identifiers and raw exception details are redacted from diagnostics. |
| YouTube cookies / SAPISID / identity token | User-specific credentials | **Yes** | High if stored in plaintext or logs | Stored in `CredentialVault` using `flutter_secure_storage`; Android uses Keystore-wrapped RSA-OAEP + AES-GCM storage. |
| YouTube visitor data, data-sync ID, auth-user context | User-specific session data | Sensitive context | Medium | Stored with account session records in secure storage, not Hive. |
| Piped bearer token | User-specific private API token | **Yes** | High if stored in plaintext or logs | Stored in secure storage. Hive retains only link state and the HTTPS instance URL. |
| Piped instance URL | Public endpoint configuration | No | Medium if user selects an untrusted instance | HTTPS-only validation; user should trust the selected Piped operator. |
| BgUtils endpoint | Public endpoint configuration | No | Depends on the configured third-party provider | No embedded private credential found in the inspected adapter. |
| GitHub Actions signing and symbol-encryption values | Cryptographic material | **Yes** | High if committed or printed | Inspected release workflows read these values from GitHub Secrets. Keep them out of artifacts and logs. |
| `android/app/build.gradle` trusted release certificate SHA-256 | Public integrity metadata | No | Low | Public fingerprint; not a signing private key. |
| Native C/C++, assets, JSON, inspected build configuration | Credential / cryptographic material | No additional confirmed private secret found by the searches performed | Not exhaustive | Full-history and release-artifact scans remain owner-side verification tasks. |

Actual credential values are intentionally omitted.

## Secure-storage implementation

- Added `flutter_secure_storage: ^10.3.4` (compatible with the repository's existing `device_info_plus` dependency).
- Added `lib/services/credential_vault.dart` as the single credential boundary.
- Android secure storage uses the plugin's default RSA-OAEP key wrapping and AES-GCM data encryption. The encryption key is protected by Android Keystore; no universal key is embedded in Dart, Kotlin, assets, or build configuration.
- YouTube account records, active session cookies/context, and the Piped bearer token are stored in secure storage.
- Hive keeps only non-secret account display metadata, the active account identifier, the Piped link flag, and the HTTPS instance URL.
- `InnerTubeSessionManager` reads session cookies from the vault. The expiry timestamp remains in Hive because it is not a credential.
- YouTube login, account switching, session expiry, disconnect, Piped login, and Piped unlink now use the vault.
- The legacy migration runs after Hive opens and before application services start. It writes secure values, reads them back for verification, and only then removes plaintext Hive copies.
- If secure storage is unavailable or migration fails, legacy values are not deleted. Authenticated mode is disabled for that launch while local playback remains available; the user can retry on a later launch or sign in again.
- Android backup rules exclude SharedPreferences (including secure-storage ciphertext) from cloud backup and device transfer. This avoids restoring ciphertext without the device-bound Keystore key.

## GitHub Actions and release handling

- The inspected release workflows read Android signing values and the symbol-encryption key from `secrets.*`.
- The workflows print validation status and derived build metadata, not the secret values.
- The expected signing certificate fingerprint is public integrity metadata.
- Do not upload keystores, local environment files, symbol-encryption keys, or unencrypted symbol archives as public artifacts.
- A credential committed at any time must be treated as exposed even after a later source deletion; revoke/rotate it at the provider.

## Backend decision

No backend endpoint or new server dependency was added. The InnerTube key is a public client configuration value, and BgUtils is a user-configured provider. A MuziiNap backend would add hosting, authentication, abuse controls, monitoring, and availability dependencies without removing the need for public client identity. Reconsider a backend only if MuziiNap later owns a genuinely private third-party credential or server-side entitlement/business rule.

## Rotation and incident response

1. **Previously logged Piped token:** unlink the Piped account and sign in again. Revoke the old token/session at the Piped instance if it supports revocation. Previously captured logs or shared diagnostics cannot be made safe by deleting the source log statement.
2. **YouTube cookies / identity token:** disconnect the YouTube account and revoke the app session from Google account security if exposure is suspected; sign in again after containment.
3. **Google/InnerTube API key:** do not rotate solely because it is visible in a public client. Verify API restrictions and quotas. If unrestricted or abused, restrict or rotate it in Google Cloud and update the public client configuration.
4. **Android signing key / symbol-encryption key:** never print or commit replacements. Follow the Android app-signing recovery/upgrade-key process and rotate the symbol key separately. Old encrypted symbol archives may require the old key for symbolication.
5. Preserve incident evidence securely, determine the exposure window and affected accounts, revoke credentials at their issuer, and validate the replacement path without placing values in source control.

## Tests and remaining verification

Added regression coverage:
- `test/services/credential_vault_test.dart`: migration of YouTube/Piped credentials, secure-write failure preserving legacy data, Hive metadata sanitization, and Piped token deletion.
- `test/services/innertube_session_manager_test.dart`: session headers via injected vault and assertion that cookies are not written to Hive.
- `test/services/piped_service_security_test.dart`: HTTPS URL validation and rejection of credential-bearing or malformed endpoints.

The code changes have been committed to `dev`. A successful source commit is not proof that the new CI run or device tests passed. Confirm the new `flutter pub get`, analyzer, and Flutter test workflow after these commits. Also verify on a real Android device:
- Upgrade from a build containing legacy Hive sessions and confirm migration preserves account switching.
- Confirm YouTube login, personalized home, queue, downloads, and background playback.
- Confirm Piped login, playlist operations, and unlink/relink.
- Confirm reinstall/restore behavior: secure credentials are intentionally device-bound and excluded from Android backup, so users may need to sign in again after reinstall or device transfer.
- Confirm the secure-storage dependency resolves in the project's pinned Flutter toolchain and commit the generated lockfile if CI updates it.

**Residual risk:** rooted devices, runtime instrumentation, memory inspection, and an attacker controlling the unlocked app process can still access credentials while the app uses them. Keystore-backed storage protects data at rest; it does not make a compromised runtime safe. Full Git history scanning, provider-side API-key restriction review, and release-artifact scanning remain separate verification tasks.
