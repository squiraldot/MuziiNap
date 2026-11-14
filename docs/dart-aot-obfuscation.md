# Dart AOT obfuscation and symbol recovery

**Scope:** Layer 01 only — official Flutter Dart AOT obfuscation for Android release APKs.

## Protection behavior

Every Android release APK build in these workflows uses Flutter's official AOT obfuscation:

- `.github/workflows/muziinap-apk.yml` — the universal branch APK.
- `.github/workflows/release.yml` — the universal APK and all ABI-specific APKs.

Each release build uses `--release --obfuscate --split-debug-info=<unique-directory>`. Debug builds and the ordinary code-quality workflow remain unchanged.

Dart obfuscation renames Dart symbols in the compiled AOT program. It is not source encryption, does not encrypt assets or native libraries, and does not make reverse engineering impossible.

## Build identity and symbol handling

The symbol archive manifest records the full Git commit SHA, exact `pubspec.yaml` version (including build number), GitHub Actions run ID and attempt (unique build ID), Git ref, and symbol-file count.

Universal and ABI-specific invocations write to separate directories. The packaging script refuses to continue if it cannot find a non-empty `*.symbols` file.

Raw symbols are kept outside the APK output directory. The workflows check that no `*.symbols` entry is present inside each APK. Before artifact upload, the packaging script creates a manifest and compressed archive, encrypts it with GnuPG symmetric AES-256 using the dedicated `SYMBOLS_ENCRYPTION_KEY` Actions secret, decrypts the result on the runner to validate archive integrity, and removes plaintext symbols and the temporary unencrypted archive.

Only the encrypted `.gpg` archive is uploaded. APK artifacts remain separate and retain their existing distribution behavior.

## Required GitHub Actions secret

Before running either protected release workflow, configure:

- **Name:** `SYMBOLS_ENCRYPTION_KEY`
- **Value:** a unique, high-entropy passphrase (use at least 32 random bytes).

Configure it in **Repository → Settings → Secrets and variables → Actions → New repository secret**. Do not use the Android keystore password, commit the passphrase, put it in a workflow variable, or paste it into logs.

This repository is public. GitHub Actions artifacts in a public repository must not be treated as private. The symbol artifact is therefore encrypted before upload; public access to the ciphertext does not reveal the symbols without the separate secret. Keep the passphrase in an approved password manager and restrict who can access it. Retain old passphrases for as long as artifacts encrypted with them may be needed.

## Artifact retention

Encrypted symbol artifacts request **90 days** of retention. The repository or organization Actions retention policy may impose a lower maximum. Download and preserve the encrypted archive in approved private storage before it expires when a longer investigation window is required. Never upload plaintext symbols to a public release, public repository, or ordinary unencrypted artifact.

Artifact names include the commit SHA, run ID, and attempt. Builds do not overwrite one another.

## Release build commands

Use a unique, access-controlled directory for every release build. Do not put symbols in the repository's public source tree.

Universal APK:

```bash
flutter build apk --release --obfuscate \
  --split-debug-info=/secure/symbols/<commit>/<version>/<build-id>/universal
```

ABI-specific APKs:

```bash
flutter build apk \
  --target-platform android-arm,android-arm64,android-x64 \
  --split-per-abi --release --obfuscate \
  --split-debug-info=/secure/symbols/<commit>/<version>/<build-id>/split-per-abi
```

Keep the same Flutter SDK, Java 17, Android NDK, localization generation, Isar generation, dependency resolution, and signing setup used by the repository's workflows. Do not use obfuscation on debug builds.

## Recover and symbolicate a crash

1. Locate the workflow run for the exact commit, version, and build ID.
2. Download the matching `muziinap-obfuscated-symbols-<commit>-<run-id>-<attempt>` artifact before it expires.
3. Obtain the matching passphrase from the approved password manager.
4. Decrypt and extract the archive:

```bash
gpg --output muziinap-symbols.tar.gz --decrypt muziinap-symbols-<commit>-<version>-<build-id>.tar.gz.gpg
mkdir recovered-symbols
tar -xzf muziinap-symbols.tar.gz -C recovered-symbols
```

GnuPG prompts for the passphrase interactively. Do not place it directly in shell history or command-line arguments.

5. Confirm `manifest.txt` matches the APK's commit, version, and build ID. Never symbolize a crash with symbols from a different build.
6. Use the symbol directory corresponding to the APK variant:

```bash
flutter symbolize -i crash.txt -d recovered-symbols/universal
```

For ABI-specific builds, use the corresponding directory under `split-per-abi`. If the Flutter output contains architecture-specific symbol files in a nested directory, point `-d` to the directory containing the matching symbol file.

## Recovery and retention precautions

- Preserve the encrypted artifact and its passphrase together in approved private storage when the 90-day CI window is insufficient.
- If the passphrase is lost, the encrypted symbols cannot be recovered.
- If the passphrase is rotated, keep the previous passphrase until every artifact encrypted with it has expired or been securely re-encrypted.
- If an artifact expires and no private copy exists, exact Dart stack-trace symbolication for that build may no longer be possible.
- Never commit raw symbols, decrypted archives, keystores, or credentials.

## Verification boundaries

CI can verify the release build, APK signature, existence of symbol files, successful encryption/decryption, archive integrity, unique build metadata, and separation of APKs from symbols. It cannot prove real-device playback, queue behavior, background audio, widgets, JNI behavior, or deep-link behavior. Those require device/integration testing and remain separate from this build-protection layer.
