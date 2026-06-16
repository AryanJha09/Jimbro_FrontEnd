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
      baseUrl: config.fastApiBaseUrl,
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

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint(
      'JimBro API -> ${options.method} ${options.path} '
      'query=${_redactMap(options.queryParameters)} '
      'payload=${_redactValue(options.data)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    debugPrint(
      'JimBro API <- ${response.statusCode ?? 'unknown'} '
      '${response.requestOptions.method} ${response.requestOptions.path} '
      'body=${_redactValue(response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
      'JimBro API !! ${err.response?.statusCode ?? err.type.name} '
      '${err.requestOptions.method} ${err.requestOptions.path} '
      'body=${_redactValue(err.response?.data)}',
    );
    handler.next(err);
  }
}

Object? _redactValue(Object? value) {
  if (value is Map) {
    return _redactMap(value);
  }
  if (value is Iterable) {
    return value.map(_redactValue).toList(growable: false);
  }
  return value;
}

Map<String, Object?> _redactMap(Map<dynamic, dynamic> map) {
  return map.map((key, value) {
    final name = key.toString();
    final normalized = name.toLowerCase();
    final sensitive = normalized.contains('password') ||
        normalized.contains('token') ||
        normalized.contains('authorization') ||
        normalized.contains('secret') ||
        normalized.contains('key');
    return MapEntry(name, sensitive ? '<redacted>' : _redactValue(value));
  });
}
