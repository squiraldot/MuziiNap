import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/youtube/po_token/bgutil_http_po_token_provider.dart';
import 'package:muziinap/services/youtube/po_token/po_token_cache.dart';
import 'package:muziinap/services/youtube/po_token/po_token_manager.dart';
import 'package:muziinap/services/youtube/po_token/po_token_policy.dart';
import 'package:muziinap/services/youtube/po_token/po_token_provider.dart';
import 'package:muziinap/services/youtube/po_token/po_token_request.dart';
import 'package:muziinap/services/youtube/po_token/po_token_result.dart';

class FakeProvider implements PoTokenProvider {
  FakeProvider({this.delay = Duration.zero, this.failure = false});

  final Duration delay;
  final bool failure;
  int calls = 0;

  @override
  String get id => 'fake';

  @override
  bool supports(PoTokenRequest request) => request.clientName == 'WEB_REMIX';

  @override
  Future<PoTokenResult?> getToken(PoTokenRequest request) async {
    calls++;
    await Future<void>.delayed(delay);
    if (failure) throw StateError('simulated provider failure');
    return PoTokenResult(
      token: 'test-token-${request.videoId}',
      providerId: id,
      clientName: request.clientName,
      clientVersion: request.clientVersion,
      videoId: request.videoId,
      visitorData: request.visitorData,
      sessionId: request.sessionId,
      binding: request.binding,
      bindingValue: request.bindingValue!,
      purpose: request.purpose,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

PoTokenRequest request({
  String videoId = 'video-a',
  String clientName = 'WEB_REMIX',
  PoTokenPurpose purpose = PoTokenPurpose.player,
  PoTokenBinding binding = PoTokenBinding.video,
  String visitorData = 'visitor-a',
}) =>
    PoTokenRequest(
      clientName: clientName,
      clientVersion: '1.0',
      videoId: videoId,
      visitorData: visitorData,
      purpose: purpose,
      binding: binding,
    );

void main() {
  group('PoTokenManager', () {
    test('retrieves a valid token from a provider', () async {
      final manager = PoTokenManager(provider: FakeProvider());
      final result = await manager.getToken(request());
      expect(result?.token, 'test-token-video-a');
      expect(result?.isValidFor(request()), isTrue);
    });

    test('returns a cached token for an identical binding', () async {
      final provider = FakeProvider();
      final manager = PoTokenManager(provider: provider);
      await manager.getToken(request());
      await manager.getToken(request());
      expect(provider.calls, 1);
    });

    test('expires cache entries instead of reusing them', () {
      final cache = PoTokenCache();
      final req = request();
      final expired = PoTokenResult(
        token: 'expired',
        providerId: 'fake',
        clientName: req.clientName,
        videoId: req.videoId,
        binding: req.binding,
        bindingValue: req.bindingValue!,
        purpose: req.purpose,
        expiresAt: DateTime.utc(2020),
      );
      cache.put(req, expired);
      expect(cache.get(req, now: DateTime.utc(2021)), isNull);
    });

    test('refreshes after an expired token has been invalidated', () async {
      final provider = FakeProvider();
      final manager = PoTokenManager(provider: provider);
      final req = request();
      await manager.getToken(req);
      manager.invalidate(req);
      await manager.getToken(req);
      expect(provider.calls, 2);
    });

    test('never reuses a video-bound token for another video', () async {
      final provider = FakeProvider();
      final manager = PoTokenManager(provider: provider);
      final first = await manager.getToken(request(videoId: 'one'));
      final second = await manager.getToken(request(videoId: 'two'));
      expect(first?.token, isNot(second?.token));
      expect(provider.calls, 2);
    });

    test('reuses visitor-bound tokens across videos in the same session', () async {
      final provider = FakeProvider();
      final manager = PoTokenManager(provider: provider);
      final first = await manager.getToken(
        request(videoId: 'one', binding: PoTokenBinding.visitor),
      );
      final second = await manager.getToken(
        request(videoId: 'two', binding: PoTokenBinding.visitor),
      );
      expect(second?.token, first?.token);
      expect(provider.calls, 1);
    });

    test('isolates tokens by visitor session identity', () async {
      final provider = FakeProvider();
      final manager = PoTokenManager(provider: provider);
      await manager.getToken(request(visitorData: 'visitor-one'));
      await manager.getToken(request(visitorData: 'visitor-two'));
      expect(provider.calls, 2);
    });

    test('isolates tokens by client version', () async {
      final provider = FakeProvider();
      final manager = PoTokenManager(provider: provider);
      await manager.getToken(request());
      await manager.getToken(request(clientVersion: '2.0'));
      expect(provider.calls, 2);
    });

    test('isolates tokens by client identity', () async {
      final provider = FakeProvider();
      final manager = PoTokenManager(provider: provider);
      await manager.getToken(request());
      await manager.getToken(request(clientName: 'ANDROID'));
      expect(provider.calls, 1);
    });

    test('deduplicates concurrent generation for the same key', () async {
      final provider = FakeProvider(delay: const Duration(milliseconds: 10));
      final manager = PoTokenManager(provider: provider);
      final results = await Future.wait([
        manager.getToken(request()),
        manager.getToken(request()),
        manager.getToken(request()),
      ]);
      expect(provider.calls, 1);
      expect(results.every((result) => result?.token == results.first?.token),
          isTrue);
    });

    test('returns unavailable when provider does not support a request', () async {
      final manager = PoTokenManager(provider: const UnavailablePoTokenProvider());
      expect(await manager.getToken(request()), isNull);
    });

    test('does not throw when token generation fails', () async {
      final manager = PoTokenManager(provider: FakeProvider(failure: true));
      expect(await manager.getToken(request()), isNull);
    });

    test('rejects a token returned for the wrong binding', () async {
      final wrong = _WrongBindingProvider();
      final manager = PoTokenManager(provider: wrong);
      expect(await manager.getToken(request()), isNull);
    });
  });

  group('Provider and policy boundaries', () {
    test('BgUtils adapter rejects non-Web clients and SABR', () {
      final provider = BgutilHttpPoTokenProvider(
        baseUrl: 'https://pot.example.test',
      );
      expect(provider.supports(request()), isTrue);
      expect(provider.supports(request(clientName: 'ANDROID')), isFalse);
      expect(
        provider.supports(request(purpose: PoTokenPurpose.sabr)),
        isFalse,
      );
    });

    test('includes visitorData in the upstream InnerTube context', () {
      final context = request(visitorData: 'visitor-123').innertubeContext;
      expect(
        (context['client'] as Map<String, dynamic>)['visitorData'],
        'visitor-123',
      );
    });

    test('places a Player token only in serviceIntegrityDimensions', () {
      const policy = PoTokenPolicy();
      final body = policy.attachPlayerToken({'videoId': 'video-a'}, 'real-token');
      expect(body['serviceIntegrityDimensions'], {'poToken': 'real-token'});
      expect(body.containsKey('poToken'), isFalse);
      expect(policy.attachPlayerToken({'videoId': 'video-a'}, null),
          {'videoId': 'video-a'});
    });

    test('does not classify a generic HTTP 403 as a PO Token error', () {
      const policy = PoTokenPolicy();
      expect(policy.isGenericHttpForbidden(403), isTrue);
      expect(policy.purposeRequiredByPlayerReason('Forbidden'), isNull);
      expect(policy.purposeRequiredByPlayerReason('HTTP 403'), isNull);
    });

    test('recognizes explicit player PO Token requirements only', () {
      const policy = PoTokenPolicy();
      expect(
        policy.purposeRequiredByPlayerReason('PO_TOKEN_REQUIRED'),
        PoTokenPurpose.player,
      );
      expect(
        policy.purposeRequiredByPlayerReason('Proof-of-origin token required'),
        PoTokenPurpose.player,
      );
    });
  });
}

class _WrongBindingProvider implements PoTokenProvider {
  @override
  String get id => 'wrong-binding';

  @override
  bool supports(PoTokenRequest request) => true;

  @override
  Future<PoTokenResult?> getToken(PoTokenRequest request) async =>
      PoTokenResult(
        token: 'wrong-binding-token',
        providerId: id,
        clientName: request.clientName,
        clientVersion: request.clientVersion,
        videoId: request.videoId,
        visitorData: request.visitorData,
        sessionId: request.sessionId,
        binding: request.binding,
        bindingValue: 'another-video',
        purpose: request.purpose,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
}
