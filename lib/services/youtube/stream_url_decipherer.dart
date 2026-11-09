import 'nsig_decipher_service.dart';
import 'signature_decipher_service.dart';

/// Resolves cipher-protected and n-throttled InnerTube format URLs.
/// A failed candidate is discarded without affecting its siblings.
class StreamUrlDecipherer {
  StreamUrlDecipherer({
    required NsigDecipherService nsig,
    required SignatureDecipherService signature,
  })  : _nsig = nsig,
        _signature = signature;

  final NsigDecipherService _nsig;
  final SignatureDecipherService _signature;
  final Map<String, Future<String?>> _inFlight = {};

  Future<List<Map<String, dynamic>>> decipherFormats(
    List<dynamic> formats, {
    Uri? playerUrl,
  }) async {
    final resolved = <Map<String, dynamic>>[];
    for (final entry in formats) {
      if (entry is! Map) continue;
      try {
        final format = Map<String, dynamic>.from(entry);
        final cipherValue =
            (format['signatureCipher'] ?? format['cipher'])?.toString();
        var mediaUrl = format['url']?.toString();

        if (cipherValue != null && cipherValue.isNotEmpty) {
          final cipher = Uri.splitQueryString(cipherValue);
          mediaUrl ??= cipher['url'];
          final encrypted = cipher['s'];
          if (encrypted != null && encrypted.isNotEmpty) {
            if (playerUrl == null || mediaUrl == null) {
              throw const FormatException('Player JavaScript URL unavailable');
            }
            final parameter = cipher['sp']?.trim().isNotEmpty == true
                ? cipher['sp']!.trim()
                : 'signature';
            final signature = await _memoized(
              'sig|' + playerUrl.toString() + '|$encrypted',
              () => _signature.decipher(playerUrl, encrypted),
            );
            if (signature == null || signature.isEmpty) {
              throw const FormatException('Signature deciphering failed');
            }
            mediaUrl = _setQueryParameter(mediaUrl, parameter, signature);
          }
        }

        if (mediaUrl == null || !_isSafeMediaUrl(mediaUrl)) continue;
        final n = Uri.parse(mediaUrl).queryParameters['n'];
        if (n != null) {
          if (playerUrl == null) {
            throw const FormatException('Player JavaScript URL unavailable');
          }
          final deciphered = await _memoized(
            'n|' + playerUrl.toString() + '|$n',
            () => _nsig.decipher(playerUrl, n),
          );
          if (deciphered == null || deciphered.isEmpty || deciphered == n) {
            throw const FormatException('n parameter deciphering failed');
          }
          mediaUrl = _setQueryParameter(mediaUrl, 'n', deciphered);
        }

        if (!_isSafeMediaUrl(mediaUrl)) continue;
        if (n != null && Uri.parse(mediaUrl).queryParameters['n'] == n) {
          continue;
        }
        format['url'] = mediaUrl;
        format.remove('signatureCipher');
        format.remove('cipher');
        resolved.add(format);
      } catch (_) {
        // Fail closed for this candidate only. Other valid formats survive.
      }
    }
    return resolved;
  }

  Future<String?> _memoized(
    String key,
    Future<String> Function() operation,
  ) async {
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = operation();
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  static bool _isSafeMediaUrl(String raw) {
    final uri = Uri.tryParse(raw);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  /// Replaces one query value while leaving unrelated raw query components
  /// (including signed/duplicate parameters) byte-for-byte intact.
  static String _setQueryParameter(
    String rawUrl,
    String name,
    String value,
  ) {
    final fragmentIndex = rawUrl.indexOf('#');
    final beforeFragment =
        fragmentIndex < 0 ? rawUrl : rawUrl.substring(0, fragmentIndex);
    final fragment =
        fragmentIndex < 0 ? '' : rawUrl.substring(fragmentIndex);
    final queryIndex = beforeFragment.indexOf('?');
    final base =
        queryIndex < 0 ? beforeFragment : beforeFragment.substring(0, queryIndex);
    final query =
        queryIndex < 0 ? '' : beforeFragment.substring(queryIndex + 1);
    final parts = query.isEmpty ? <String>[] : query.split('&');
    final encodedValue = Uri.encodeQueryComponent(value);
    var replaced = false;

    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      final equals = part.indexOf('=');
      final rawKey = equals < 0 ? part : part.substring(0, equals);
      String decodedKey;
      try {
        decodedKey = Uri.decodeQueryComponent(rawKey);
      } catch (_) {
        continue;
      }
      if (decodedKey == name) {
        if (!replaced) {
          parts[index] = '$rawKey=$encodedValue';
          replaced = true;
        } else {
          parts.removeAt(index--);
        }
      }
    }
    if (!replaced) {
      parts.add(Uri.encodeQueryComponent(name) + '=$encodedValue');
    }
    return '$base?' + parts.join('&') + fragment;
  }
}
