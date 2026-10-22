<div align="center">

# MuziiNap
### Android music streaming, playback, and custom audio controls

An Android-only Flutter music app created and maintained by SquiralDot.

[Download latest APK](https://github.com/squiraldot/MuziiNap/releases/latest) · [Report a bug](https://github.com/squiraldot/MuziiNap/issues) · [View source](https://github.com/squiraldot/MuziiNap)

</div>

## Overview

MuziiNap is an Android music player and streaming client built with Flutter. It integrates with YouTube/YouTube Music and supporting community services. Core playback, library, and settings do not require a MuziiNap account.

> Availability of streams, lyrics, and third-party services depends on those services and their policies. Use the app lawfully and respect content owners and local law.

## Features

- Search and play music from supported YouTube/YouTube Music endpoints
- Background playback, notification/media controls, queue management, and playback restoration
- Song caching, downloads, and offline playback where cached/downloaded files are available
- Playlists, favourites, bookmarks, album and artist library views
- Import supported song, playlist, album, and artist links through Android sharing/deep links
- Streaming quality controls and stream-source fallback
- Custom equalizer support and Android audio integration
- Synced/plain lyrics, lyrics reload, and live lyrics translation
- Radio, sleep timer, skip silence, and dynamic artwork-based theming
- Android Auto support
- QR-code generation/sharing and scanning
- Configurable navigation, player gestures, double-tap seeking, and dedicated ±10-second controls
- Localization and settings for playback and app behavior
- GitHub version/update notification support in distributed builds

Feature availability may vary by Android version, device audio stack, network, and upstream service changes.

## Platform and technology

**Supported target: Android.** Shared Flutter layout code or dependencies with broader upstream support do not change the maintained app/build target.

- Flutter / Dart
- GetX for state management and dependency injection
- just_audio and audio_service for playback and background media controls
- Hive for local persistence and caching
- Dio and YouTube-related service integrations for networking/stream resolution
- Kotlin, JNI/JNIGen, and Android-native integrations where configured
- flutter_zxing and camera for QR/barcode scanning

The Dart package name is **muziinap**. The Android namespace/application ID is **com.merrmist.muziinapmusic**. These identifiers are compatibility-sensitive and must not be changed casually.

## Download and update

Download the latest published Android APK from the [GitHub Releases page](https://github.com/squiraldot/MuziiNap/releases/latest). For in-place updates, install builds signed with the same release signing identity. Do not uninstall an existing installation unless you understand the effect on local app data.

Release builds and checksums are published through the repository's tag-triggered release workflow. Branch CI artifacts are validation builds, not necessarily published releases.

## Development

Use the Flutter version configured by GitHub Actions (currently **3.47.5**) and Java 17.

~~~bash
flutter pub get
dart localization/generator.dart
flutter analyze --no-fatal-infos lib test
flutter test --no-pub
flutter build apk --release
~~~

For release-equivalent signing checks, use CI and its configured Android signing secrets. Never commit keystores, passwords, signing files, generated build output, or other secrets.

### GitHub Actions

- .github/workflows/code_quality.yml — analyzer and Flutter tests
- .github/workflows/muziinap-apk.yml — Android APK build, analysis, and signature verification
- .github/workflows/release.yml — Android APK variants, checksum verification, and tag-triggered GitHub Release publication

Check the actual workflow run for the commit being evaluated before describing CI as passing. A successful CI run does not replace real-device testing.

## Troubleshooting

- If background playback or notification controls stop working, check Android battery/background restrictions and notification permissions for your device.
- Stream availability and startup time depend on network conditions and third-party endpoints; a source may become unavailable without an app release.
- If an update cannot install over an existing copy, verify that the APK came from the expected distribution channel and uses the same signing identity.

## Privacy and third-party services

MuziiNap does not require a MuziiNap account for core use. Network features may contact YouTube/YouTube Music, Piped instances, LRCLIB, GitHub, translation services, and other configured endpoints. Their availability, data handling, and terms are controlled by those providers. Review their policies before use.

## License and notices

Check the repository's LICENSE file for the authoritative license text and conditions.

MuziiNap is an independent community project and is not sponsored, affiliated with, or endorsed by YouTube, Google, or other content providers. Content, songs, trademarks, and artwork belong to their respective owners. The software is provided as-is, without warranty; see the repository license and applicable law for details.

## Credits

- [Flutter](https://docs.flutter.dev/) and the Flutter ecosystem
- [GetX](https://pub.dev/packages/get)
- [just_audio](https://pub.dev/packages/just_audio) and [audio_service](https://pub.dev/packages/audio_service)
- [YouTube Music API project by sigma67](https://github.com/sigma67)
- [ViMusic](https://github.com/vfsfitvnm) for UI inspiration
- [LRCLIB](https://lrclib.net) for synced lyrics
- [Piped](https://piped.video) for supported playlist/service integration
- All upstream maintainers and contributors whose work this project builds upon
