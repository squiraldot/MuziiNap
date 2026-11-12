# MuziiNap Universal Song Sharing URL Contract

**Contract version:** 1  
**Status:** Implemented in Android Phase 01; website implementation is pending a separately authorized website phase.

## Canonical identity and URL

A shared song is identified only by its YouTube Video ID. Its canonical URL is:

`https://muziinap-site.vercel.app/song/VIDEO_ID`

Example: `https://muziinap-site.vercel.app/song/dQw4w9WgXcQ`

The URL contains no stream URL, expiry data, authentication token, or song metadata. Stream URLs are transient playback details and must never become song identity.

## Video ID validation

A valid ID is exactly 11 ASCII characters matching `[A-Za-z0-9_-]{11}`. IDs are case-sensitive; consumers must preserve their exact spelling. Do not lowercase, trim, transliterate, or normalize an ID.

Reject empty IDs, IDs of any other length, whitespace, punctuation outside the allowed alphabet, and encoded substitutes.

## Parsing and URL rules

| Property | Contract |
| --- | --- |
| Scheme | HTTPS only |
| Host | Exactly `muziinap-site.vercel.app`; DNS host comparison is case-insensitive |
| Port | HTTPS default port 443 only |
| Route | Exactly `/song/VIDEO_ID` |
| Trailing slash | One optional trailing slash accepted by Android parser; canonical generation omits it |
| Path case | Case-sensitive; `/Song/` is invalid |
| Encoding | Literal ASCII path only; percent-encoded path forms rejected |
| Query | Any query component rejected, including tracking parameters |
| Fragment | Any fragment rejected |
| Credentials | User-info in authority rejected |
| Extra segments | Rejected, including duplicate slashes and multiple trailing slashes |
| Empty ID | Rejected |
| Unknown routes | Not a song URL; website must show its not-found experience and Android must reject safely |

A parser must not infer song IDs from arbitrary URL text, query values, YouTube watch URLs, or another host. Existing YouTube URL import is a separate feature and must retain its current behavior.

## Android ↔ website agreement

- Public origin: `https://muziinap-site.vercel.app`
- Route prefix: `/song/`
- Identifier: one case-sensitive 11-character YouTube Video ID
- Canonical generator: `SongSharingConfig.canonicalUrl(videoId)`
- Android parser: `SongSharingConfig.parseVideoId(uri)`
- Invalid URL: no song is opened; handle as unsupported/invalid without crashing.
- Song identity: YouTube Video ID, never title, artist, stream URL, or metadata tuple.

The website route must extract the single path segment after `/song/`, apply the same ID validation, and show an invalid/not-found experience for invalid IDs. It should canonicalize a valid trailing-slash request to the slashless URL. Website routing has not been modified in this Android-only phase.

## Android configuration

Keep the public domain and route prefix centralized in `lib/utils/song_sharing_config.dart`. Future share actions and route consumers must call its validation and canonical URL methods rather than duplicate domain strings.

## Examples

Valid:
- `https://muziinap-site.vercel.app/song/dQw4w9WgXcQ`
- `https://muziinap-site.vercel.app/song/dQw4w9WgXcQ/` (accepted input; canonical output omits slash)

Invalid:
- `http://muziinap-site.vercel.app/song/dQw4w9WgXcQ` (HTTP)
- `https://example.com/song/dQw4w9WgXcQ` (wrong host)
- `https://muziinap-site.vercel.app/song/short` (invalid ID)
- `https://muziinap-site.vercel.app/song/dQw4w9WgXcQ?utm_source=share` (query)
- `https://muziinap-site.vercel.app/song/dQw4w9WgXcQ#track` (fragment)
- `https://muziinap-site.vercel.app/song/dQw4w9WgXcQ/extra` (extra path)

## Compatibility and future phases

This contract does not enable Android App Links, add playback behavior, create a backend, or introduce Deferred Deep Linking. Those concerns require separately authorized phases. If the public domain or route changes, version and migrate the contract deliberately. Any future query parameters require a documented contract revision and matching Android/website tests.
