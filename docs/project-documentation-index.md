# MuziiNap Documentation Index and Maintenance Scope

**Repository:** `squiraldot/MuziiNap`  
**Branch:** `dev`  
**Snapshot:** 14 November 2026

This index inventories the repository's human-readable documentation and records its maintenance treatment. Source configuration is authoritative for SDK/toolchain versions, workflow behavior, package identity, and implementation status.

## Maintained project documentation

| File | Purpose | Maintenance treatment |
| --- | --- | --- |
| `README.md` | Public project overview, features, setup, workflows, troubleshooting | Keep aligned with supported app behavior and developer workflow |
| `.github/copilot-instructions.md` | Detailed AI/contributor engineering instructions | Keep aligned with source, CI, and branch policy |
| `memory-agent.md` | Concise project memory for coding agents | Keep synchronized with detailed instructions |
| `CHANGELOG.md` | Release-facing change history | Add new work under Unreleased; preserve historical entries |
| `docs/maintenance-branch-policy.md` | Official branch roles and automation policy | Update when branch/release policy changes |
| `docs/song-sharing-url-contract.md` | Canonical song URL and Android App Links contract | Update with source/contract changes and new verification evidence |
| `fastlane/metadata/android/en-US/title.txt` | Store listing title | Change only when the approved product title changes |
| `fastlane/metadata/android/en-US/short_description.txt` | Store listing short description | Keep within store limits and aligned with product |
| `fastlane/metadata/android/en-US/full_description.txt` | Store listing feature description | Keep claims supportable by current app behavior |

## Historical and legal records

- `fastlane/metadata/android/changelogs/*.txt` are version-specific release notes. Preserve them as historical records; do not rewrite them to describe current branch state.
- `LICENSE` is the repository's authoritative license text. Do not edit it as routine documentation maintenance.
- `packages/just_audio/LICENSE` is the local dependency fork's license notice. Preserve it with the fork.
- Store title metadata remains unchanged while the product name remains MuziiNap.

## Source-of-truth references

| Fact | Source of truth |
| --- | --- |
| Dart package, SDK constraint, app version, dependencies | `pubspec.yaml` |
| Android namespace/application ID, NDK/build configuration | `android/app/build.gradle` and Android Gradle files |
| Android app links and intent filters | `android/app/src/main/AndroidManifest.xml` |
| Native channels and intent delivery | `android/app/src/main/kotlin/com/merrmist/muziinapmusic/MainActivity.kt` |
| CI/release triggers and toolchains | `.github/workflows/*.yml` |
| Current app behavior and feature wiring | `lib/`, `android/`, and `test/` |
| Song sharing URL rules | `docs/song-sharing-url-contract.md` plus matching source/tests |
| Branch policy | `docs/maintenance-branch-policy.md` |

## Current audited facts

- Official maintenance branch: `dev`; GitHub default branch remains `main`.
- Dart SDK constraint: `>=3.11.0 <4.0.0`.
- CI Flutter: `3.47.5`; Java: `17`; Android NDK: `27.0.12077973`.
- Android application ID: `com.merrmist.muziinapmusic`.
- Deferred deep linking is not implemented and is outside accepted Android Phase 08 scope.
- Website source/deployment is separate and is not verified by this Android repository documentation update.
