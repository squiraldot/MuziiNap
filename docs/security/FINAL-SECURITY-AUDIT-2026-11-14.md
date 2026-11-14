# MuziiNap — Final Security Integration Audit

**Audit date:** 2026-11-14  
**Repository:** `squiraldot/MuziiNap`  
**Required branch:** `dev`  
**Audited code baseline:** `ff3eb59582bf8514efc42bcf0ea985bbadf0c505`  
**Audit documentation head before this report:** `974e2aca4d47ab4d52bfb44ed5e404694ce2001a`

## Executive decision

**NOT SECURITY-COMPLETE.** Layers 01 and 02 have successful release-build evidence. Layers 03, 04, and 05 remain partial because native C/C++ hardening is not applicable to any first-party C/C++ source currently present, runtime APK tamper response is non-enforcing and has not been device-tested, and the project has no first-party backend or server-side integrity-verification path. Real-device functional regression tests and controlled modified/repackaged APK tests have not been run.

No claim of complete source protection or resistance to all reverse engineering is made.

## Layer-by-layer status

| Layer | Status | Evidence and limitation |
| --- | --- | --- |
| 01 — Flutter Dart AOT obfuscation | **VERIFIED** (universal APK build) | Release workflow #684 built with `--release --obfuscate --split-debug-info`. Three non-empty Dart symbol files were packaged into the encrypted symbols archive. CI confirmed no Dart `.symbols` file was inside the APK. Multi-ABI split release was not run on `dev`. |
| 02 — Android R8 / ProGuard | **VERIFIED** (universal APK build) | `minifyEnabled true`, `shrinkResources true`, optimized default ProGuard config, targeted keep rules, and non-empty R8 `mapping.txt` were present. Workflow #684 copied one mapping into the encrypted symbols archive. No physical-device minification regression test was performed. |
| 03 — Native binary hardening | **PARTIALLY IMPLEMENTED** | No first-party `.c`, `.cc`, `.cpp`, `.h`, `CMakeLists.txt`, `Android.mk`, checked-in `.so`, or native static archive exists in the audited repository tree. Therefore project-owned C/C++ compiler/linker hardening flags cannot be applied honestly. NDK 27.0.12077973 is pinned; AGP FULL native debug-symbol extraction is configured. Workflow #684 verified native debug-symbol entries for universal APK ABIs `arm64-v8a` and `armeabi-v7a`. This is symbol preservation, not proof that dependency-owned native binaries were hardened. |
| 04 — APK integrity / tamper detection | **PARTIALLY IMPLEMENTED** | CI verified the release APK signature and compared its certificate SHA-256 fingerprint with the restored release keystore. Runtime policy tests cover trusted/untrusted fingerprints, debug separation, missing pin, and package ID mismatch. However, `ApkIntegrityVerifier` only logs the status and startup continues; it is not an enforcement boundary. No controlled modified/repacked APK was installed and tested on a device. |
| 05 — Backend and secret protection | **PARTIALLY IMPLEMENTED** | CredentialVault migration to Android Keystore-backed secure storage is present; credential vault, session manager, and Piped security tests are in the Flutter suite. CI secrets are referenced via GitHub Secrets. No MuziiNap-owned backend exists, so server-side integrity token verification, server-side secret custody, and backend authorization are **NOT IMPLEMENTED**. The InnerTube API key is public client configuration, not a private server secret. |

## Branch and commit integrity

- All audit work was kept on the existing `dev` branch. No branch was created.
- The final audit documentation changes are documentation-only relative to the successful code baseline.
- Compare `ff3eb59582bf8514efc42bcf0ea985bbadf0c505` to `974e2aca4d47ab4d52bfb44ed5e404694ce2001a`: only these three documentation files differ:
  - `docs/backend-security-layer-05.md`
  - `docs/dart-aot-obfuscation.md`
  - `docs/security/LAYER-03-NATIVE.md`
- `.github/workflows/release.yml` is unchanged from the successful baseline. An attempted temporary extension to run the multi-ABI release workflow on `dev` produced workflow-configuration failures and was reverted. The multi-ABI workflow is not claimed as verified on `dev`.
- No application source, playback code, native DSP algorithm, manifest, signing configuration, or release runtime behavior was changed by this audit.

## CI and release-build evidence

### Successful runs on code baseline `ff3eb59582bf8514efc42bcf0ea985bbadf0c505`

- [MuziiNap Android APK — run #684](https://github.com/squiraldot/MuziiNap/actions/runs/43610184624): **SUCCESS**.
  - Flutter dependency resolution and Isar generation succeeded.
  - Obfuscated, R8-minified universal release APK built.
  - Release keystore restored and alias validated.
  - APK signature verification passed; actual signer fingerprint matched the keystore-derived expected fingerprint.
  - No Dart `.symbols` files were present inside the APK.
  - Native debug-symbol archive existed and had entries for all ABIs found in the APK: `arm64-v8a`, `armeabi-v7a`.
  - Encrypted symbols archive round-tripped successfully: 3 Dart symbol files and 1 R8 mapping file.
  - APK artifact size: 45,138,372 bytes. Encrypted symbols artifact size: 133,007,929 bytes.
- [Code quality check — run #686](https://github.com/squiraldot/MuziiNap/actions/runs/43610184656): **SUCCESS**.
  - Android debug APK compilation succeeded.
  - Kotlin DSP unit tests succeeded.
  - Flutter analyzer checks succeeded.
  - Flutter test suite succeeded.

These successful runs predate the documentation-only audit commits. The application source and build configuration were unchanged between that tested code baseline and the audit documentation commits.

### Release variants not verified

The separate `Release Workflow` defines universal and split APK outputs for `armeabi-v7a`, `arm64-v8a`, and `x86_64`, plus checksum generation. It is configured for `main` pushes and version tags, not ordinary `dev` pushes. No successful execution of that workflow on this `dev` audit was obtained. Therefore the x86_64 APK, all split APK signatures, split-variant mappings/symbols, and release checksum manifest remain **NOT VERIFIED** in this audit.

## Functional regression coverage

| Area | Result |
| --- | --- |
| Flutter startup / app initialization | Automated compilation and unit suite passed; real-device launch not verified |
| Song playback | **NOT VERIFIED** end-to-end on device |
| Queue playback and transitions | Unit/policy coverage exists; **NOT VERIFIED** end-to-end on device |
| Background playback / AudioService | **NOT VERIFIED** on device |
| Equalizer | Kotlin DSP unit tests and Flutter tests passed; device audio output not verified |
| Native DSP / JNI | JVM unit coverage and debug compilation passed; runtime JNI loading on device not verified |
| Android widgets | **NOT VERIFIED** on device |
| Deep links and song/preset sharing | Unit tests exist; Android intent flows not verified on device |
| BgUtils runtime / foreground service | Policy and runtime-manager tests exist; installation, service health and download not verified on device |
| Download functionality | **NOT VERIFIED** end-to-end on device |

The passing automated suite is useful regression evidence, but it does not replace playback tests on real Android hardware. In particular, no claim is made that queue transitions, background playback, notifications, or a single-song playback path were functionally exercised in this audit.

## Security verification evidence and gaps

### Verified by CI

- Release APK signature structure verification with `apksigner`.
- Signer certificate fingerprint equality with the certificate exported from the CI keystore.
- Dart symbols are outside the APK.
- Non-empty Dart symbols and R8 mapping exist.
- Native debug-symbol archive exists and contains ABI entries for the universal APK's packaged ABIs.
- Encrypted symbols archive decrypts and its tar archive is readable.
- GitHub Actions workflows source their keystore and symbol encryption passphrase from Actions Secrets rather than literal values in the checked workflow.

### Not verified / remaining risks

1. **Runtime tamper enforcement:** signer mismatch is logged, but startup continues. Client-side code and embedded pins can be patched. No server trusts this signal.
2. **Modified/repackaged APK:** no controlled mutation, re-signing, installation, or runtime detection test was performed.
3. **Debug vs release runtime behavior:** policy unit tests cover status classification; separate device-installed debug and release APK comparison was not performed.
4. **Private symbol exposure:** CI uploaded encrypted symbols only. No independent download-and-decrypt test from the artifact service, public-access permission test, or artifact contents scan was performed.
5. **Secret leakage:** no exhaustive Git-history scan or binary/artifact secret scan was run. Workflow source review is not proof that no credential was ever committed or logged.
6. **Native ELF metadata:** release logs emitted three warnings that a generated ELF library contains unobfuscated DWARF debugging information. The exact affected ELF payload and whether the relevant metadata is present in each distributed APK were not independently inspected. Investigate before claiming native debug metadata is absent from public APKs. Preserve private debug symbols for crash recovery.
7. **Native compiler hardening:** there is no first-party C/C++ target to receive project-owned flags. Dependency-owned native targets remain governed by their upstream build configuration.
8. **Backend verification:** no server-side challenge, replay defense, Play Integrity validation, or server-side authorization exists in this project.
9. **Client credentials:** rooted devices, runtime instrumentation, memory inspection, and a compromised unlocked process may expose credentials while in use. Keystore-backed storage protects data at rest, not a compromised runtime.
10. **Toolchain maintenance:** CI logs warn that Flutter support for the currently pinned Gradle 8.14.2, AGP 8.11.1, and Kotlin 2.2.20 versions will soon be dropped. Upgrade only with a separate compatibility-tested change.

## Modified files

Only documentation changed in the final audit diff:

- `docs/backend-security-layer-05.md` — records successful CI test evidence and retains the device-test limitation.
- `docs/dart-aot-obfuscation.md` — corrects encrypted artifact naming for both workflows.
- `docs/security/LAYER-03-NATIVE.md` — updates the audit reference and clarifies which native symbol workflow was actually verified.

No app code was modified. No debug symbols were deleted. No private build artifact was published as a GitHub Release by this audit.

## Recovery and rollback

- Keep the encrypted symbols artifact and its matching `SYMBOLS_ENCRYPTION_KEY` passphrase in separate approved private storage. Artifact retention is finite; the APK workflow requests 90 days for encrypted symbols.
- For Dart crashes, use the exact build's `.symbols` file with `flutter symbolize`.
- For Java/Kotlin crashes, use the exact build's R8 `mapping.txt` with Retrace.
- For native crashes, use the matching AGP native debug-symbol archive and matching build/ABI.
- Never mix symbol files, mappings, APKs, or signing identities from different commits or workflow attempts.
- To roll back only the documentation audit, revert the audit documentation commits on `dev`. No runtime rollback is needed because application source and runtime configuration were not changed.

## Required follow-up before security-complete

1. Run the separate multi-ABI release workflow on `dev` and retain evidence for universal, armv7, arm64, and x86_64 outputs, signatures, checksums, R8 mappings, Dart symbols, and native debug symbols.
2. Resolve the DWARF warning with a precise APK/ELF inspection. Preserve matching private symbols; do not simply delete debug information.
3. Install release and debug APKs on supported Android versions and perform controlled modified/repackaged APK tests.
4. Decide whether a signer mismatch should block selected sensitive operations. Do not treat a local client Boolean as server proof.
5. If server-protected features are introduced, implement server-side integrity challenge validation, freshness/replay protection, package/certificate policy, and authorization.
6. Run a device regression matrix for playback, queue transitions, background audio, AudioService, equalizer, JNI, widgets, deep links, sharing, BgUtils, downloads, and startup.
7. Run full Git-history and release-artifact secret scans; review provider-side restrictions for public client API keys.

**Final classification:** The five-layer protection system is not security-complete. Layers 01 and 02 are verified for the tested universal release build; Layers 03–05 remain partial or unimplemented in the specific areas stated above.
