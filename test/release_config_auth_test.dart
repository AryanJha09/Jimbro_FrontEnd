import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/core/config/app_config.dart';
import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/notifications/workout_notification_service.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  test('config validation keeps mock mode usable without live config', () {
    const config = AppConfig(
      backendMode: BackendMode.mock,
      authMode: AuthMode.supabase,
      fastApiBaseUrl: '',
      supabaseUrl: '',
      supabaseAnonKey: '',
      supabaseRedirectScheme: 'jimbro',
      supabaseRedirectHost: 'login-callback',
    );

    expect(
      config.validate(presentVariableNames: const {}).where(
          (issue) => issue.severity == AppConfigValidationSeverity.error),
      isEmpty,
    );
  });

  test('config validation requires api v1 and warns on server-only env names',
      () {
    const config = AppConfig(
      backendMode: BackendMode.fastApi,
      authMode: AuthMode.supabase,
      fastApiBaseUrl: 'https://api.example.test',
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'public-anon-key',
      supabaseRedirectScheme: 'jimbro',
      supabaseRedirectHost: 'login-callback',
    );

    final issues = config.validate(
      presentVariableNames: const {
        'APP_BACKEND_MODE',
        'AUTH_MODE',
        'FASTAPI_BASE_URL',
        'SUPABASE_URL',
        'SUPABASE_ANON_KEY',
        'SUPABASE_SERVICE_KEY',
      },
    );

    expect(
      issues
          .where((issue) =>
              issue.code == 'fastapi_base_url_missing_api_v1' &&
              issue.severity == AppConfigValidationSeverity.error)
          .length,
      1,
    );
    expect(
      issues
          .where((issue) =>
              issue.code == 'server_only_env_name' &&
              issue.variableName == 'SUPABASE_SERVICE_KEY')
          .length,
      1,
    );
  });

  test('401 from protected save clears session and auth gate state', () async {
    final authRepository = _MutableAuthRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
        workoutRepositoryProvider
            .overrideWithValue(_ExpiringWorkoutRepository()),
        nutritionRepositoryProvider
            .overrideWithValue(MockNutritionRepository()),
        consistencyRepositoryProvider.overrideWithValue(
          MockConsistencyRepository(),
        ),
        atlasRepositoryProvider.overrideWithValue(MockAtlasRepository()),
        searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
        workoutNotificationServiceProvider.overrideWithValue(
          const _NoopWorkoutNotificationService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(appDraftProvider.future);
    expect(container.read(isAuthenticatedProvider), isTrue);

    await expectLater(
      container.read(appDraftProvider.notifier).saveWorkoutTemplate(),
      throwsA(isA<AuthSessionExpiredException>()),
    );

    expect(authRepository.signOutCalled, isTrue);
    expect(container.read(authSessionProvider), isNull);
    expect(container.read(isAuthenticatedProvider), isFalse);
    expect(container.read(hasCompletedOnboardingProvider), isFalse);
    expect(container.read(appDraftProvider).value?.session, isNull);
  });

  test('missing bearer token blocks protected save before HTTP', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = _FailingHttpClientAdapter();
    final repository = FastApiWorkoutRepository(dio);

    await expectLater(
      repository.saveTemplate(
        const AuthSession(
          userId: 'user-1',
          displayName: 'Test User',
          email: 'test@example.com',
          accessToken: '',
          provider: 'fastapi',
        ),
        const WorkoutTemplateDraft(
          name: 'Push',
          description: '',
          durationMinutes: 0,
          goal: '',
          exercises: [
            WorkoutExerciseDraft(
              exerciseId: 1,
              exerciseName: 'Bench Press',
              notes: '',
              targetSets: 3,
              targetReps: 8,
              sets: [],
            ),
          ],
        ),
      ),
      throwsA(
        isA<Exception>()
            .having(
              (error) => error.toString(),
              'message',
              contains('Authentication token missing'),
            )
            .having(
              (error) => error.toString(),
              'backend sent',
              contains('backend_request_sent: false'),
            ),
      ),
    );
  });
}

class _MutableAuthRepository implements AuthRepository {
  AuthSession? session = const AuthSession(
    userId: 'test-user',
    displayName: 'Test User',
    email: 'test@example.com',
    accessToken: 'test-token',
    provider: 'fastapi',
  );
  bool signOutCalled = false;

  @override
  Future<AuthSession?> currentSession() async => session;

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return session!;
  }

  @override
  Future<AuthSession> signInWithMockProvider(String provider) async {
    return session!;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    session = null;
  }
}

class _ExpiringWorkoutRepository extends MockWorkoutRepository {
  @override
  Future<WorkoutTemplateDraft> saveTemplate(
    AuthSession? session,
    WorkoutTemplateDraft template,
  ) async {
    throw const AuthSessionExpiredException(
      'Backend rejected bearer token.\nstatus: 401',
    );
  }
}

class _NoopWorkoutNotificationService implements WorkoutNotificationService {
  const _NoopWorkoutNotificationService();

  @override
  Future<void> cancelReminder(WorkoutScheduleEntry entry) async {}

  @override
  Future<WorkoutReminderResult> scheduleWeeklyReminder(
    WorkoutScheduleEntry entry,
  ) async {
    return const WorkoutReminderResult(
      status: WorkoutReminderStatus.unavailable,
      message: 'Unavailable in test.',
    );
  }
}

class _FailingHttpClientAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw StateError('HTTP should not be reached without a bearer token.');
  }
}
