import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  test('DELETE /account uses bearer auth and sends no body', () async {
    final adapter = _AccountDeleteAdapter(
      statusCode: 200,
      responseBody: '{"success":true,"data":{"deleted":true}}',
    );
    final repository = FastApiAccountRepository(_dio(adapter));

    final result = await repository.deleteAccount(_session);

    expect(result.deleted, isTrue);
    expect(adapter.requestOptions?.method, 'DELETE');
    expect(adapter.requestOptions?.uri.path, '/api/v1/account');
    expect(adapter.requestOptions?.headers['Authorization'], 'Bearer token');
    expect(adapter.requestOptions?.headers['Accept'], 'application/json');
    expect(adapter.requestOptions?.data, isNull);
    expect(adapter.requestBody, isEmpty);
  });

  test('standard HTTP 200 response is treated as success', () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 200,
          responseBody: '{"success":true,"data":{"deleted":true}}',
        ),
      ),
    );

    final result = await repository.deleteAccount(_session);

    expect(result.deleted, isTrue);
    expect(result.alreadyDeleted, isFalse);
  });

  test('HTTP 200 already_deleted response is treated as success', () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 200,
          responseBody:
              '{"success":true,"data":{"deleted":true,"already_deleted":true}}',
        ),
      ),
    );

    final result = await repository.deleteAccount(_session);

    expect(result.deleted, isTrue);
    expect(result.alreadyDeleted, isTrue);
  });

  test('HTTP 401 is treated as failure', () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 401,
          responseBody: '{"success":false,"error":{"code":"unauthorized"}}',
        ),
      ),
    );

    await expectLater(
      repository.deleteAccount(_session),
      throwsA(isA<AccountDeletionException>()),
    );
  });

  test('HTTP 500 is treated as failure', () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 500,
          responseBody: '{"success":false}',
        ),
      ),
    );

    await expectLater(
      repository.deleteAccount(_session),
      throwsA(isA<AccountDeletionException>()),
    );
  });

  test('network failure is treated as failure', () async {
    final repository = FastApiAccountRepository(
      _dio(_AccountDeleteAdapter.networkFailure()),
    );

    await expectLater(
      repository.deleteAccount(_session),
      throwsA(isA<AccountDeletionException>()),
    );
  });

  test('malformed HTTP 200 response is treated as failure', () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 200,
          responseBody: '{"success":true,"data":{}}',
        ),
      ),
    );

    await expectLater(
      repository.deleteAccount(_session),
      throwsA(isA<AccountDeletionException>()),
    );
  });
}

const _session = AuthSession(
  userId: 'user-1',
  displayName: 'Test User',
  email: 'test@example.com',
  accessToken: 'token',
  provider: 'fastapi',
);

Dio _dio(HttpClientAdapter adapter) {
  return Dio(
    BaseOptions(
      baseUrl: 'https://api.example.test/api/v1',
      headers: const {'Accept': 'application/json'},
      validateStatus: (status) => status != null && status < 500,
    ),
  )..httpClientAdapter = adapter;
}

class _AccountDeleteAdapter implements HttpClientAdapter {
  _AccountDeleteAdapter({
    required this.statusCode,
    required this.responseBody,
  }) : throwNetworkFailure = false;

  _AccountDeleteAdapter.networkFailure()
      : statusCode = 0,
        responseBody = '',
        throwNetworkFailure = true;

  final int statusCode;
  final String responseBody;
  final bool throwNetworkFailure;

  RequestOptions? requestOptions;
  String requestBody = '';

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestOptions = options;
    final bodyBytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bodyBytes.addAll(chunk);
      }
    }
    requestBody = utf8.decode(bodyBytes);
    if (throwNetworkFailure) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }
    return ResponseBody.fromString(
      responseBody,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
