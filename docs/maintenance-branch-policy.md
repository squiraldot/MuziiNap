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
- `.github/workflows/release.yml` runs on pushes to `main`, version tags matching `v*.*.*`, and manual dispatch. It does not currently run automatically on `dev` pushes.

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
