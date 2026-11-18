import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/supporters_api_service.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final String body;
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    request = options;
    return ResponseBody.fromString(body, status, headers: {Headers.contentTypeHeader: ['application/json']});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  test('GET 200 returns snapshot over HTTPS', () async {
    final adapter = _Adapter(200, jsonEncode({'total': 0, 'supporters': <Object>[]}));
    final dio = Dio()..httpClientAdapter = adapter;
    final result = await SupportersApiService(dio: dio).fetchSupporters();
    expect(result.total, 0);
    expect(adapter.request?.method, 'GET');
    expect(adapter.request?.uri.scheme, 'https');
  });

  test('503 is not treated as an empty snapshot', () async {
    final dio = Dio()..httpClientAdapter = _Adapter(503, '{}');
    await expectLater(SupportersApiService(dio: dio).fetchSupporters(),
      throwsA(isA<SupportersException>().having((e) => e.failure, 'failure', SupportersFailure.unavailable)));
  });

  test('405 maps to safe method failure', () async {
    final dio = Dio()..httpClientAdapter = _Adapter(405, '{}');
    await expectLater(SupportersApiService(dio: dio).fetchSupporters(),
      throwsA(isA<SupportersException>().having((e) => e.failure, 'failure', SupportersFailure.methodNotAllowed)));
  });

  test('invalid JSON and response shape are rejected', () async {
    for (final body in ['{broken', '{"total":0}']) {
      final dio = Dio()..httpClientAdapter = _Adapter(200, body);
      await expectLater(SupportersApiService(dio: dio).fetchSupporters(),
        throwsA(isA<SupportersException>().having((e) => e.failure, 'failure', SupportersFailure.invalidResponse)));
    }
  });
}