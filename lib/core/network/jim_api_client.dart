import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final configErrors = ref
      .watch(appConfigValidationProvider)
      .where((issue) => issue.severity == AppConfigValidationSeverity.error)
      .toList(growable: false);
  if (configErrors.isNotEmpty) {
    throw StateError(
      'JimBro live backend configuration is invalid.\n'
      '${appConfigValidationSummary(configErrors)}',
    );
  }
  final dio = Dio(
    BaseOptions(
      baseUrl: config.normalizedFastApiBaseUrl,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 12),
      contentType: Headers.jsonContentType,
      headers: const {'Accept': 'application/json'},
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(const DevSafeApiLogInterceptor());
  }
  return dio;
});

class DevSafeApiLogInterceptor extends Interceptor {
  const DevSafeApiLogInterceptor();

  static int _requestSequence = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${++_requestSequence}';
    final startedAt = DateTime.now();
    options.extra['jimbro_request_id'] = requestId;
    options.extra['jimbro_request_started_at'] = startedAt;
    options.headers.putIfAbsent('X-Correlation-ID', () => requestId);
    final tokenTiming = _safeTokenTiming(options.headers['Authorization']);
    debugPrint(
      'JimBro API -> request_id=$requestId ${options.method} ${options.path} '
      'environment=${_buildEnvironmentName()} host=${options.uri.host} '
      'authSessionPresent=${options.headers['Authorization'] != null} '
      '${tokenTiming ?? 'tokenExpiry=unknown'} '
      'startedAt=${startedAt.toUtc().toIso8601String()} '
      'queryKeys=${_mapKeys(options.queryParameters)} '
      'payloadShape=${_valueShape(options.data)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    debugPrint(
      'JimBro API <- request_id=${_requestId(options)} '
      'status=${response.statusCode ?? 'unknown'} '
      '${options.method} ${options.path} '
      'durationMs=${_durationMilliseconds(options)} '
      'responseShape=${_valueShape(response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    debugPrint(
      'JimBro API !! request_id=${_requestId(options)} '
      'errorCategory=${err.type.name} '
      'status=${err.response?.statusCode ?? 'none'} '
      '${options.method} ${options.path} '
      'durationMs=${_durationMilliseconds(options)} '
      'responseShape=${_valueShape(err.response?.data)}',
    );
    handler.next(err);
  }
}

String _buildEnvironmentName() {
  if (kReleaseMode) {
    return 'release';
  }
  if (kProfileMode) {
    return 'profile';
  }
  return 'debug';
}

String _requestId(RequestOptions options) {
  return options.extra['jimbro_request_id']?.toString() ?? 'unknown';
}

int _durationMilliseconds(RequestOptions options) {
  final startedAt = options.extra['jimbro_request_started_at'];
  if (startedAt is! DateTime) {
    return -1;
  }
  return DateTime.now().difference(startedAt).inMilliseconds;
}

String? _safeTokenTiming(Object? authorization) {
  final value = authorization?.toString() ?? '';
  if (!value.startsWith('Bearer ')) {
    return null;
  }
  final token = value.substring('Bearer '.length);
  final segments = token.split('.');
  if (segments.length != 3) {
    return null;
  }
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
    );
    if (payload is! Map || payload['exp'] is! num) {
      return null;
    }
    final expirySeconds = (payload['exp'] as num).toInt();
    final expiry = DateTime.fromMillisecondsSinceEpoch(
      expirySeconds * 1000,
      isUtc: true,
    );
    final remaining =
        expirySeconds - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return 'tokenExpiry=${expiry.toIso8601String()} '
        'tokenSecondsRemaining=$remaining';
  } catch (_) {
    return null;
  }
}

String _valueShape(Object? value) {
  if (value is Map) {
    return 'map(keys=${_mapKeys(value)})';
  }
  if (value is Iterable) {
    return 'list(length=${value.length})';
  }
  return value == null ? 'none' : value.runtimeType.toString();
}

List<String> _mapKeys(Map<dynamic, dynamic> map) {
  return map.keys.map((key) => key.toString()).toList(growable: false);
}
