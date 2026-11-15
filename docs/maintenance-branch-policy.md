# MuziiNap Maintenance Branch Policy

**Effective repository snapshot:** 14 November 2026  
**Repository:** `squiraldot/MuziiNap`

## Branch roles

| Branch | Role | Expected use |
| --- | --- | --- |
| `dev` | **Official maintenance and day-to-day development branch** | Routine fixes, maintenance, feature work, documentation, and CI validation |
| `main` | Release/integration branch | Reviewed release-ready changes and version/tag-based release process |

The existing `dev` branch is authoritative for ongoing maintenance. New routine work should start from and target `dev`. Promote changes from `dev` to `main` only through the agreed review/release process.

## Automation currently configured

- `.github/workflows/code_quality.yml` runs on pushes to `main` and `dev`, and on manual dispatch.
- `.github/workflows/muziinap-apk.yml` runs on pushes to `main` and `dev`, and on manual dispatch.
- `.github/workflows/release.yml` runs on pushes to `main` and manual dispatch only. It has no version-tag trigger and does not run automatically on `dev` pushes. It uploads GitHub Actions artifacts and does not create/publish a GitHub Release.

Check workflow results against the exact commit SHA. CI does not replace physical-device testing.

## Repository settings and limits

GitHub currently reports `main` as the repository's default branch. Default-branch selection is separate from the maintenance-branch policy. This policy designates `dev` for maintenance; it does not change the default branch, branch protection/rulesets, or release settings.

Do not rename, delete, force-update, or create branches; change the default branch; alter branch protections; or publish/replace release tags without explicit authorization.

## Contributor expectations

1. Confirm the current branch before editing.
2. Perform routine maintenance on `dev`.
3. Keep changes scoped and preserve unrelated behavior.
4. Update relevant docs and tests when implementation/contracts change.
5. Do not claim CI/device verification without checking exact-commit evidence.
6. Keep `main` reserved for reviewed integration/release work.

See [AI Coding Instructions](../.github/copilot-instructions.md), [Project Memory](../memory-agent.md), and [README](../README.md).

## Release and distribution policy clarification (2026-11-15)

The current `main` release workflow builds a universal APK plus ABI-specific APKs (armeabi-v7a, arm64-v8a, x86_64), verifies APK signatures against the configured Actions keystore, generates and verifies SHA-256 checksums, and uploads GitHub Actions artifacts. It also encrypts Dart AOT symbols and R8 mappings. It does **not** create a GitHub Release, attach APK assets to a GitHub Release, or trigger on version tags.

The separate `muziinap-apk.yml` workflow builds a universal APK on `main`/`dev` pushes or manual dispatch and uploads build/symbol artifacts. Public APK distribution is through https://telegram.me/muziinap/3. The in-app checker obtains version metadata from https://github.com/squiraldot/MuziiNap-Official; that repository is not the APK distribution destination.

Current toolchain: Flutter 3.47.5 (submodule commit `84abdf7372654171e0a66174be2846f53331f6ab`), Java 17, AGP 8.11.1, Gradle 8.14.2, Kotlin 2.2.20, NDK 28.2.13676358. Current `pubspec.yaml` version is `1.0.0+2` (`versionName` `1.0.0`, Android `versionCode` `2`); the configured production release version is `v1.0.0`.
