# MuziiNap Documentation Synchronization Audit

**Date:** 2026-11-15  
**Repository:** `squiraldot/MuziiNap`  
**Documentation target:** `dev` only  
**Baseline commit:** `e643c8522924f01d633ad0a50ad61a1e52cb05ea`  
**First production release target:** `v1.0.0` (not yet published)

## Branch verification

GitHub reported both `dev` and `main` at `e643c8522924f01d633ad0a50ad61a1e52cb05ea`, latest commit `fix: correct album model imports for CI tests` (2026-11-14). A direct compare returned `identical`, ahead 0, behind 0, and no differing paths. Main workflow files were still fetched independently using `ref=main`.

The environment could not clone the repository locally because DNS resolution for github.com failed; therefore no local shell checkout was possible. Repository reads and writes are instead explicitly scoped to the existing `dev` ref. The final branch update uses the expected original HEAD as a lease. No branch is created and `main` is not written.

## Complete Markdown inventory and disposition

The initial recursive Git-tree scan found **13** Markdown files. All 13 were individually fetched and reviewed. This report adds one new Markdown file, making the final inventory **14**.

| File | Final classification | Review focus |
| --- | --- | --- |
| `.github/copilot-instructions.md` | Updated | Contributor rules, toolchain, branch/workflow and distribution policy |
| `CHANGELOG.md` | Updated | v1.0.0 marked as an unpublished target; existing history retained |
| `README.md` | Updated | Features, version state, Telegram download, update checker and workflows |
| `docs/apk-integrity.md` | Updated | Signer verification, local trust boundary, workflows and APK destination |
| `docs/backend-security-layer-05.md` | Updated | CredentialVault, secret handling and device-test evidence boundaries |
| `docs/dart-aot-obfuscation.md` | Updated | AOT/R8 symbols, encryption, retention and workflow scope |
| `docs/maintenance-branch-policy.md` | Updated | Branch roles and exact workflow triggers |
| `docs/project-documentation-index.md` | Updated | Full inventory, sources of truth and architecture status |
| `docs/security/FINAL-SECURITY-AUDIT-2026-11-14.md` | Historical — preserved intentionally | Original audit preserved; dated 2026-11-15 addendum appended |
| `docs/security/LAYER-02-R8.md` | Updated | R8 configuration and current toolchain |
| `docs/security/LAYER-03-NATIVE.md` | Updated | NDK, native symbols and device-test boundaries |
| `docs/song-sharing-url-contract.md` | Updated | Historical Phase 08 evidence preserved; current source and QA clarified |
| `memory-agent.md` | Updated | Current toolchain, persistence, workflows and distribution |
| `docs/documentation-audit-2026-11-15.md` | Updated — newly created | This inventory and audit report |

**Totals:** 13/13 pre-existing Markdown files inspected; 12 existing documents updated; 1 historical document preserved with a dated addendum; 0 verified-without-change; 1 new audit report. Final inventory: 14/14 classified.

## Source/configuration facts verified

- Dart package: `muziinap`; configured version: `1.0.0-beta.1+1`; SDK constraint: `>=3.11.0 <4.0.0`.
- First production target: `v1.0.0`, not yet published. No version configuration was changed.
- Flutter CI action: 3.47.5; Flutter submodule gitlink: `84abdf7372654171e0a66174be2846f53331f6ab`.
- Java 17; AGP 8.11.1; Gradle wrapper 8.14.2; Kotlin 2.2.20; Android NDK 28.2.13676358.
- Android namespace/application ID: `com.merrmist.muziinapmusic`.
- Relevant dependencies include GetX, just_audio (local path override), audio_service, Hive/Hive Flutter, Isar Community, flutter_secure_storage, Dio, jni and youtube_explode_dart. Resolved versions are recorded in `pubspec.lock`; dependency files were not changed.
- Flutter submodule URL is https://github.com/flutter/flutter.git, pinned by the gitlink above.
- Old documentation's NDK `27.0.12077973` reference was stale and corrected.

## Main release workflow audit

The actual `.github/workflows/release.yml` was independently fetched from `main`. It is named **Android Build & Package**.

- Triggers: push to `main`; manual `workflow_dispatch`. No version-tag trigger.
- Runner: `ubuntu-latest`; permissions: `contents: read`.
- Java: Zulu 17. Flutter: stable 3.47.5.
- Signing: restore keystore/password/alias from Actions Secrets, validate alias, derive SHA-256 certificate fingerprint.
- Builds: obfuscated universal APK plus split APKs for armeabi-v7a, arm64-v8a and x86_64.
- Dart AOT: `--release --obfuscate --split-debug-info` with a unique commit/version/run/attempt directory.
- R8: preserve universal and split-build `mapping.txt`.
- Symbols: packaging script requires non-empty Dart symbols and R8 mappings, encrypts using GnuPG AES-256 and `SYMBOLS_ENCRYPTION_KEY`, decrypts in CI to verify integrity, then uploads encrypted symbols with 90-day retention.
- APK checks: all four outputs must exist; `apksigner` verifies each and compares signer fingerprint with the restored keystore; embedded Dart symbols are rejected.
- Packaging: renames APKs, generates SHA-256 checksums and verifies them with `sha256sum -c`.
- Artifacts: `android-builds`, encrypted `muziinap-obfuscated-symbols-...`, and `android-release-assets`.
- **GitHub Release publishing is not implemented** in this workflow. It creates Actions artifacts only.
- Although Gradle requests FULL native debug symbols, this workflow has no explicit native-symbol capture/verification step. That step exists in `muziinap-apk.yml`.

The separate `muziinap-apk.yml` runs on `main`/`dev` pushes or manual dispatch. It builds one signed universal APK, verifies its signature, captures Dart/R8/native debug symbols, encrypts the symbol bundle, and uploads the APK (14-day retention) and encrypted symbols (90-day retention). `code_quality.yml` runs on both branch pushes or manual dispatch and performs Android debug compilation, Isar generation, Kotlin DSP unit tests, analyzer and Flutter tests.

## APK distribution and update checker

Source `lib/services/update_checker.dart` confirms:

- API endpoint: `https://api.github.com/repos/squiraldot/MuziiNap-Official/releases`.
- Reads GitHub release `tag_name`, `draft`, `prerelease`, and `body`.
- Skips draft/prerelease releases, invalid semantic versions and prerelease tags; selects the highest stable semantic version.
- Gets installed version from `PackageInfo.fromPlatform()`; prompts only if the latest stable version is newer.
- Displays release-body notes.
- Uses a 7-second HTTP timeout; non-200 and malformed JSON are errors. Startup catches/logs failures without blocking app startup; concurrent checks are coalesced.
- Startup check runs once per app process after Home mounts when the compile-time `updateCheckFlag` is enabled. The checked-in `lib/utils/update_check_flag_file.dart` defaults to `false`; both `muziinap-apk.yml` and `release.yml` replace it with `true` in the CI build workspace. The Download action opens `https://telegram.me/muziinap/3` externally.
- No automatic GitHub APK asset download, in-app APK installation, or OTA update is implemented.

The Telegram channel is the official APK distribution destination. MuziiNap-Official is the version/release metadata source, not APK hosting.

## Architecture and implementation status

- **Playback:** app-scoped AudioService `MyAudioHandler` owns just_audio. `AudioPlaybackService` configures AudioSession focus/interruption behavior.
- **Streams:** InnerTube is primary; external extractors are sequential fallbacks. Device profile uses Android API, low-RAM status and network type to choose Opus/AAC preference and buffer policy. Decoder/renderer failures can retry with AAC.
- **Recovery/queue/cache:** playback circuit breaker monitors frozen buffering/loading states with a per-track retry budget. AudioHandler owns queue transitions, next-item stream prefetch and playback recovery. Cache trimming is bounded to 100 MiB and protects current/queued songs.
- **Persistence:** Hive remains active for preferences, library and cache/download metadata. Isar Community schemas/service exist but are lazy; Hive-to-Isar migration is not complete.
- **Credentials:** CredentialVault uses flutter_secure_storage for YouTube/Piped secrets and retains sanitized metadata in Hive. This is at-rest client storage, not server authorization.
- **Android:** Kotlin/JVM DSP/equalizer and Android audio effects are present. No first-party C/C++ DSP source was found.
- **APK integrity:** local package/signer check is informational; mismatch logs and startup continues. CI signer verification is separate. No Play Integrity or first-party backend verification.
- **Deep links:** canonical song URL parsing and Android raw-intent bridge are implemented; deferred deep linking is not implemented.
- **Physical-device QA:** owner confirms functional testing, including playback, completed on real devices. This audit did not execute new device tests and does not invent device details.

## Security classification

| Area | Classification | Limitation |
| --- | --- | --- |
| Dart AOT obfuscation | Implemented in release workflows | Not source/assets encryption; reverse engineering remains possible |
| R8 minification/resource shrinking | Implemented for release build type | Runtime behavior still depends on keep rules and device coverage |
| APK signing / CI signer comparison | Implemented | Build-time identity check, not anti-repackaging enforcement |
| Runtime APK integrity | Implemented, informational | Mismatch is logged; startup continues; client code can be patched |
| CredentialVault / Keystore-backed storage | Implemented | At-rest protection; runtime compromise can expose in-use credentials |
| Native debug-symbol capture | Implemented in `muziinap-apk.yml` | Not equivalent to native compiler hardening; release workflow differs |
| First-party C/C++ hardening | Not applicable to first-party source found | JNI dependency native code is upstream-owned |
| Play Integrity / server-side attestation | Not implemented | No MuziiNap-owned backend |
| Exhaustive Git-history/artifact secret scan | Not verified in this audit | Workflow review is not a complete secret scan |

No complete-application-security claim is made.

## Device evidence boundaries

The owner explicitly confirms that real-device functional testing is complete and application features/playback work correctly. This is owner-confirmed evidence, not a new test run by this documentation task. No device model, Android version, test date or log is invented. Controlled repackaging, ELF/DWARF inspection, artifact-access tests, exhaustive secret scans and CredentialVault-specific migration edge cases remain separate unless supported by their own evidence.

## Cross-reference and external-link checks

The README and maintained docs now point APK downloads to Telegram and distinguish the MuziiNap-Official metadata repository. Relative references in the index point to existing repository paths. Website implementation/deployment and external-site availability were not independently tested; the website is maintained separately.

## Change isolation gate

Only `.md`, `.mdx`, and `.markdown` paths are allowed in the final diff. Source, dependency/lockfile, workflow, YAML/JSON, Gradle, Kotlin, Java, XML, localization, test, submodule and other non-Markdown paths must remain untouched. All documentation writes target the existing `dev` ref. No merge, cherry-pick, rebase, new branch, tag, APK upload, GitHub Release or v1.0.0 publication is part of this task.
