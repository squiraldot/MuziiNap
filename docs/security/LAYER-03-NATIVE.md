# Layer 03 — Android native binary hardening

## Scope and audited architecture

Audited on `dev` at commit `4760063e5b79fbdedb7dd7086e0c0d2db25e81c1` (2026-11-14).

- No first-party C/C++ source, `CMakeLists.txt`, `Android.mk`, `Application.mk`, checked-in `.so`, or checked-in static native archive is present in the repository tree.
- The Android app pins NDK `27.0.12077973`; Android Gradle Plugin is `8.11.1`.
- The transitive Flutter package `jni 0.14.2` is an Android FFI plugin whose Android Gradle module builds native code through its own CMake project. Its CMake source and compile flags are owned by the resolved pub dependency, not by this repository.
- JNIGen output in `lib/native_bindings/andrid_utils.dart` resolves Kotlin/Java methods on `Equalizer` and `SDKInt`. These are not C/C++ JNI exports. The app does not declare `externalNativeBuild` or `ndk-build`.
- The maintained `packages/just_audio` Android fork uses Java/Kotlin and AndroidX Media3. `MuziiNapPcmAudioProcessor.kt` is JVM code; it is not a native C++ DSP implementation.
- The DSP implementation is Kotlin `NativeEqCurve` plus Android `DynamicsProcessing` / `Virtualizer`. Layer 03 does not modify those algorithms or playback code.

## Release treatment

Android Gradle Plugin strips native debug metadata from release libraries by default. The app release variant now requests `ndk.debugSymbolLevel = 'FULL'`. This produces the separate AGP archive at:

`android/app/build/outputs/native-debug-symbols/release/native-debug-symbols.zip`

The release APK remains stripped; debug symbols are not embedded in the APK. The APK workflow checks that the symbols archive exists, contains extracted `.dbg` entries, and has at least one symbol entry for every ABI found in the APK. It writes a manifest containing repository, commit SHA, app version, CI build ID, pinned NDK/AGP versions, ABI list, packaged library filenames, and captured symbol entry names.

The native archive and manifest are placed inside the existing encrypted private symbols bundle with Dart AOT symbols and the R8 mapping. The encrypted bundle is uploaded as a GitHub Actions artifact with 90-day retention; it is not attached to a public release. The encryption key remains the existing `SYMBOLS_ENCRYPTION_KEY` Actions secret.

## JNI and visibility

Do not apply blanket hidden visibility or remove dynamic exports to dependency-owned JNI/FFI libraries. The resolved `jni` plugin owns its CMake target, exported ABI, and loader contract. The generated JNIGen binding depends on the exact JVM class/member names retained by Layer 02 R8 rules. Any future visibility changes must be made in the owning native target and validated against its JNI/FFI loading contract first.

## ABI policy

No `abiFilters` or target-platform restriction is added. CI derives the ABI set from the produced universal APK and requires matching native debug-symbol coverage for each packaged ABI. The actual ABI set is recorded in the private manifest rather than hard-coded in this document.

## Build and verification

The `MuziiNap Android APK` workflow on `dev` performs the release build, APK signature verification, native library inventory, native debug-symbol archive verification, and encryption/integrity verification of the private symbols bundle.

The code-quality workflow runs Android debug compilation and existing Kotlin DSP unit tests. CI build evidence must be read from the workflow run after this commit; a repository edit alone is not evidence of a successful native build.

Device-level playback, JNI runtime loading, native crash symbolication, and latency measurements require an Android device/emulator and are not established by static repository inspection or APK compilation alone.

## Explicit limitations

- No first-party C/C++ DSP source exists to receive project-owned compiler/linker hardening flags such as `-fvisibility=hidden`, `-Wl,--exclude-libs`, or custom LTO options.
- The `jni` dependency's CMake flags are upstream-owned. This layer captures and verifies its release symbols without forking or rewriting the dependency.
- AGP cannot recover debug metadata that an upstream dependency has already stripped. The workflow fails if the native symbol archive is absent, has no `.dbg` entries, or lacks symbol entries for an APK ABI. It may also report an upstream library as unavailable if that dependency is pre-stripped.
- No native DSP behavior, PCM algorithm, JNI binding, ABI filter, or audio-thread behavior was changed.

## Rollback

Revert the Layer 03 commit on `dev`. This removes the `FULL` native symbol extraction request and CI symbol capture step. It does not change app runtime behavior, DSP processing, JNI bindings, or ABI selection.
