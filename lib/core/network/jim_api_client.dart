import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  return Dio(
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
});
