import 'dart:math' as math;

import 'package:dio/dio.dart';

import 'device_adaptive_stream_selector.dart';

/// Network-aware deadlines shared by the stream resolver and its fallbacks.
/// Successful request latency is sampled per transport and used as a bounded
/// estimate for subsequent tracks; it is not treated as a bandwidth test.
class StreamRequestPolicy {
  const StreamRequestPolicy._();

  static final Map<DeviceNetworkType, int> _latencyEwmaMs = {};

  static Duration _networkBase(DeviceStreamProfile? profile) {
    switch (profile?.networkType ?? DeviceNetworkType.other) {
      case DeviceNetworkType.wifi:
        return const Duration(seconds: 8);
      case DeviceNetworkType.mobile:
        return const Duration(seconds: 15);
      case DeviceNetworkType.offline:
        return const Duration(seconds: 4);
      case DeviceNetworkType.other:
        return const Duration(seconds: 12);
    }
  }

  static void recordLatency(
    DeviceStreamProfile? profile,
    Duration elapsed,
  ) {
    final networkType = profile?.networkType;
    final sample = elapsed.inMilliseconds;
    if (networkType == null ||
        networkType == DeviceNetworkType.offline ||
        sample <= 0) {
      return;
    }
    final previous = _latencyEwmaMs[networkType];
    _latencyEwmaMs[networkType] =
        previous == null ? sample : ((previous * 3) + sample) ~/ 4;
  }

  static Duration _adaptive(
    DeviceStreamProfile? profile,
    Duration base,
  ) {
    final networkType = profile?.networkType ?? DeviceNetworkType.other;
    final observedMs = _latencyEwmaMs[networkType];
    if (observedMs == null || networkType == DeviceNetworkType.offline) {
      return base;
    }
    final maximumMs = switch (networkType) {
      DeviceNetworkType.wifi => const Duration(seconds: 24).inMilliseconds,
      DeviceNetworkType.mobile => const Duration(seconds: 35).inMilliseconds,
      DeviceNetworkType.offline => const Duration(seconds: 4).inMilliseconds,
      DeviceNetworkType.other => const Duration(seconds: 28).inMilliseconds,
    };
    final estimateMs = math.max(
      base.inMilliseconds,
      math.min(maximumMs, observedMs * 3 + 2000),
    ).toInt();
    return Duration(milliseconds: estimateMs);
  }

  static Duration innerTubeTimeout(
    DeviceStreamProfile? profile, {
    required bool isInitialAttempt,
  }) {
    final base = _networkBase(profile);
    return _adaptive(
      profile,
      isInitialAttempt ? base : base + const Duration(seconds: 2),
    );
  }

  static Duration youtubeExplodeTimeout(DeviceStreamProfile? profile) =>
      _adaptive(
        profile,
        _networkBase(profile) + const Duration(seconds: 4),
      );

  static Duration pipedInstanceTimeout(DeviceStreamProfile? profile) =>
      _adaptive(profile, _networkBase(profile));

  static Duration pipedOverallTimeout(DeviceStreamProfile? profile) =>
      _adaptive(
        profile,
        _networkBase(profile) + const Duration(seconds: 4),
      );
}

enum StreamRequestFailureKind {
  timeout,
  cancelled,
  connection,
  http,
  unknown,
}

/// Converts Dio failures into stable, non-secret diagnostics for logs and UI.
class StreamRequestDiagnostic {
  const StreamRequestDiagnostic._();

  static StreamRequestFailureKind classify(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return StreamRequestFailureKind.timeout;
      case DioExceptionType.cancel:
        return StreamRequestFailureKind.cancelled;
      case DioExceptionType.connectionError:
        return StreamRequestFailureKind.connection;
      case DioExceptionType.badResponse:
        return StreamRequestFailureKind.http;
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return StreamRequestFailureKind.unknown;
    }
  }

  static String describe(String provider, DioException error) {
    switch (classify(error)) {
      case StreamRequestFailureKind.timeout:
        final phase = switch (error.type) {
          DioExceptionType.connectionTimeout => 'connection',
          DioExceptionType.sendTimeout => 'send',
          DioExceptionType.receiveTimeout => 'response',
          DioExceptionType.transformTimeout => 'response transform',
          _ => 'request',
        };
        return '$provider: $phase timeout';
      case StreamRequestFailureKind.cancelled:
        return '$provider: request cancelled';
      case StreamRequestFailureKind.connection:
        return '$provider: connection failed';
      case StreamRequestFailureKind.http:
        final status = error.response?.statusCode;
        return '$provider: HTTP ${status ?? 'unknown'}';
      case StreamRequestFailureKind.unknown:
        return '$provider: request failed';
    }
  }
}
