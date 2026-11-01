import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/youtube/nsig_decipher_service.dart';
import 'package:muziinap/services/youtube/player_js_service.dart';
import 'package:muziinap/services/youtube/player_script_cache.dart';
import 'package:muziinap/services/youtube/signature_decipher_service.dart';
import 'package:muziinap/services/youtube/stream_url_decipherer.dart';
import 'package:youtube_explode_dart/js_challenge.dart';

class _FakeExecutor implements PlayerJavaScriptExecutor {
  _FakeExecutor(this.values);

  final Map<(JSChallengeType, String), String?> values;
  final Map<(JSChallengeType, String), int> calls = {};

  @override
  Future<String?> solve(Uri playerUrl, JSChallengeType type, String challenge) async {
    calls.update((type, challenge), (count) => count + 1, ifAbsent: () => 1);
    return values[(type, challenge)];
  }
}

void main() {
  const player = 'https://www.youtube.com/s/player/player-v1/player_ias.vflset/en_US/base.js';

  group('PlayerScriptCache', () {
    test('reuses the same player script for the same player version', () async {
      var downloads = 0;
      final cache = PlayerScriptCache(
        fetcher: (_) async {
          downloads++;
          return 'function playerTransform(value) { return value.split("").reverse().join(""); }';
        },
      );
      final first = await cache.get(Uri.parse(player));
      final second = await cache.get(Uri.parse(player));

      expect(first.source, second.source);
      expect(downloads, 1);
      expect(cache.cachedScriptCount, 1);
    });

    test('uses a new cache key when the player version changes', () async {
      var downloads = 0;
      final cache = PlayerScriptCache(
        fetcher: (_) async {
          downloads++;
          return 'function playerTransform(value) { return value.split("").reverse().join(""); }';
        },
      );
      await cache.get(Uri.parse(player));
      await cache.get(Uri.parse(
        'https://www.youtube.com/s/player/player-v2/player_ias.vflset/en_US/base.js',
      ));

      expect(downloads, 2);
    });

    test('shares concurrent downloads for the same player script', () async {
      var downloads = 0;
      final gate = Completer<String>();
      final cache = PlayerScriptCache(
        fetcher: (_) {
          downloads++;
          return gate.future;
        },
      );
      final first = cache.get(Uri.parse(player));
      final second = cache.get(Uri.parse(player));
      gate.complete('function playerTransform(value) { return value; }');

      await Future.wait([first, second]);
      expect(downloads, 1);
    });

    test('rejects invalid player JavaScript and untrusted hosts', () async {
      final cache = PlayerScriptCache(fetcher: (_) async => 'not javascript');
      await expectLater(cache.get(Uri.parse(player)), throwsFormatException);
      await expectLater(
        cache.get(Uri.parse('https://evil.example/player.js')),
        throwsFormatException,
      );
    });
  });

  group('StreamUrlDecipherer', () {
    late _FakeExecutor executor;
    late StreamUrlDecipherer decipherer;

    setUp(() {
      executor = _FakeExecutor({
        (JSChallengeType.n, 'throttled'): 'unthrottled',
        (JSChallengeType.sig, 'encrypted-signature'): 'decrypted-signature',
        (JSChallengeType.sig, 'encrypted'): 'decoded',
      });
      decipherer = StreamUrlDecipherer(
        nsig: NsigDecipherService(executor),
        signature: SignatureDecipherService(executor),
      );
    });

    test('keeps a direct URL without n unchanged', () async {
      const url = 'https://media.example/audio?itag=140&expire=1900000000';
      final result = await decipherer.decipherFormats([
        {'itag': 140, 'url': url},
      ]);

      expect(result.single['url'], url);
    });

    test('deciphers n and preserves unrelated query parameters', () async {
      const url = 'https://media.example/audio?expire=1900000000&itag=140&n=throttled&cpn=nonce&pot=proof';
      final result = await decipherer.decipherFormats(
        [
          {'itag': 140, 'url': url},
        ],
        playerUrl: Uri.parse(player),
      );

      final resolved = Uri.parse(result.single['url'] as String);
      expect(resolved.queryParameters['n'], 'unthrottled');
      expect(resolved.queryParameters['expire'], '1900000000');
      expect(resolved.queryParameters['itag'], '140');
      expect(resolved.queryParameters['cpn'], 'nonce');
      expect(resolved.queryParameters['pot'], 'proof');
    });

    test('rejects an invalid n decipher output but preserves sibling candidates', () async {
      final broken = _FakeExecutor({
        (JSChallengeType.n, 'bad'): 'bad',
      });
      final resolver = StreamUrlDecipherer(
        nsig: NsigDecipherService(broken),
        signature: SignatureDecipherService(broken),
      );
      final result = await resolver.decipherFormats(
        [
          {'itag': 140, 'url': 'https://media.example/audio?n=bad'},
          {'itag': 251, 'url': 'https://media.example/audio?itag=251'},
        ],
        playerUrl: Uri.parse(player),
      );

      expect(result, hasLength(1));
      expect(result.single['itag'], 251);
    });

    test('rejects n-protected candidates when player JavaScript is missing', () async {
      final result = await decipherer.decipherFormats([
        {'itag': 140, 'url': 'https://media.example/audio?n=throttled'},
        {'itag': 251, 'url': 'https://media.example/audio?itag=251'},
      ]);

      expect(result, hasLength(1));
      expect(result.single['itag'], 251);
    });

    test('deciphers signatureCipher and applies sp parameter', () async {
      final cipher = Uri(
        queryParameters: {
          'url': 'https://media.example/audio?itag=140&expire=1900000000',
          's': 'encrypted-signature',
          'sp': 'lsig',
        },
      ).query;
      final result = await decipherer.decipherFormats(
        [
          {'itag': 140, 'signatureCipher': cipher},
        ],
        playerUrl: Uri.parse(player),
      );

      final url = Uri.parse(result.single['url'] as String);
      expect(url.queryParameters['lsig'], 'decrypted-signature');
      expect(url.queryParameters['itag'], '140');
      expect(url.queryParameters['expire'], '1900000000');
      expect(result.single.containsKey('signatureCipher'), isFalse);
    });

    test('supports the legacy cipher field', () async {
      final cipher = Uri(
        queryParameters: {
          'url': 'https://media.example/audio?itag=140',
          's': 'encrypted',
          'sp': 'signature',
        },
      ).query;
      final result = await decipherer.decipherFormats(
        [
          {'itag': 140, 'cipher': cipher},
        ],
        playerUrl: Uri.parse(player),
      );

      expect(
        Uri.parse(result.single['url'] as String).queryParameters['signature'],
        'decoded',
      );
    });

    test('rejects signature candidates when player JavaScript is missing', () async {
      final cipher = Uri(queryParameters: {
        'url': 'https://media.example/audio',
        's': 'encrypted-signature',
        'sp': 'signature',
      }).query;
      final result = await decipherer.decipherFormats([
        {'itag': 140, 'signatureCipher': cipher},
      ]);

      expect(result, isEmpty);
    });

    test('preserves existing signed URL components while replacing n', () async {
      const url = 'https://media.example/audio?expire=1900000000&sig=a%2Fb&n=throttled&cpn=x%2By';
      final result = await decipherer.decipherFormats(
        [{'url': url, 'itag': 140}],
        playerUrl: Uri.parse(player),
      );

      final output = result.single['url'] as String;
      expect(output, contains('sig=a%2Fb'));
      expect(output, contains('cpn=x%2By'));
      expect(output, contains('expire=1900000000'));
      expect(Uri.parse(output).queryParameters['n'], 'unthrottled');
    });

    test('coalesces concurrent identical decipher challenges', () async {
      final gate = Completer<String?>();
      final slowExecutor = _CompletingExecutor(gate);
      final resolver = StreamUrlDecipherer(
        nsig: NsigDecipherService(slowExecutor),
        signature: SignatureDecipherService(slowExecutor),
      );
      final input = [
        {'url': 'https://media.example/audio?n=throttled', 'itag': 140},
      ];
      final first = resolver.decipherFormats(input, playerUrl: Uri.parse(player));
      final second = resolver.decipherFormats(input, playerUrl: Uri.parse(player));
      await Future<void>.delayed(Duration.zero);
      gate.complete('unthrottled');

      final results = await Future.wait([first, second]);
      expect(slowExecutor.calls, 1);
      expect(results.every((value) => value.single['url'].toString().contains('n=unthrottled')), isTrue);
    });

    test('does not silently accept an undeciphered signature', () async {
      final broken = _FakeExecutor({
        (JSChallengeType.sig, 'encrypted-signature'): 'encrypted-signature',
      });
      final resolver = StreamUrlDecipherer(
        nsig: NsigDecipherService(broken),
        signature: SignatureDecipherService(broken),
      );
      final cipher = Uri(queryParameters: {
        'url': 'https://media.example/audio',
        's': 'encrypted-signature',
      }).query;

      expect(
        await resolver.decipherFormats(
          [{'signatureCipher': cipher}],
          playerUrl: Uri.parse(player),
        ),
        isEmpty,
      );
    });
  });
}

class _CompletingExecutor implements PlayerJavaScriptExecutor {
  _CompletingExecutor(this.gate);

  final Completer<String?> gate;
  int calls = 0;

  @override
  Future<String?> solve(Uri playerUrl, JSChallengeType type, String challenge) {
    calls++;
    return gate.future;
  }
}
