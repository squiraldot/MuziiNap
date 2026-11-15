## Unreleased

> First production release target: **MuziiNap v1.0.0**. This is a preparation target, not a published release. The current `pubspec.yaml` version remains `1.0.0-beta.1+1` until a separately authorized release change.

### Android release build security

- Added official Dart AOT obfuscation to Android release APK build paths, with per-build symbol generation, encrypted CI retention, and crash-symbolication documentation.

### Documentation and maintenance

- Standardized repository guidance around `dev` as the official maintenance/development branch and `main` as the release/integration branch.
- Synchronized project references with the current Dart SDK constraint, Android-only target, CI toolchain, and workflow triggers.
- Updated Android song-sharing acceptance evidence to the latest audited `dev` commit and verified CI runs.
- Clarified that deferred deep linking is not implemented and remains outside the accepted Android Phase 08 scope.
