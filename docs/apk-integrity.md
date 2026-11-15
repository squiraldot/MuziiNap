# APK integrity and tamper detection

**Layer:** 04 — Android APK integrity  
**Repository:** `squiraldot/MuziiNap`  
**Maintenance branch:** `dev`

## Distribution and trust boundary

The official APK distribution destination is the MuziiNap Telegram channel: https://telegram.me/muziinap/3. The separate repository https://github.com/squiraldot/MuziiNap-Official supplies version/release metadata to the app's update checker; it is not the APK download host. The MuziiNap `release.yml` workflow uploads build outputs as GitHub Actions artifacts and does not publish GitHub Releases. The audited repository does not declare Google Play distribution or a first-party trusted backend for integrity-token verification. Play Integrity is not enabled and is not required for sideloaded installs.

This implementation performs a local Android package/signing identity check. It is a repackaging signal, not proof against a determined attacker: client-side code and embedded fingerprints can be patched or extracted. Any future protected server feature must independently verify server-issued challenges and integrity evidence before granting sensitive access.

## Signing identity

- Android application ID: `com.merrmist.muziinapmusic`.
- Debug builds are classified separately and do not use the release pin.
- The `muziinap-apk.yml` and `release.yml` workflows restore the existing Actions keystore and derive its SHA-256 certificate fingerprint from the public certificate. `muziinap-apk.yml` builds one universal APK on `main`/`dev` pushes or manual dispatch; `release.yml` builds universal and ABI-specific APKs on `main` pushes or manual dispatch.
- The fingerprint is injected into generated `BuildConfig.TRUSTED_RELEASE_CERT_SHA256S`; no private key or keystore is packaged.
- CI verifies each release APK with `apksigner` and compares its signer fingerprint with the restored CI keystore.

The fingerprint is public identity data, not a secret. Its exact value is derived at workflow runtime and is visible in APK signature metadata and generated build configuration.

## Runtime behavior

At native startup, `ApkIntegrityVerifier` checks the runtime package ID, reads installed signer certificates through Android PackageManager, hashes certificates with SHA-256, and compares them with the trusted set. On Android 9/API 28+, single-signer apps use `signingCertificateHistory` to recognize Android-verified signing-key rotation; multiple-signer apps use their current signer set. Older supported Android versions use the legacy signatures API.

Results are logged locally. No device identifiers are collected and no telemetry is transmitted. A mismatch is not treated as trusted, but startup continues to avoid breaking legitimate sideloaded installations. The current architecture has no server-protected feature wired to this signal.

## Failure policy

| Condition | Result | Behavior |
| --- | --- | --- |
| Official release signer matches | Trusted release | Continue |
| Debug build | Debug build | Continue |
| Release pin absent (e.g. local debug-signed release fallback) | Unconfigured | Warn and continue |
| Package ID mismatch | Failure signal | Log error and continue |
| Unexpected signer / repackaged APK | Failure signal | Log error and continue |
| PackageManager exception | Verification unavailable | Warn and continue |

The check has no network dependency; offline operation and backend outages cannot block startup. There is no automatic termination or root-only decision.

## Google Play and Play Integrity

Play Integrity is not integrated. If Play distribution is introduced, integrate it only for Play-distributed builds and verify tokens on a trusted backend. The backend must validate request freshness, package identity, recognized signing certificate, verdict policy, and replay protection. Never accept a client-side Boolean as proof. Do not impose Play Integrity on direct APK builds.

## Key rotation

Use Android's supported signing lineage for a legitimate signing-key upgrade. The verifier checks the platform-provided signing history on API 28+ for single-signer packages. Each build pins the certificate used by the CI signing keystore, so a properly lineage-signed new release receives its new certificate pin while Android exposes the validated signing history. Keep the existing signing identity and lineage secure; do not rotate merely to silence a mismatch.

## Verification and testing

JUnit policy tests cover fingerprint normalization, trusted current/historical signer acceptance, unexpected signer rejection, debug separation, missing-pin behavior, and package-ID mismatch. Android CI verifies APK signature validity and confirms that the signer matches the CI keystore.

Run with the pinned repository toolchain:

```bash
flutter pub get
flutter test --no-pub
gradle -p android :app:testDebugUnitTest --no-daemon
flutter build apk --debug
```

Wrong-signer/repackaging and offline tests on a device/emulator remain manual controlled-test work. No device execution is claimed here. A repackaged APK can patch or remove the client verifier; tamper detection does not make modification impossible.

## Rollback

Revert the Layer 04 commit on `dev` if a regression is found. The verifier is non-blocking and adds no manifest permissions, network calls, backend dependency, or persistent state.

## Workflow and distribution boundaries (2026-11-15)

| Workflow | Trigger | APK outputs | Verification / retention | Publication |
| --- | --- | --- | --- | --- |
| `.github/workflows/muziinap-apk.yml` | Push to `main` or `dev`; manual dispatch | Universal release APK | `apksigner` verifies signer against the Actions keystore; APK artifact retention 14 days; encrypted Dart/R8/native symbols artifact retention 90 days | GitHub Actions artifacts only |
| `.github/workflows/release.yml` (verified on `main`) | Push to `main`; manual dispatch; no tag trigger | Universal, armeabi-v7a, arm64-v8a, x86_64 APKs | Signature verification for each APK; SHA-256 checksum manifest; encrypted Dart/R8 symbols artifact retention 90 days | GitHub Actions artifacts only; no GitHub Release creation/upload step |

Both workflows restore signing material from GitHub Actions Secrets. The release workflow's `permissions` are `contents: read`. Its package job creates and verifies checksums before uploading the build-assets artifact. This build pipeline is distinct from the owner-operated Telegram APK distribution. A successful build or artifact upload does not establish that a public APK was posted to Telegram.

## Current toolchain

- Flutter action: `3.47.5`; Flutter git submodule commit: `84abdf7372654171e0a66174be2846f53331f6ab`.
- Java: 17; Android Gradle Plugin: 8.11.1; Gradle wrapper: 8.14.2; Kotlin: 2.2.20; Android NDK: 28.2.13676358.
- Dart SDK constraint: `>=3.11.0 <4.0.0`.
- Current configured production app version: `1.0.0+2` (`versionName` `1.0.0`, Android `versionCode` `2`). The `release.yml` workflow derives artifact filenames and checksum names from this version. APK publication to Telegram remains a separate owner-operated step.
