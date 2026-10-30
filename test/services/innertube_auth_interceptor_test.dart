import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:muziinap/services/innertube_auth_interceptor.dart';
import 'package:muziinap/services/innertube_session_manager.dart';

void main() {
  late Directory tempDirectory;
  late Box<dynamic> box;
  late InnerTubeSessionManager sessionManager;

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('innertube_auth_interceptor_');
    Hive.init(tempDirectory.path);
    box = await Hive.openBox<dynamic>('test_preferences');
    sessionManager = InnerTubeSessionManager(box: box);
  });

  tearDown(() async {
    await box.close();
    await Hive.close();
    await tempDirectory.delete(recursive: true);
  });

  test('adds the latest cached cookie and fresh auth headers', () async {
    await sessionManager.storeCookies(
      'SAPISID=latest-secret; SID=session-value',
    );
    RequestOptions? captured;
    final dio = Dio()
      ..httpClientAdapter = _RecordingAdapter((options) {
        captured = options;
        return _response({'ok': true});
      });
    dio.interceptors.add(
      InnerTubeAuthInterceptor(
        sessionManager: sessionManager,
        headersProvider: () => {'x-youtube-client-name': '67'},
        onSessionExpired: (_) async => true,
      ),
    );

    await dio.get('https://music.youtube.com/youtubei/v1/browse');

    expect(captured!.headers['cookie'],
        'SAPISID=latest-secret; SID=session-value');
    expect(captured!.headers['authorization'], startsWith('SAPISIDHASH '));
    expect(captured!.headers['x-youtube-client-name'], '67');
    dio.close();
  });

  test('coalesces concurrent LOGIN_REQUIRED responses into one expiry event',
      () async {
    await sessionManager.storeCookies('SAPISID=active-secret; SID=session');
    var callbackCount = 0;
    final event = Completer<InnerTubeSessionExpiredEvent>();
    final subscription =
        InnerTubeAuthInterceptor.sessionExpiredEvents.listen(event.complete);
    final dio = Dio()
      ..httpClientAdapter = _RecordingAdapter(
        (_) => _response({
          'error': {'code': 'LOGIN_REQUIRED'},
        }),
      );
    dio.interceptors.add(
      InnerTubeAuthInterceptor(
        sessionManager: sessionManager,
        headersProvider: () => const {},
        onSessionExpired: (_) async {
          callbackCount++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return true;
        },
      ),
    );

    await Future.wait([
      dio.get('https://music.youtube.com/youtubei/v1/browse')
          .then<void>((_) {}, onError: (_) {}),
      dio.get('https://music.youtube.com/youtubei/v1/search')
          .then<void>((_) {}, onError: (_) {}),
    ]);
    await event.future.timeout(const Duration(seconds: 1));

    expect(callbackCount, 1);
    await subscription.cancel();
    dio.close();
  });

  test('detects HTTP 403 and ignores unrelated endpoints', () async {
    await sessionManager.storeCookies('SAPISID=active-secret; SID=session');
    var callbackCount = 0;
    final dio = Dio()
      ..httpClientAdapter = _RecordingAdapter(
        (_) => _response({'message': 'Forbidden'}, statusCode: 403),
      );
    dio.interceptors.add(
      InnerTubeAuthInterceptor(
        sessionManager: sessionManager,
        headersProvider: () => const {},
        onSessionExpired: (_) async {
          callbackCount++;
          return true;
        },
      ),
    );

    await dio.get('https://music.youtube.com/youtubei/v1/browse')
        .then<void>((_) {}, onError: (_) {});
    await dio.get('https://music.youtube.com/watch')
        .then<void>((_) {}, onError: (_) {});

    expect(callbackCount, 1);
    dio.close();
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _response(
  Object body, {
  int statusCode = 200,
}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}
