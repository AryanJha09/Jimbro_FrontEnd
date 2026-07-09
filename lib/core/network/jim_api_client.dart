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
      'queryKeys=${_mapKeys(options.queryParameters)} '
      'payloadShape=${_valueShape(options.data)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    debugPrint(
      'JimBro API <- ${response.statusCode ?? 'unknown'} '
      '${response.requestOptions.method} ${response.requestOptions.path} '
      'responseShape=${_valueShape(response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
      'JimBro API !! ${err.response?.statusCode ?? err.type.name} '
      '${err.requestOptions.method} ${err.requestOptions.path} '
      'responseShape=${_valueShape(err.response?.data)}',
    );
    handler.next(err);
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
