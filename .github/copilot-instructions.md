# AI Coding Instructions — MuziiNap

These instructions describe the current repository configuration. If documentation conflicts with source, pubspec.yaml, Android Gradle files, or active GitHub Actions workflows, verify the source of truth and update this document instead of guessing.

## Project identity and target

- Repository: squiraldot/MuziiNap
- Current work branch: feature/advanced-equalizer
- App: MuziiNap, an Android-only Flutter music app
- Dart package name: muziinap
- Android namespace and application ID: com.merrmist.muziinapmusic
- Dart SDK constraint: >=3.1.5 <4.0.0
- CI Flutter version: 3.47.5
- Java: 17
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

1. Work only on feature/advanced-equalizer for the current work. Do not switch to or modify main, and do not create a new branch.
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
- .github/workflows/release.yml: release-signed universal and ABI APKs, checksum verification, and tag-triggered GitHub Release publishing

The workflows currently use Flutter 3.47.5 and Java 17. The release workflow expects configured Android signing secrets. Do not infer successful CI from a commit being pushed; inspect the latest run for the exact commit SHA.

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

## Useful references

- [Flutter](https://docs.flutter.dev/)
- [GetX](https://pub.dev/packages/get)
- [Hive](https://docs.hivedb.dev/)
- See README.md for user-facing capabilities and download instructions.
