import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/core/errors/app_error.dart';

void main() {
  group('public error boundary', () {
    test('redacts tokens, passwords, and complete profile payloads', () {
      final error = Exception(
        'Bearer secret-token password=hunter2 '
        '{"age":31,"weight_kg":82,"dietary_preference":"vegan"}',
      );

      final message = presentAppError(error);

      expect(message, isNot(contains('secret-token')));
      expect(message, isNot(contains('hunter2')));
      expect(message, isNot(contains('weight_kg')));
      expect(message, isNot(contains('vegan')));
    });

    test('redacts long HTML and SQL-like response bodies', () {
      final request = RequestOptions(
        path: '/profile',
        method: 'POST',
        data: {'password': 'secret'},
      );
      final response = Response<dynamic>(
        requestOptions: request,
        statusCode: 500,
        data: '<html>${'private'.padRight(500, 'x')}</html> '
            'SELECT * FROM public.users',
      );
      final error = DioException.badResponse(
        statusCode: 500,
        requestOptions: request,
        response: response,
      );

      final message = presentAppError(error);

      expect(message, isNot(contains('<html>')));
      expect(message, isNot(contains('SELECT')));
      expect(message, isNot(contains('public.users')));
      expect(message, isNot(contains('password')));
    });

    test('public presentation never contains developer diagnostics', () {
      const error = AppError(
        code: AppErrorCode.serverUnavailable,
        userMessage: 'Please try again.',
        diagnostics: AppErrorDiagnostics(
          method: 'POST',
          route: '/supabase/profile',
          httpStatus: 503,
          retryable: true,
        ),
      );

      expect(error.publicMessage(), 'Please try again.');
      expect(error.publicMessage(), isNot(contains('/supabase/profile')));
      expect(error.publicMessage(), isNot(contains('503')));
    });

    test('displays a validated correlation id without private metadata', () {
      const error = AppError(
        code: AppErrorCode.serverUnavailable,
        userMessage: 'Please try again.',
        diagnostics: AppErrorDiagnostics(
          method: 'GET',
          route: '/supabase/profile',
          httpStatus: 503,
          correlationId: 'req_abc-123',
          retryable: true,
        ),
      );

      expect(error.publicMessage(), 'Please try again. Reference: req_abc-123');
      expect(error.publicMessage(), isNot(contains('/supabase/profile')));
    });

    test('maps known HTTP and network errors to stable codes', () {
      final request = RequestOptions(path: '/workout-logs', method: 'POST');
      final validation = DioException.badResponse(
        statusCode: 422,
        requestOptions: request,
        response: Response<void>(
          requestOptions: request,
          statusCode: 422,
        ),
      );
      final timeout = DioException(
        requestOptions: request,
        type: DioExceptionType.receiveTimeout,
      );

      expect(mapAppError(validation).code, AppErrorCode.validationFailed);
      expect(mapAppError(timeout).code, AppErrorCode.requestTimeout);
    });

    test('uses stable unknown fallback without exposing the exception', () {
      final mapped = mapAppError(
        Exception('/private/source.dart token=secret stack trace'),
      );

      expect(mapped.code, AppErrorCode.unknown);
      expect(mapped.publicMessage(), isNot(contains('/private')));
      expect(mapped.publicMessage(), isNot(contains('secret')));
      expect(mapped.publicMessage(), isNot(contains('stack trace')));
    });

    test('developer diagnostics contain allow-listed metadata only', () {
      const error = AppError(
        code: AppErrorCode.validationFailed,
        userMessage: 'Review the form.',
        diagnostics: AppErrorDiagnostics(
          method: 'POST',
          route: '/supabase/profile',
          httpStatus: 422,
          correlationId: 'request-1',
          retryable: false,
        ),
      );

      expect(
        error.diagnosticSummary(),
        'code=VALIDATION_FAILED method=POST route=/supabase/profile '
        'status=422 correlation_id=request-1 retryable=false',
      );
    });
  });
}
