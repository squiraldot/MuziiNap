# Layer 05 — Backend Security and Secret Protection

**Target branch:** `dev`  
**Audit baseline:** 2026-11-14  
**Implementation status:** Partial remediation; see unresolved risks below.

## Executive summary

The inspected application does not currently require a MuziiNap-owned backend for its YouTube extraction flow. The InnerTube key is a client-visible Google/YouTube configuration value, not a server credential. Moving extraction to a new backend would add operational cost and latency without making a public client key secret.

The audit found user-specific YouTube and Piped credentials persisted in the unencrypted Hive preferences box. A Piped bearer token was also written to application logs. The log disclosure was removed, and Piped instance URLs are now validated as HTTPS before login credentials are sent. **At-rest credential encryption remains unresolved and must not be considered fixed by this layer's current changes.**

## Sanitized secret inventory

| File / location | Category | Sensitive? | Exposure risk | Remediation / status |
|---|---|---:|---|---|
| `lib/services/constant.dart` — InnerTube `key` query parameter | Public configuration | No, by itself | Medium if unrestricted; the key is shipped in the client and visible in source/APK | Keep client-side; owner should verify Google Cloud API restrictions, quotas, and allowed APIs. Do not treat obfuscation as secrecy. |
| `lib/services/music_service.dart` — shared InnerTube request parameters | Public configuration | No, by itself | Same as above | No backend migration required. Session identifiers were removed from diagnostic messages. |
| `lib/services/innertube_session_manager.dart` — `yt_cookies` and SAPISID-derived authorization | User-specific credentials / cryptographic derivation input | **Yes** | High: cookies are bearer-like account credentials and Hive is opened without an encryption cipher | Move cookie material to Android Keystore-backed secure storage. Keep cookies out of logs and ordinary backups. Not yet migrated. |
| `lib/ui/screens/Settings/youtube_login_screen.dart` and `lib/services/music_service.dart` — `yt_accounts`, `yt_cookies`, `yt_identity_token` | User-specific credentials | **Yes** for cookies and identity token; other fields are session metadata | High: multi-account records duplicate sensitive values in unencrypted Hive | Migrate all account-scoped credentials atomically to secure storage; preserve account switching and legacy migration. Not yet migrated. |
| `lib/services/piped_service.dart` — `piped.token` | User-specific private API token | **Yes** | High: unencrypted Hive persistence; token was also logged | Token log removed. HTTPS-only instance validation added. At-rest migration to secure storage remains unresolved. |
| `.github/workflows/release.yml`, `.github/workflows/muziinap-apk.yml` | Build/signing cryptographic material | **Yes** | High if committed or printed | Signing keystore and passwords, plus symbol-encryption key, are already sourced from GitHub Actions Secrets. Workflow logs show status messages, not secret values. Keep them in GitHub Secrets only. |
| `android/app/build.gradle` — trusted release certificate SHA-256 | Public integrity metadata | No | Low; certificate fingerprints are public verification data | Keep public fingerprint in BuildConfig; it is not a private key. |
| BgUtils provider URL and YouTube visitor/session context | Public endpoint configuration / user-specific request context | Endpoint: No; request context: potentially identifying | Medium when a user configures a third-party remote provider | Remote provider URLs require HTTPS; use only a provider you trust. No backend credential was found in this adapter. |
| Native C/C++, assets, JSON, and inspected build configuration | Credential / cryptographic material | No additional confirmed private secret found by the searches performed | Not exhaustive | Continue secret scanning on full repository history and release artifacts. |

Actual credential values are intentionally omitted from this report.

## Changes made on `dev`

- `lib/services/piped_service.dart`
  - Removed the successful-login log that printed the returned bearer token.
  - Added HTTPS URL validation for Piped login and stored instance configuration.
  - Rejects URLs containing user-info, query strings, or fragments.
  - Validates the login response before persisting its token.
  - Replaced raw Dio login errors with sanitized status-only diagnostics.
- `lib/services/music_service.dart`
  - Removed YouTube visitor identifiers from diagnostic logs.
  - Replaced raw Dio exception logging with a sanitized status-only message.
- `test/services/piped_service_security_test.dart`
  - Added coverage for HTTPS acceptance, trailing-slash normalization, and rejection of HTTP, embedded credentials, query strings, fragments, and invalid hosts.

## Backend decision

No new backend endpoint was introduced. The inspected YouTube InnerTube key is a public client configuration value, and the optional BgUtils adapter is designed to call a user-configured provider. A MuziiNap backend would add hosting, authentication, abuse controls, monitoring, and availability dependencies without removing the need for a public client identity. Reconsider a backend only if MuziiNap later owns a genuinely private third-party credential or server-side entitlement/business rule.

## GitHub Actions and release handling

- The inspected release workflows read Android signing values and the symbol-encryption key from `secrets.*`.
- The workflows do not print the secret values; they print validation status and derived build metadata.
- The expected signing certificate fingerprint is derived at build time and is public integrity metadata, not a signing secret.
- Do not upload keystores, local environment files, symbol-encryption keys, or unencrypted symbol archives as public artifacts.
- Keep private obfuscation/debug symbols restricted to authorized maintainers.
- A credential committed at any time must be treated as exposed even after a later source deletion; revoke/rotate it at the provider.

## Rotation and incident response

1. **Piped token:** disconnect the affected Piped account and sign in again to obtain a new token. If the instance offers token/session revocation, revoke the previous session there. Review device logs and any shared diagnostic bundles; previously captured logs cannot be made safe by deleting the source log statement.
2. **YouTube cookies / identity token:** disconnect the YouTube account in MuziiNap and revoke the app's session from the Google account security page if exposure is suspected; sign in again after the incident is contained.
3. **Google/InnerTube API key:** do not rotate solely because it is visible in a public client. First verify API restrictions and quotas in the owning Google Cloud project. If it is unrestricted or abused, restrict it or rotate it in the provider console and update the public client configuration.
4. **Android signing key / symbol-encryption key:** never print or commit replacements. If compromised, follow the Android app-signing recovery/upgrade-key process and rotate the symbol key separately; old encrypted archives may require the old key for symbolication.
5. Preserve incident evidence securely, determine exposure window and affected accounts, revoke the credential at its issuer, then validate the new credential path without placing it in source control.

## Verification and limits

- Static searches covered API-key markers, common token prefixes, private-key headers, credential assignments, YouTube auth/session code, Piped integration, BgUtils, Gradle, and the two inspected release workflows.
- The new Piped URL validation regression tests were added but have not yet been executed in a repository CI run at the time this document was written.
- No real-device playback, queue, download, deep-link, background-playback, or remote BgUtils integration test is claimed here.
- Full Git history scanning, GitHub secret-scanning alert review, Google Cloud API-key restriction review, and inspection of every release artifact require owner-side/provider-side verification.
- **Unresolved high-risk item:** YouTube cookies, identity tokens, and Piped bearer tokens remain persisted in the unencrypted Hive preferences box. Implementing secure storage safely requires a tested migration that preserves multi-account switching and existing installations. Do not describe Layer 05 as fully complete until that migration and regression testing are finished.
