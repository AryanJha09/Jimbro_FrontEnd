import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'profile_schema_exception.dart';

abstract final class AppErrorCode {
  static const authFailed = 'AUTH_FAILED';
  static const authVerificationRequired = 'AUTH_VERIFICATION_REQUIRED';
  static const sessionExpired = 'SESSION_EXPIRED';
  static const provisioningFailed = 'USER_PROVISIONING_FAILED';
  static const validationFailed = 'VALIDATION_FAILED';
  static const invalidDietaryPreference = 'INVALID_DIETARY_PREFERENCE';
  static const networkUnavailable = 'NETWORK_UNAVAILABLE';
  static const requestTimeout = 'REQUEST_TIMEOUT';
  static const requestCancelled = 'REQUEST_CANCELLED';
  static const secureConnectionFailed = 'SECURE_CONNECTION_FAILED';
  static const serverRejectedRequest = 'SERVER_REJECTED_REQUEST';
  static const serverUnavailable = 'SERVER_UNAVAILABLE';
  static const synchronizationFailed = 'SYNCHRONIZATION_FAILED';
  static const mutationConflict = 'MUTATION_CONFLICT';
  static const pendingSync = 'PENDING_SYNC';
  static const malformedResponse = 'MALFORMED_RESPONSE';
  static const profileSchemaInvalid = 'PROFILE_SCHEMA_INVALID';
  static const secureStorageUnavailable = 'SECURE_STORAGE_UNAVAILABLE';
  static const accountDeletionFailed = 'ACCOUNT_DELETION_FAILED';
  static const unknown = 'UNKNOWN_ERROR';
}

class AppErrorDiagnostics {
  const AppErrorDiagnostics({
    this.method,
    this.route,
    this.httpStatus,
    this.correlationId,
    required this.retryable,
  });

  final String? method;
  final String? route;
  final int? httpStatus;
  final String? correlationId;
  final bool retryable;
}

class AppError implements Exception {
  const AppError({
    required this.code,
    required this.userMessage,
    required this.diagnostics,
  });

  final String code;
  final String userMessage;
  final AppErrorDiagnostics diagnostics;

  String publicMessage() {
    final correlationId = _safeCorrelationId(diagnostics.correlationId);
    if (correlationId == null || correlationId.isEmpty) {
      return userMessage;
    }
    return '$userMessage Reference: $correlationId';
  }

  String diagnosticSummary() {
    return <String>[
      'code=$code',
      if (diagnostics.method != null) 'method=${diagnostics.method}',
      if (diagnostics.route != null) 'route=${diagnostics.route}',
      if (diagnostics.httpStatus != null) 'status=${diagnostics.httpStatus}',
      if (diagnostics.correlationId != null)
        'correlation_id=${diagnostics.correlationId}',
      'retryable=${diagnostics.retryable}',
    ].join(' ');
  }

  @override
  String toString() => 'AppError($code)';
}

AppError mapAppError(
  Object error, {
  String fallbackMessage =
      'Something went wrong. Your changes are still here; please try again.',
  String? method,
  String? route,
}) {
  if (error is AppError) {
    return error;
  }
  if (error is DioException) {
    return _mapDioError(
      error,
      fallbackMessage: fallbackMessage,
      method: method,
      route: route,
    );
  }
  if (error is ProfileSchemaException) {
    return _typed(
      AppErrorCode.profileSchemaInvalid,
      'JimBro received profile data in an unexpected format. Retry once. If the problem continues, update the app or contact support.',
      retryable: false,
      method: method,
      route: route,
    );
  }

  final type = error.runtimeType.toString();
  return switch (type) {
    'AuthSessionExpiredException' => _typed(
        AppErrorCode.sessionExpired,
        'Your session expired. Please sign in again.',
        retryable: false,
        method: method,
        route: route,
      ),
    'AuthVerificationRequiredException' => _typed(
        AppErrorCode.authVerificationRequired,
        'Check your email to finish signing up, then sign in.',
        retryable: true,
        method: method,
        route: route,
      ),
    'UserProvisioningException' => _typed(
        AppErrorCode.provisioningFailed,
        'Your account is signed in, but we could not finish creating your JimBro profile.',
        retryable: true,
        method: method,
        route: route,
      ),
    'InvalidDietaryPreferenceException' => _typed(
        AppErrorCode.invalidDietaryPreference,
        'Choose one of the available dietary preferences.',
        retryable: false,
        method: method,
        route: route,
      ),
    'AccountDeletionException' => _typed(
        AppErrorCode.accountDeletionFailed,
        'Unable to delete your account. Please try again.',
        retryable: true,
        method: method,
        route: route,
      ),
    'AtlasProfileSyncException' => _typed(
        AppErrorCode.synchronizationFailed,
        'Your profile is saved, but coaching data could not sync yet.',
        retryable: true,
        method: method,
        route: route,
      ),
    _ => _typed(
        AppErrorCode.unknown,
        fallbackMessage,
        retryable: true,
        method: method,
        route: route,
      ),
  };
}

String presentAppError(
  Object error, {
  String fallbackMessage =
      'Something went wrong. Your changes are still here; please try again.',
  String? method,
  String? route,
}) {
  final mapped = mapAppError(
    error,
    fallbackMessage: fallbackMessage,
    method: method,
    route: route,
  );
  if (kDebugMode) {
    debugPrint('JimBro error: ${mapped.diagnosticSummary()}');
  }
  return mapped.publicMessage();
}

AppError appHttpError({
  required String code,
  required String userMessage,
  required RequestOptions request,
  required int? statusCode,
  required bool retryable,
  String? correlationId,
}) {
  return AppError(
    code: code,
    userMessage: userMessage,
    diagnostics: AppErrorDiagnostics(
      method: request.method,
      route: request.uri.path,
      httpStatus: statusCode,
      correlationId: _safeCorrelationId(correlationId),
      retryable: retryable,
    ),
  );
}

AppError _mapDioError(
  DioException error, {
  required String fallbackMessage,
  String? method,
  String? route,
}) {
  final status = error.response?.statusCode;
  final request = error.requestOptions;
  final resolvedMethod = method ?? request.method;
  final resolvedRoute = route ?? request.uri.path;
  final correlationId = _correlationId(error.response);
  final mapped = switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout =>
      (
        AppErrorCode.requestTimeout,
        'The service took too long to respond. Please try again.',
        true
      ),
    DioExceptionType.connectionError => (
        AppErrorCode.networkUnavailable,
        'JimBro could not reach the service. Check your connection and retry.',
        true
      ),
    DioExceptionType.cancel => (
        AppErrorCode.requestCancelled,
        'The request was cancelled.',
        true
      ),
    DioExceptionType.badCertificate => (
        AppErrorCode.secureConnectionFailed,
        'A secure connection could not be established.',
        false
      ),
    DioExceptionType.badResponse when status == 401 => (
        AppErrorCode.sessionExpired,
        'Your session expired. Please sign in again.',
        false
      ),
    DioExceptionType.badResponse when status == 422 => (
        AppErrorCode.validationFailed,
        'Some information was not accepted. Review it and try again.',
        false
      ),
    DioExceptionType.badResponse when (status ?? 0) >= 500 => (
        AppErrorCode.serverUnavailable,
        'The service is temporarily unavailable. Please try again.',
        true
      ),
    DioExceptionType.badResponse => (
        AppErrorCode.serverRejectedRequest,
        fallbackMessage,
        false
      ),
    DioExceptionType.unknown => (AppErrorCode.unknown, fallbackMessage, true),
  };
  return AppError(
    code: mapped.$1,
    userMessage: mapped.$2,
    diagnostics: AppErrorDiagnostics(
      method: resolvedMethod,
      route: resolvedRoute,
      httpStatus: status,
      correlationId: correlationId,
      retryable: mapped.$3,
    ),
  );
}

AppError _typed(
  String code,
  String message, {
  required bool retryable,
  String? method,
  String? route,
}) {
  return AppError(
    code: code,
    userMessage: message,
    diagnostics: AppErrorDiagnostics(
      method: method,
      route: route,
      retryable: retryable,
    ),
  );
}

String? _correlationId(Response<dynamic>? response) {
  if (response == null) {
    return null;
  }
  for (final name in const [
    'x-correlation-id',
    'x-request-id',
    'request-id',
  ]) {
    final value = response.headers.value(name);
    if (value != null) {
      return _safeCorrelationId(value);
    }
  }
  return null;
}

String? _safeCorrelationId(String? value) {
  final candidate = value?.trim();
  if (candidate == null || candidate.isEmpty) {
    return null;
  }
  if (!RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(candidate)) {
    return null;
  }
  return candidate;
}
