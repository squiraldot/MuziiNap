# MuziiNap Universal Song Sharing URL Contract

**Contract version:** 1  
**Android status:** Implemented; Phase 08 Android acceptance recorded as complete  
**Last repository audit:** 14 November 2026  
**Audited branch/commit:** `dev` / `670583ab20d9caf0f76df40999018fe4553e8704`

## Canonical identity and URL

A shared song is identified only by its YouTube Video ID. Its canonical URL is:

`https://muziinap-site.vercel.app/song/VIDEO_ID`

Example: `https://muziinap-site.vercel.app/song/dQw4w9WgXcQ`

- Website host: `muziinap-site.vercel.app`
- Android application ID: `com.merrmist.muziinapmusic`
- Android parser and URL generator: `lib/utils/song_sharing_config.dart`
- Android incoming-link service: `lib/services/deep_link_service.dart`

The URL contains no stream URL, expiry data, authentication token, or song metadata. Stream URLs are transient playback details and must never become song identity.

`SongSharingConfig.canonicalUrl(videoId)` validates the 11-character ID and always generates the lowercase canonical HTTPS URL with no explicit port and no trailing slash.

## Video ID validation

A valid ID is exactly 11 ASCII characters matching `[A-Za-z0-9_-]{11}`. IDs are case-sensitive; consumers must preserve their exact spelling. Do not lowercase, trim, transliterate, or normalize an ID.

Reject empty IDs, IDs of any other length, whitespace, punctuation outside the allowed alphabet, and encoded substitutes.

## Parsing and URL rules

| Property | Contract |
| --- | --- |
| Scheme | HTTPS only; scheme comparison is case-insensitive (`https` and `HTTPS` are accepted) |
| Host | Exactly `muziinap-site.vercel.app`; DNS host comparison is case-insensitive |
| Authority | Exact host, optionally with explicit default port `:443`; authority comparison is case-insensitive; no credentials or encoded host |
| Port | HTTPS default port 443 only; explicit `:443` is accepted; non-default or non-canonical port forms rejected |
| Route | Exactly `/song/VIDEO_ID` |
| Trailing slash | One optional trailing slash accepted by Android parser; canonical generation omits it |
| Path case | Case-sensitive; `/Song/` is invalid |
| Encoding | Literal ASCII path only; percent-encoded authority/path forms rejected |
| Dot segments | Literal and encoded traversal segments rejected |
| Separators | Encoded separators, backslash path forms, duplicate slashes rejected |
| Query | Any query component rejected, including tracking parameters |
| Fragment | Any fragment rejected |
| Credentials | User-info in authority rejected |
| Extra segments | Rejected, including duplicate slashes and multiple trailing slashes |
| Empty ID | Rejected |
| Unknown routes | Not a song URL; website shows its not-found/invalid experience and Android rejects safely |

Android validates the original incoming URL string before relying on normalized URI path/authority values. Raw input checks reject percent-encoding, query, and fragment delimiters before URI parsing; the original authority and path are then checked against the exact contract. This prevents URI parser normalization from accepting encoded or dot-segment forms.

A parser must not infer song IDs from arbitrary URL text, query values, YouTube watch URLs, or another host. Existing YouTube URL import is a separate feature and retains its current behavior.

## Android App Links configuration

The Android manifest at `android/app/src/main/AndroidManifest.xml` declares an HTTPS `VIEW` intent filter with `android:autoVerify="true"`, `DEFAULT` and `BROWSABLE` categories, and the exact website host. Its path patterns match the 11-character song route, with and without the optional trailing slash. Flutter's `SongSharingConfig` applies the stricter character-level validation after delivery.

The website association is published at:

`https://muziinap-site.vercel.app/.well-known/assetlinks.json`

The Digital Asset Links statement uses the `delegate_permission/common.handle_all_urls` relationship and identifies Android package `com.merrmist.muziinapmusic` in the `android_app` namespace. Its `sha256_cert_fingerprints` entry must match the certificate that signs the distributed release APK. Physical-device testing reported that the production statement's package and signing fingerprint match the installed release APK, and that the association file opened successfully.

**Fingerprint provenance:** the authoritative colon-separated SHA-256 value is the value published in the production `assetlinks.json`; it is not duplicated in this Android repository. This avoids documenting a stale or guessed signing certificate value. Re-check the live statement against the release APK certificate whenever the release signing key changes.

## Website fallback and install behavior

When the app is installed and the verified domain association is active, Android App Links can route canonical song URLs into MuziiNap. When the app is not installed, the website handles the URL and presents the song page/fallback experience. Physical-device testing reported that the app-not-installed fallback worked.

There is **no Deferred Deep Linking**. Installing the app after visiting a song page does not automatically transfer or replay that earlier URL on a later manual launch. Physical-device testing specifically confirmed that install-then-manual-launch does not resume an old shared song.

The website implementation and deployment are maintained in a separate repository; this document records the cross-platform contract and Android integration, not website source changes or fresh deployment verification.

## Existing YouTube import compatibility

Canonical MuziiNap song URLs are parsed separately from legacy YouTube imports. The Android manifest retains the existing HTTPS intent filters for `youtube.com`, `www.youtube.com`, `m.youtube.com`, `music.youtube.com`, and `youtu.be`. The legacy import path remains responsible for supported YouTube watch, music, short-link, playlist, album, and artist/channel URLs. Incoming non-MuziiNap URLs continue through the existing legacy-link handling path.

Preset-file sharing and handling are separate from song URL parsing and are not changed by this contract.

## Phase 08 — Android Deep Link Final Acceptance

**Acceptance status: COMPLETE**  
**Audited repository:** `squiraldot/MuziiNap`  
**Branch:** `dev`  
**Audited commit:** `670583ab20d9caf0f76df40999018fe4553e8704`

The Android deep-link implementation is accepted as complete for the defined Phase 08 scope. This status is based on source-level implementation review and the successful automated workflows listed below. It does not represent a new physical-device test execution by this final documentation audit.

**Verified GitHub Actions evidence for the audited commit:**

- [Code quality check #615 — SUCCESS](https://github.com/squiraldot/MuziiNap/actions/runs/43568710322)
- [MuziiNap Android APK #613 — SUCCESS](https://github.com/squiraldot/MuziiNap/actions/runs/43568710272)

Both workflow runs were checked as successful against the current audited commit `670583ab20d9caf0f76df40999018fe4553e8704`.

**Acceptance evidence is intentionally separated:**

- **Source-level implementation verification:** canonical URL generation and parsing, Android HTTPS App Links manifest declarations, incoming-link handling, playback coordination and stale-request protection, and regression tests were inspected in the audited source.
- **Automated CI verification:** the two workflow runs above are independently verified as successful for the audited commit.
- **Physical-device verification:** previously reported complete in the existing project test record; this Phase 08 final audit did not repeat those device tests.

**Deferred Deep Linking: NOT IMPLEMENTED / OUT OF SCOPE.** Installing the app after opening a song URL does not preserve and automatically replay that URL on a later manual launch. This is an explicit scope limitation, not an incomplete Phase 08 acceptance item.

## Verification status and evidence boundaries

### Automated/source-level verification

- The parser unit tests cover all supported case variations, explicit default-port handling, ID alphabet/length/case, trailing slash, authority/port/credential validation, traversal and encoded inputs, query/fragment rejection, and extra path segments.
- Android App Links intent-filter configuration is source-verified in the manifest.
- Existing YouTube import routing and preset-file intent filters remain in source.
- GitHub Actions provides the repository's code-quality and release-APK workflows. Their per-commit status must be checked on the commit under review; a previous green run is not evidence for a later commit.

### Physical-device verification (reported)

The completed physical-device test report states that shared song links open and play the correct song; cold start, warm start, background delivery, multiple links/latest-song behavior, queue preservation, next/previous, and notification controls passed. It also reports successful app-not-installed fallback and no deferred resume after install/manual launch. The production Asset Links URL was opened and its package ID and signing fingerprint were reported to match the release APK.

These device observations are recorded as reported test evidence, not as results produced by the automated parser test suite in this phase. Repeat physical-device checks after changes to the manifest, application ID, domain association, or release signing certificate.

## Contract maintenance

Keep the public domain and route prefix centralized in `lib/utils/song_sharing_config.dart`. Future share actions and route consumers must call its validation and canonical URL methods rather than duplicate domain strings.

If the public domain, route, ID format, or signing certificate changes, version and migrate the contract deliberately. Any future query parameters require a documented contract revision and matching Android/website tests.
