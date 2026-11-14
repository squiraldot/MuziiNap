# Layer 02 — Android R8 / ProGuard hardening

## Build configuration

The Android application uses Android Gradle Plugin 8.11.1, Gradle 8.14.2, and Kotlin 2.2.20. Release builds enable R8 minification/optimization with AGP's `proguard-android-optimize.txt` defaults and resource shrinking. Debug builds are unchanged.

The application ID and existing release-signing configuration are unchanged. Local builds retain the pre-existing debug-signing fallback when release credentials are absent; release CI continues to require the release keystore secrets.

## Targeted keep rules

`android/app/proguard-rules.pro` keeps only Android-instantiated application components, Flutter's configured multidex Application, audio_service's manifest-declared service/receiver, and application classes/members resolved by JNIGen through literal JVM names.

- `MainActivity`, `BgUtilsPotService`, and `LyricsHomeWidgetProvider`: Android manifest entry points.
- `AudioService` and `MediaButtonReceiver`: audio_service manifest entry points.
- `Equalizer`, `SDKInt`, and `SDKInt$Companion`: JNIGen class/member lookups.
- Flutter MethodChannel/EventChannel handlers and the just_audio plugin are directly reachable through registered code; no blanket package keep rule is added.
- Native PCM DSP controller calls are direct JVM references in the host activity and processor, so they are not protected by a broad keep rule.

R8 warnings are not suppressed. Any missing-class warning must be investigated against the actual dependency graph before adding a targeted rule.

## Mapping file handling

Each release workflow captures the R8 mapping immediately after each Gradle release build. The mapping is copied under the unique Dart symbol directory:

`build/obfuscation-symbols/<commit>/<app-version>/<run-id>-<attempt>/r8/<variant>/mapping.txt`

The existing symbol packaging script now requires both non-empty Dart AOT symbols and at least one non-empty R8 mapping. It archives the build manifest, all Dart symbols, and all variant mappings, encrypts the archive with AES-256 using the existing Actions secret `SYMBOLS_ENCRYPTION_KEY`, decrypts it in CI to verify integrity, and uploads only the encrypted `.gpg` artifact. Artifact names include commit SHA, workflow run ID, and run attempt; mappings from earlier builds are never overwritten. The encrypted artifact is retained for 90 days by the APK workflow. Repository artifact access is still governed by GitHub repository permissions; encryption protects mapping contents from casual artifact access.

Do not upload plaintext `mapping.txt` files or commit them to the repository.

## Crash deobfuscation

1. Download the encrypted symbols/mapping artifact matching the exact APK's commit SHA and workflow run ID/attempt.
2. Obtain the same `SYMBOLS_ENCRYPTION_KEY` secret through the repository's approved private secret-sharing process.
3. Decrypt and extract the archive:

```bash
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
  --decrypt --output muziinap-symbols.tar.gz muziinap-symbols-<commit>-<version>-<run-id>-<attempt>.tar.gz.gpg
tar -xzf muziinap-symbols.tar.gz
```

For Android Java/Kotlin stack traces, run Retrace with the matching variant mapping:

```bash
$ANDROID_HOME/cmdline-tools/latest/bin/retrace <path-to-r8-mapping.txt> <stacktrace.txt>
```

If using a standalone R8 distribution, use its matching `retrace` executable with the same arguments. Never use a mapping from a different commit, app version, variant, or workflow attempt.

For Dart AOT stack traces, use the matching `.symbols` file with the Flutter `flutter symbolize` command.

## Missing classes and runtime troubleshooting

- Keep the original R8 warning output in CI logs; do not add `-dontwarn` as a shortcut.
- Identify which dependency references the missing type, verify whether it is an optional API or a missing dependency, then fix the dependency or add a narrowly scoped rule only when runtime evidence requires it.
- If a runtime component fails after minification, inspect the merged manifest, R8 usage report, mapping file, and stack trace before changing keep rules.
- Verify startup, audio_service notifications, media buttons, widgets, BgUtils service startup, JNI equalizer calls, deep links, sharing, and queue/background playback on supported Android devices.

## Rollback

To disable this layer temporarily, revert only the release build-type R8 settings and this layer's ProGuard file from the Layer 02 commit. Do not alter application ID, signing, Dart obfuscation flags, generated code, native DSP, or release artifact naming. Preserve already-created encrypted mapping archives for crash diagnosis of builds produced while R8 was enabled.

## Verification boundary

CI builds and APK signature checks provide build-time evidence only. Physical-device checks for playback, notifications, widgets, JNI, deep links, and BgUtils are still required before declaring full runtime regression coverage.
