# MuziiNap Documentation Index and Audit Inventory

**Repository:** `squiraldot/MuziiNap`  
**Documentation branch:** `dev`  
**Current source snapshot:** 15 November 2026 — `e643c8522924f01d633ad0a50ad61a1e52cb05ea`  
**Configured production release version:** `v1.0.0`

This index is the complete Markdown inventory for the current source snapshot. Every `.md`, `.mdx`, and `.markdown` file was enumerated recursively from the `dev` Git tree and inspected individually. The current inventory contains 13 pre-existing Markdown files; this synchronization adds the audit report, bringing the final inventory to 14.

## Complete Markdown inventory

| Markdown file | Purpose | Final classification |
| --- | --- | --- |
| `.github/copilot-instructions.md` | Contributor/AI engineering instructions, branch policy, source paths and workflow rules | Updated |
| `CHANGELOG.md` | Release-facing change history; historical entries retained | Updated |
| `README.md` | Public project overview, capabilities, setup, distribution and troubleshooting | Updated |
| `docs/apk-integrity.md` | Local signer identity check, CI signing verification and trust boundaries | Updated |
| `docs/backend-security-layer-05.md` | CredentialVault, secure storage, public configuration, secret handling and backend limits | Updated |
| `docs/dart-aot-obfuscation.md` | Dart AOT symbol generation, encryption, retention and crash symbolication | Updated |
| `docs/maintenance-branch-policy.md` | Branch roles, workflow triggers and maintenance policy | Updated |
| `docs/project-documentation-index.md` | Complete documentation inventory and source-of-truth map | Updated |
| `docs/security/FINAL-SECURITY-AUDIT-2026-11-14.md` | Historical five-layer security audit and subsequent dated clarification | Historical — preserved intentionally |
| `docs/security/LAYER-02-R8.md` | R8/ProGuard release configuration and mapping recovery | Updated |
| `docs/security/LAYER-03-NATIVE.md` | Native dependency boundary and AGP debug-symbol handling | Updated |
| `docs/song-sharing-url-contract.md` | Canonical song URL, Android App Links and acceptance evidence | Updated |
| `memory-agent.md` | Concise project memory for coding agents | Updated |
| `docs/documentation-audit-2026-11-15.md` | This synchronization's inventory, evidence, corrections and verification | Updated — newly created |

No Markdown file from the initial inventory was skipped. The historical security report is preserved rather than rewritten as a current audit.

## Source-of-truth hierarchy

| Subject | Authoritative source |
| --- | --- |
| Package name, configured version, Dart SDK constraint, dependencies and overrides | `pubspec.yaml` and `pubspec.lock` |
| Flutter submodule URL and pinned commit | `.gitmodules` and the `flutter` gitlink |
| Android namespace/application ID, NDK, Java/Kotlin targets, signing fallback, R8 and native symbol level | `android/app/build.gradle`, `android/settings.gradle`, Gradle wrapper |
| Actual CI/release triggers, toolchain setup, build variants, permissions and artifacts | Workflow YAML files; `release.yml` is inspected on `main` |
| Current app behavior | Dart/Kotlin source under `lib/` and `android/`, plus tests |
| Update metadata endpoint and APK destination | `lib/services/update_checker.dart` |
| Song URL and Android intent contract | `docs/song-sharing-url-contract.md` plus source and tests |
| Branch roles | This index and `docs/maintenance-branch-policy.md`; GitHub currently defaults to `main` |

## Branch and workflow policy

- `dev` is the documentation and routine maintenance branch.
- `main` is the release/integration branch and remains GitHub's default branch.
- At the inspected snapshot, both branches point to the same commit. Their equality was verified, not assumed.
- `code_quality.yml` and `muziinap-apk.yml` run on pushes to `main` and `dev`, and on manual dispatch.
- `release.yml` runs on `main` pushes and manual dispatch only. It has no tag trigger and does not run automatically on `dev` pushes.
- The `release.yml` workflow uploads GitHub Actions artifacts; it does not create or publish a GitHub Release.
- Documentation-only updates in this task are committed to `dev` only. Do not merge, cherry-pick, rebase, or write to `main`.

## Current toolchain and release state

- Current `pubspec.yaml` version: `1.0.0+2`; Android `versionName`: `1.0.0`; Android `versionCode`: `2`. This is the configured production release version.
- Dart SDK constraint: `>=3.11.0 <4.0.0`.
- Flutter CI action: `3.47.5`; Flutter submodule gitlink: `84abdf7372654171e0a66174be2846f53331f6ab`.
- Java 17; Android Gradle Plugin 8.11.1; Gradle 8.14.2; Kotlin 2.2.20; Android NDK 28.2.13676358.
- Android namespace/application ID: `com.merrmist.muziinapmusic`.
- APK distribution: official Telegram channel, https://telegram.me/muziinap/3.
- Update checker: reads stable release metadata from the MuziiNap-Official GitHub Releases API, displays notes, and opens Telegram. The checked-in compile-time startup flag defaults to false; both APK workflows set it true in their build workspace. No APK auto-download or auto-install.
- Version metadata: GitHub Releases API for the separate `squiraldot/MuziiNap-Official` repository. This is not APK hosting.
- Owner-confirmed physical-device functional testing, including playback, is complete. This documentation audit did not execute a new device test.

## Feature/architecture status notes

- Playback is owned by the app-scoped `MyAudioHandler` (AudioService + just_audio), with a shared AudioSession policy, device-adaptive stream profile, network stream recovery/circuit breaker, queue prefetching and bounded cache trimming.
- Stream resolution uses InnerTube as primary extractor with sequential external fallback providers; adaptive codec selection prefers Opus only on supported Android API/device/network profiles and retains AAC fallback.
- Hive remains the active persistence owner for preferences, library and cache-related data. Isar has schema/service scaffolding and is initialized lazily; the Hive-to-Isar migration is not complete.
- CredentialVault uses flutter_secure_storage for account/session secrets; Hive retains non-secret display/endpoint metadata. This is local at-rest protection, not server-side authorization.
- APK integrity is a local package/signing identity signal. A mismatch is logged; startup continues. No Play Integrity integration or MuziiNap-owned backend verification exists.
- Android DSP/equalizer implementation is Kotlin/JVM with Android audio effects; no first-party C/C++ DSP source is present.
- Deferred deep linking is not implemented. Website implementation/deployment is outside this Android repository audit.

## Historical and non-Markdown records

- Preserve `LICENSE`, generated localization files, fastlane text metadata and version-specific text changelogs as their own artifacts; they are not Markdown files and are not part of this Markdown inventory.
- Historical audit and acceptance evidence must retain its original date, commit and scope. Add dated status notes rather than rewriting history.
- No Markdown inventory claim should be inferred from this index alone; re-run a recursive tree inventory when the repository tree changes.

## Ownership and maintenance

- Repository owner/maintainers own release signing secrets, Telegram APK publication, official update metadata and physical-device QA evidence.
- Contributors maintain source-aligned docs on `dev`; release workflow changes require separate explicit authorization.
- Before documenting CI success, inspect the workflow run for the exact commit. CI is not a substitute for physical-device evidence.
- Update this index whenever a Markdown file is added, moved or removed. Keep relative links valid and preserve historical records.

## Production versioning policy

- Flutter package version: `1.0.0+2`.
- Android user-visible `versionName`: `1.0.0`.
- Android monotonically increasing `versionCode`: `2`, greater than the prior beta build code `1` so Android can update an existing beta installation when the signing identity matches.
- Flutter Gradle integration derives the Android version values from the package version during Flutter builds. The explicit `android/app/build.gradle` fallback values are also aligned to `versionName 1.0.0` and `versionCode 2`.
- Do not include the build suffix `+2` in user-facing release labels or APK release version names; use `v1.0.0`.
