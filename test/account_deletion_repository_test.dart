import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/core/errors/app_error.dart';
import 'package:jimbro/core/errors/profile_schema_exception.dart';
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

  test('HTTP 401 is surfaced as expired authentication', () async {
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
      throwsA(isA<AuthSessionExpiredException>()),
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

  test('profile bootstrap confirms the application user from bearer auth',
      () async {
    final adapter = _AccountDeleteAdapter(
      statusCode: 200,
      responseBody:
          '{"success":true,"data":{"user_id":"app-user-1","reconciled":true,"username":"Test User","dietary_preference":"vegetarian","onboarding_completed":true}}',
    );
    final repository = FastApiAccountRepository(_dio(adapter));

    final result = await repository.provisionAuthenticatedUser(_session);

    expect(result.applicationUserId, 'app-user-1');
    expect(result.reconciled, isTrue);
    expect(result.profile?.name, 'Test User');
    expect(result.profile?.dietaryPreference, 'vegetarian');
    expect(result.onboardingCompleted, isTrue);
    expect(adapter.requestOptions?.method, 'GET');
    expect(adapter.requestOptions?.uri.path, '/api/v1/supabase/profile');
    expect(adapter.requestOptions?.headers['Authorization'], 'Bearer token');
    expect(adapter.requestOptions?.data, isNull);
  });

  test('profile bootstrap explicitly rejects undocumented nested profile data',
      () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 200,
          responseBody:
              '{"success":true,"data":{"user":{"id":"app-user-1","username":"New User","onboarding_completed":false}}}',
        ),
      ),
    );

    await expectLater(
      repository.provisionAuthenticatedUser(_session),
      throwsA(
        isA<ProfileSchemaException>()
            .having(
              (error) => error.stage,
              'stage',
              ProfileProcessingStage.dtoParsing,
            )
            .having(
              (error) => error.dataKeys,
              'data keys',
              contains('user'),
            ),
      ),
    );
  });

  test('profile mapper receives data rather than the outer wrapper', () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 200,
          responseBody:
              '{"success":true,"username":"Outer Wrapper","data":{"user_id":"app-user-1","username":"Inner Profile","dietary_preference":"omnivore","onboarding_completed":false}}',
        ),
      ),
    );

    final result = await repository.provisionAuthenticatedUser(_session);

    expect(result.profile?.name, 'Inner Profile');
    expect(result.onboardingCompleted, isFalse);
  });

  test('incomplete profile accepts blank optional onboarding fields', () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 200,
          responseBody:
              '{"success":true,"data":{"user_id":"app-user-1","username":null,"dietary_preference":null,"activity_level":null,"constraints_json":null,"onboarding_completed":false}}',
        ),
      ),
    );

    final result = await repository.provisionAuthenticatedUser(_session);

    expect(result.applicationUserId, 'app-user-1');
    expect(result.profile?.dietaryPreference, isNull);
    expect(result.profile?.activityLevel, isNull);
    expect(result.profileDto?.constraintsJson, isNull);
    expect(result.onboardingCompleted, isFalse);
  });

  test('profile bootstrap rejects HTTP 200 success false', () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 200,
          responseBody:
              '{"success":false,"data":{"user_id":"app-user-1","dietary_preference":"omnivore","onboarding_completed":false}}',
        ),
      ),
    );

    await expectLater(
      repository.provisionAuthenticatedUser(_session),
      throwsA(
        isA<AppError>().having(
          (error) => error.code,
          'code',
          AppErrorCode.serverRejectedRequest,
        ),
      ),
    );
  });

  test('profile network failure preserves the Dio error category', () async {
    final repository = FastApiAccountRepository(
      _dio(_AccountDeleteAdapter.networkFailure()),
    );

    await expectLater(
      repository.provisionAuthenticatedUser(_session),
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.connectionError,
        ),
      ),
    );
  });

  test('profile timeout does not trigger token refresh', () async {
    final adapter = _TimeoutAdapter();
    var tokenCalls = 0;
    final repository = FastApiAccountRepository(
      _dio(adapter),
      tokenProvider: () async {
        tokenCalls++;
        return 'current-token';
      },
    );

    await expectLater(
      repository.provisionAuthenticatedUser(_supabaseSession),
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );

    expect(tokenCalls, 1);
    expect(adapter.calls, 1);
  });

  test('profile bootstrap rejects null or malformed wrapped data', () async {
    for (final body in const [
      '{"success":true,"data":null}',
      '{"success":true,"data":"not-a-profile"}',
    ]) {
      final repository = FastApiAccountRepository(
        _dio(
          _AccountDeleteAdapter(statusCode: 200, responseBody: body),
        ),
      );

      await expectLater(
        repository.provisionAuthenticatedUser(_session),
        throwsA(isA<ProfileSchemaException>()),
      );
    }
  });

  test('profile bootstrap blocks when no application user id is returned',
      () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 200,
          responseBody: '{"success":true,"data":{"username":"Test"}}',
        ),
      ),
    );

    await expectLater(
      repository.provisionAuthenticatedUser(_session),
      throwsA(isA<ProfileSchemaException>()),
    );
  });

  test('profile bootstrap rejects an invalid provisional preference', () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 200,
          responseBody:
              '{"success":true,"data":{"user_id":"app-user-1","dietary_preference":"invalid","onboarding_completed":false}}',
        ),
      ),
    );

    await expectLater(
      repository.provisionAuthenticatedUser(_session),
      throwsA(
        isA<ProfileSchemaException>()
            .having(
              (error) => error.stage,
              'stage',
              ProfileProcessingStage.dtoParsing,
            )
            .having(
              (error) => error.exceptionType,
              'original exception',
              'FormatException',
            ),
      ),
    );
  });

  test('missing onboarding flag is an incomplete profile, not a decode error',
      () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 200,
          responseBody:
              '{"success":true,"data":{"user_id":"app-user-1","dietary_preference":"omnivore"}}',
        ),
      ),
    );

    final result = await repository.provisionAuthenticatedUser(_session);

    expect(result.onboardingCompleted, isFalse);
    expect(result.profileDto?.onboardingCompleted, isNull);
  });

  test('constraints_json list is retained by the typed profile DTO', () async {
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 200,
          responseBody:
              '{"success":true,"data":{"user_id":"app-user-1","constraints_json":["knee_sensitive"],"onboarding_completed":false}}',
        ),
      ),
    );

    final result = await repository.provisionAuthenticatedUser(_session);

    expect(result.profileDto?.constraintsJson, ['knee_sensitive']);
    expect(result.onboardingCompleted, isFalse);
  });

  test('nullable profile fields can be written to and read from local cache',
      () async {
    final adapter = _AccountDeleteAdapter(
      statusCode: 200,
      responseBody:
          '{"success":true,"data":{"user_id":"app-user-1","dietary_preference":null,"activity_level":null,"constraints_json":null,"onboarding_completed":false}}',
    );
    final repository = FastApiProfileRepository(
      _dio(adapter),
      MockProfileRepository(),
    );

    final first = await repository.loadProfile(_session);
    final second = await repository.loadProfile(_session);

    expect(first.dietaryPreference, isNull);
    expect(first.activityLevel, isNull);
    expect(second.dietaryPreference, isNull);
    expect(adapter.fetchCalls, 1);
  });

  test('decode diagnostics retain stage and type without private values',
      () async {
    final previousDebugPrint = debugPrint;
    final messages = <String>[];
    debugPrint = (message, {wrapWidth}) {
      if (message != null) {
        messages.add(message);
      }
    };
    addTearDown(() => debugPrint = previousDebugPrint);
    final repository = FastApiAccountRepository(
      _dio(
        _AccountDeleteAdapter(
          statusCode: 200,
          responseBody:
              '{"success":true,"data":{"user_id":"private-user-id","email":"private@example.com","username":"Private Name","dietary_preference":"private-health-value","onboarding_completed":false}}',
        ),
      ),
    );

    ProfileSchemaException? captured;
    try {
      await repository.provisionAuthenticatedUser(_session);
    } on ProfileSchemaException catch (error) {
      captured = error;
    }

    expect(captured, isNotNull);
    expect(captured?.stage, ProfileProcessingStage.dtoParsing);
    expect(captured?.exceptionType, 'FormatException');
    expect(captured?.stackTrace.toString(), isNotEmpty);
    expect(captured?.topLevelKeys, ['data', 'success']);
    expect(captured?.dataKeys, containsAll(['email', 'user_id']));
    expect(captured?.fieldShapes['email'], 'String');
    final log = messages.join('\n');
    expect(log, contains('stage=dtoParsing'));
    expect(log, contains('exceptionType=FormatException'));
    expect(log, contains('fieldShapes='));
    expect(log, isNot(contains('private-user-id')));
    expect(log, isNot(contains('private@example.com')));
    expect(log, isNot(contains('Private Name')));
    expect(log, isNot(contains('private-health-value')));
    expect(log, isNot(contains(_session.accessToken)));
  });

  test('Supabase bootstrap retries once with a refreshed token', () async {
    final adapter = _SequenceAdapter([
      (401, '{"success":false}'),
      (
        200,
        '{"success":true,"data":{"user_id":"app-user-1","dietary_preference":"omnivore","onboarding_completed":false}}',
      ),
    ]);
    var refreshCalls = 0;
    final repository = FastApiAccountRepository(
      _dio(adapter),
      tokenProvider: () async {
        refreshCalls++;
        return refreshCalls == 1 ? 'initial-token' : 'refreshed-token';
      },
    );

    final result = await repository.provisionAuthenticatedUser(
      _supabaseSession,
    );

    expect(result.applicationUserId, 'app-user-1');
    expect(refreshCalls, 2);
    expect(adapter.authorizationHeaders, [
      'Bearer initial-token',
      'Bearer refreshed-token',
    ]);
  });

  test('Supabase refresh failure expires bootstrap before sending HTTP',
      () async {
    final adapter = _SequenceAdapter(const []);
    final repository = FastApiAccountRepository(
      _dio(adapter),
      tokenProvider: () async => throw StateError('refresh failed'),
    );

    await expectLater(
      repository.provisionAuthenticatedUser(_supabaseSession),
      throwsA(isA<AuthSessionExpiredException>()),
    );
    expect(adapter.authorizationHeaders, isEmpty);
  });
}

const _session = AuthSession(
  userId: 'user-1',
  displayName: 'Test User',
  email: 'test@example.com',
  accessToken: 'token',
  provider: 'fastapi',
);

const _supabaseSession = AuthSession(
  userId: 'supabase-user-1',
  displayName: 'Supabase User',
  email: 'supabase@example.com',
  accessToken: 'stale-token',
  provider: 'supabase',
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
  int fetchCalls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCalls++;
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

class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.responses);

  final List<(int, String)> responses;
  final authorizationHeaders = <String?>[];
  int _index = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    authorizationHeaders.add(options.headers['Authorization']?.toString());
    final response = responses[_index++];
    return ResponseBody.fromString(
      response.$2,
      response.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _TimeoutAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.receiveTimeout,
      error: 'timed out',
    );
  }
}
