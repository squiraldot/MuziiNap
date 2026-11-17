import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/supporter.dart';

const supportersEndpoint = 'https://muziinap-site.vercel.app/api/supporters';

enum SupportersFailure { unavailable, methodNotAllowed, network, timeout, invalidResponse, server }

class SupportersException implements Exception {
  const SupportersException(this.failure);
  final SupportersFailure failure;
  String get userMessage {
    switch (failure) {
      case SupportersFailure.unavailable: return 'Supporters are temporarily unavailable. Please try again soon.';
      case SupportersFailure.methodNotAllowed: return 'Supporters could not be loaded right now.';
      case SupportersFailure.network: return 'No internet connection. Check your connection and retry.';
      case SupportersFailure.timeout: return 'The supporters request took too long. Please retry.';
      case SupportersFailure.invalidResponse: return 'Supporter information could not be read safely.';
      case SupportersFailure.server: return 'Could not load supporters. Please try again.';
    }
  }
}

class SupportersApiService {
  SupportersApiService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 10),
    responseType: ResponseType.plain,
    headers: const {'Accept': 'application/json'},
    validateStatus: (status) => status != null,
  ));
  final Dio _dio;

  Future<SupportersResponse> fetchSupporters({CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get<String>(
        supportersEndpoint,
        cancelToken: cancelToken,
        options: Options(
          method: 'GET',
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null,
        ),
      );
      if (response.statusCode == 503) throw const SupportersException(SupportersFailure.unavailable);
      if (response.statusCode == 405) throw const SupportersException(SupportersFailure.methodNotAllowed);
      if (response.statusCode != 200) throw const SupportersException(SupportersFailure.server);
      final body = response.data;
      if (body == null) throw const SupportersException(SupportersFailure.invalidResponse);
      final Object? decoded;
      try { decoded = jsonDecode(body); } on FormatException {
        throw const SupportersException(SupportersFailure.invalidResponse);
      }
      try { return SupportersResponse.fromJson(decoded); } on FormatException {
        throw const SupportersException(SupportersFailure.invalidResponse);
      }
    } on SupportersException {
      rethrow;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        throw const SupportersException(SupportersFailure.timeout);
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.unknown) {
        throw const SupportersException(SupportersFailure.network);
      }
      throw const SupportersException(SupportersFailure.server);
    } catch (_) {
      throw const SupportersException(SupportersFailure.invalidResponse);
    }
  }
}