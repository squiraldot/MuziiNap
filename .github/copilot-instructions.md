# AI Coding Instructions — MuziiNap

These instructions describe the current repository configuration. If documentation conflicts with source, pubspec.yaml, Android Gradle files, or active GitHub Actions workflows, verify the source of truth and update this document instead of guessing.

## Repository and branch policy

- Repository: squiraldot/MuziiNap
- **Official maintenance and day-to-day development branch: `dev`**
- `main` is the release/integration branch. Routine maintenance belongs on `dev`; promote reviewed release-ready changes to `main` through the agreed release process.
- GitHub's current default branch remains `main`; this is separate from the maintenance-branch policy.
- Do not create, rename, delete, or force-move branches unless explicitly authorized.

## Project identity and target
- App: MuziiNap, an Android-only Flutter music app
- Dart package name: muziinap
- Android namespace and application ID: com.merrmist.muziinapmusic
- Dart SDK constraint: >=3.11.0 <4.0.0
- Current source version: `1.0.0-beta.1+1` (`pubspec.yaml`); first production target: `v1.0.0`, not yet published.
- CI Flutter version: 3.47.5 (Flutter submodule gitlink: `84abdf7372654171e0a66174be2846f53331f6ab`)
- Java: 17; Gradle: 8.14.2; Android Gradle Plugin: 8.11.1; Kotlin: 2.2.20; Android NDK: 28.2.13676358
- Keep the Android application ID, namespace, signing identity expectations, and persisted-data compatibility stable unless explicitly authorized.

## Stack and architecture

- Flutter / Dart; GetX for state and dependency injection
- just_audio + audio_service for playback, background audio, and media controls
- Hive / Hive Flutter for local storage and cache
- Dio, HTTP, and YouTube-related services for networking and stream resolution
- Kotlin and JNI/JNIGen for configured native Android integrations
- flutter_zxing and camera for QR scanning
- Localization sources live in localization/; generator: dart localization/generator.dart
- Icons/fallback assets are under assets/icons/

Key areas:
- lib/services/: audio, stream resolution, downloads, equalizer, networking, persistence, and related services
- lib/ui/player/: player UI and controllers
- lib/ui/screens/: home, library, search, settings, and other screens
- lib/native_bindings/ and android/: native integration and Android configuration
- test/: unit and widget tests

Follow existing patterns and inspect actual call sites before changing architecture.

## Platform policy

- The maintained product and CI/release target are Android only.
- Do not add or restore iOS, web, Windows, Linux, or macOS runners, workflows, packaging, or platform-specific dependencies without an explicit project decision.
- Shared Flutter layout code, responsive breakpoints, and hardware-keyboard support may still be useful on Android tablets/foldables or with external keyboards. Do not remove these simply because they resemble desktop support.
- Do not remove a dependency merely because upstream supports other platforms; first verify imports, plugins, assets, native setup, and runtime use.

## Non-negotiable compatibility and safety rules

1. Keep routine maintenance and development on `dev`; do not use `main` for ordinary maintenance.
2. Never change the Android application ID or namespace casually; existing installations and release updates depend on stable identifiers.
3. Preserve legacy Hive preference keys, saved-data schemas, equalizer preset formats, and author aliases when changing user-facing branding. These are compatibility identifiers.
4. Do not modify YouTube account/login code unless a blocking issue requires it; explain the need and scope first.
5. Do not weaken, delete, or bypass tests to make CI pass.
6. Do not commit secrets, keystores, credentials, local properties, generated build outputs, or signing files.
7. Never create or replace release tags, publish releases, or change release signing configuration without explicit authorization.
8. Check references and runtime usage before deleting files, dependencies, assets, or configuration.
9. Do not claim a test, build, APK, device test, or workflow succeeded unless the relevant result was actually verified.

## Coding expectations

- Use idiomatic Dart and the configured flutter_lints rules.
- Keep state management consistent with existing GetX controllers and dependency-injection patterns.
- Preserve playback, stream resolution, queue behavior, background controls, downloads/cache, playlists, albums/artists, search, lyrics, Android Auto, QR scanning, equalizer, settings, and playback restoration.
- Keep Android permissions, manifest declarations, Gradle settings, Kotlin code, JNI bindings, and Dart callers aligned.
- Preserve Git-pinned dependency revisions unless there is a concrete need and compatibility is verified.
- Avoid broad refactors unrelated to the task.
- For stream-resolution changes, consider upstream failures, timeouts, cancellation, parallel request cleanup, and fallback ordering; do not let a slow source block a valid playable result.
- For equalizer/audio changes, consider audio-session lifecycle, track changes, background playback, persistence, clipping, and real-device behavior.
- Add or update focused tests for behavior changes and regression risks.
- Format changed Dart files with dart format.

## Current workflows

- .github/workflows/code_quality.yml: Flutter analysis and test suite
- .github/workflows/muziinap-apk.yml: Android APK build, analysis, and APK signature verification
- .github/workflows/release.yml: main-push/manual universal and ABI APK builds, signer verification, SHA-256 checksum generation, and GitHub Actions artifact upload; it does not publish a GitHub Release

The workflows use Flutter 3.47.5 and Java 17. Android Gradle Plugin 8.11.1, Gradle 8.14.2, Kotlin 2.2.20, and NDK 28.2.13676358 are configured. Release workflows expect configured Android signing secrets. Do not infer successful CI from a commit being pushed; inspect the latest run for the exact commit SHA.

## Suggested verification

Run what the environment supports:

~~~bash
flutter pub get
dart localization/generator.dart
dart format <changed-dart-files>
flutter analyze --no-fatal-infos lib test
flutter test --no-pub
flutter build apk --release
~~~

For release or native changes, additionally inspect CI APK-signature verification and test on a real Android device when available. Report unavailable tooling or device testing explicitly.

## Git and handoff

- Keep changes scoped and commits understandable.
- Review git diff and git status before handoff.
- Do not merge into main or open/merge a PR unless explicitly asked.
- The optional git-sync.sh helper stages all local changes and can offer to replace an existing remote tag. Inspect its prompts carefully; do not run it blindly.
- Update README.md and CHANGELOG.md when user-facing features or release-relevant behavior changes.
- Release preparation must keep pubspec.yaml, changelog, in-app version information, and the tag consistent.

## Song sharing and Android App Links

The Android canonical song URL contract is documented in `docs/song-sharing-url-contract.md`.

- Canonical URL: `https://muziinap-site.vercel.app/song/VIDEO_ID`.
- The exact, case-sensitive 11-character YouTube video ID is the song identity.
- URL generation/parsing: `lib/utils/song_sharing_config.dart`; share/copy/QR generation: `lib/services/song_sharing_service.dart`.
- Native raw-intent bridge: `MainActivity.kt`, channel `muziinap/raw_deep_links`; Dart event handling: `lib/services/deep_link_service.dart`.
- Playback coordination: `lib/services/song_link_playback_coordinator.dart`; queue policy: `lib/services/song_link_playback_policy.dart` and `PlayerController.playSharedSong`.
- Preserve legacy YouTube imports and preset-file sharing.
- Deferred deep linking is not implemented and is outside the accepted Android Phase 08 scope.
- Website source/deployment is maintained separately; do not claim it was audited when only this repository was inspected.

## Current workflows and toolchain

- Flutter `3.47.5`, Java `17`, Android NDK `28.2.13676358`.
- `code_quality.yml`: push validation for `main` and `dev`, plus manual dispatch; Flutter/Android debug build, Isar code generation, native DSP unit tests, analyzer and Flutter tests.
- `muziinap-apk.yml`: `main`/`dev` push or manual; signed universal release APK, signature verification, Dart/R8/native symbol capture, encrypted symbol artifact, and APK Actions artifact.
- `release.yml` (inspected on `main`): `main` push or manual dispatch only; signed universal and split-ABI APKs, Dart/R8 symbol encryption, signature checks, SHA-256 checksums, and Actions artifact upload. No tag trigger and no GitHub Release publishing step.

The exact workflow run for the exact commit must be checked before reporting success. CI does not prove physical-device behavior.

## Git and documentation policy

- Keep README, CHANGELOG, this file, and `memory-agent.md` aligned with source configuration.
- Keep historical release notes and license texts unchanged; update only new work under Unreleased.
- `main` remains the GitHub default branch unless repository settings are explicitly changed; documenting `dev` as maintenance does not change that setting.

## Useful references

- [Flutter](https://docs.flutter.dev/)
- [GetX](https://pub.dev/packages/get)
- [Hive](https://docs.hivedb.dev/)
- See README.md for user-facing capabilities and download instructions.

## Production download and update contract

- APK distribution is through the official Telegram channel: https://telegram.me/muziinap/3. Do not describe GitHub Releases as the APK download host.
- In-app version metadata is fetched from `https://api.github.com/repos/squiraldot/MuziiNap-Official/releases`; the checker filters drafts/prereleases, compares semantic versions, displays the release body, and opens the Telegram URL externally. The checked-in startup flag defaults to false; both APK build workflows set it true in the build workspace.
- GitHub Releases in MuziiNap-Official are metadata, not APK assets. The checker does not download a GitHub asset, install an APK, or perform OTA updates.
- The upcoming first production release target is v1.0.0; do not claim publication before a real release exists.
