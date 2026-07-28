import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jimbro/core/errors/app_error.dart';
import 'package:jimbro/core/errors/profile_schema_exception.dart';
import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  test('bootstrap copyWith can clear a provisioning error', () {
    final failed = AppBootstrapState(
      status: AppBootstrapStatus.recoverableError,
      session: _session('user-1'),
      error: const UserProvisioningException(),
    );

    final recovered = failed.copyWith(
      status: AppBootstrapStatus.onboardingRequired,
      error: null,
    );

    expect(recovered.error, isNull);
    expect(recovered.session?.userId, 'user-1');
  });

  test('backend incomplete flag requires onboarding despite complete fields',
      () async {
    final container = _container(
      auth: _RestoredAuthRepository(_session('user-1')),
      account: _ImmediateProvisioningRepository(
        profile: _completeProfile('Complete Fields'),
        onboardingCompleted: false,
      ),
    );
    addTearDown(container.dispose);

    await container.read(appDraftProvider.future);

    expect(
      container.read(appBootstrapProvider).status,
      AppBootstrapStatus.onboardingRequired,
    );
    expect(container.read(hasCompletedOnboardingProvider), isFalse);
  });

  test('backend complete flag is ready despite missing optional fields',
      () async {
    final container = _container(
      auth: _RestoredAuthRepository(_session('user-1')),
      account: _ImmediateProvisioningRepository(
        profile: _provisionalProfile('Backend Complete'),
        onboardingCompleted: true,
      ),
    );
    addTearDown(container.dispose);

    final draft = await container.read(appDraftProvider.future);

    expect(draft.profile.age, isNull);
    expect(
        container.read(appBootstrapProvider).status, AppBootstrapStatus.ready);
    expect(container.read(hasCompletedOnboardingProvider), isTrue);
  });

  test('flat complete HTTP profile response routes to ready', () async {
    final container = _container(
      auth: _RestoredAuthRepository(_session('user-1')),
      account: _httpProfileRepository(
        '{"success":true,"data":{"user_id":"app-user-1","username":"Complete User","age":30,"height_cm":180,"weight_kg":80,"sex":"male","activity_level":"moderately_active","fitness_goal":"gain_muscle","experience_level":"intermediate","available_time_min":45,"equipment_access":"full_gym","dietary_preference":"vegetarian","constraints_json":[],"onboarding_completed":true}}',
      ),
    );
    addTearDown(container.dispose);

    final draft = await container.read(appDraftProvider.future);

    expect(draft.profile.name, 'Complete User');
    expect(
      container.read(appBootstrapProvider).status,
      AppBootstrapStatus.ready,
    );
  });

  test('flat partial HTTP profile response routes to onboarding', () async {
    final container = _container(
      auth: _RestoredAuthRepository(_session('user-1')),
      account: _httpProfileRepository(
        '{"success":true,"data":{"user_id":"app-user-1","username":null,"age":null,"activity_level":null,"dietary_preference":null,"constraints_json":null,"onboarding_completed":false}}',
      ),
    );
    addTearDown(container.dispose);

    final draft = await container.read(appDraftProvider.future);

    expect(draft.profile.age, isNull);
    expect(draft.profile.activityLevel, isNull);
    expect(draft.profile.dietaryPreference, isNull);
    expect(
      container.read(appBootstrapProvider).status,
      AppBootstrapStatus.onboardingRequired,
    );
  });

  test('protected write is blocked while provisioning is in progress',
      () async {
    final account = _ControlledProvisioningRepository();
    final workouts = _CountingWorkoutRepository();
    final container = _container(
      auth: _RestoredAuthRepository(_session('user-1')),
      account: account,
      workouts: workouts,
    );
    addTearDown(container.dispose);

    unawaited(container.read(appDraftProvider.future));
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(appBootstrapProvider).status,
      AppBootstrapStatus.authenticatedProvisioning,
    );
    await expectLater(
      container.read(appDraftProvider.notifier).saveWorkoutTemplate(),
      throwsA(isA<Exception>()),
    );
    expect(workouts.saveCalls, 0);

    account.complete(
      'user-1',
      profile: _provisionalProfile('User One'),
      onboardingCompleted: false,
    );
    await container.read(appDraftProvider.future);
  });

  test('latest concurrent bootstrap wins during a user switch', () async {
    final auth = _SwitchingAuthRepository();
    final account = _ControlledProvisioningRepository();
    final container = _container(auth: auth, account: account);
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);

    final first = container
        .read(appDraftProvider.notifier)
        .signInWithEmailPassword(email: 'first@example.com', password: 'x');
    await Future<void>.delayed(Duration.zero);
    final second = container
        .read(appDraftProvider.notifier)
        .signInWithEmailPassword(email: 'second@example.com', password: 'x');
    await Future<void>.delayed(Duration.zero);

    account.complete(
      'second',
      profile: _provisionalProfile('Second User'),
      onboardingCompleted: true,
    );
    await second;
    account.complete(
      'first',
      profile: _completeProfile('First User'),
      onboardingCompleted: false,
    );
    await first;

    expect(container.read(authSessionProvider)?.userId, 'second');
    expect(
        container.read(appBootstrapProvider).status, AppBootstrapStatus.ready);
    expect(container.read(appDraftProvider).value?.profile.name, 'Second User');
  });

  test('successful retry clears the old provisioning error', () async {
    final account = _RetryProvisioningRepository();
    final container = _container(
      auth: _RestoredAuthRepository(_session('user-1')),
      account: account,
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(appDraftProvider.future),
      throwsA(isA<UserProvisioningException>()),
    );
    expect(
      container.read(appBootstrapProvider).status,
      AppBootstrapStatus.fatalError,
    );
    expect(
      container.read(appBootstrapProvider).error,
      isA<UserProvisioningException>(),
    );

    await container.read(appDraftProvider.notifier).retryAccountProvisioning();

    final bootstrap = container.read(appBootstrapProvider);
    expect(bootstrap.status, AppBootstrapStatus.onboardingRequired);
    expect(bootstrap.error, isNull);
    expect(container.read(appDraftProvider).value?.profile.name, 'Retry User');
  });

  test('repeated retry calls share one in-flight profile bootstrap', () async {
    final account = _QueuedProvisioningRepository();
    final container = _container(
      auth: _RestoredAuthRepository(_session('user-1')),
      account: account,
    );
    addTearDown(container.dispose);

    await container.read(appDraftProvider.future);
    final firstRetry =
        container.read(appDraftProvider.notifier).retryAccountProvisioning();
    await account.waitForRequests(1);
    final secondRetry =
        container.read(appDraftProvider.notifier).retryAccountProvisioning();

    account.complete(
      0,
      profile: _completeProfile('Retry Winner'),
      onboardingCompleted: true,
    );
    await Future.wait([firstRetry, secondRetry]);

    expect(account.calls, 2, reason: 'initial bootstrap plus one shared retry');
    expect(
        container.read(appBootstrapProvider).status, AppBootstrapStatus.ready);
    expect(container.read(appBootstrapProvider).error, isNull);
    expect(
      container.read(appDraftProvider).value?.profile.name,
      'Retry Winner',
    );
  });

  test('transient profile failures preserve the authenticated session',
      () async {
    final failures = <Object>[
      DioException(
        requestOptions: RequestOptions(path: '/supabase/profile'),
        type: DioExceptionType.receiveTimeout,
      ),
      DioException(
        requestOptions: RequestOptions(path: '/supabase/profile'),
        type: DioExceptionType.connectionError,
      ),
      const AppError(
        code: AppErrorCode.serverUnavailable,
        userMessage: 'Temporarily unavailable.',
        diagnostics: AppErrorDiagnostics(
          method: 'GET',
          route: '/supabase/profile',
          httpStatus: 503,
          retryable: true,
        ),
      ),
    ];

    for (final failure in failures) {
      final container = _container(
        auth: _RestoredAuthRepository(_session('user-1')),
        account: _FailingProvisioningRepository(failure),
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(appDraftProvider.future),
        throwsA(anything),
      );

      final bootstrap = container.read(appBootstrapProvider);
      expect(bootstrap.status, AppBootstrapStatus.recoverableError);
      expect(bootstrap.session?.userId, 'user-1');
      expect(container.read(isAuthenticatedProvider), isTrue);
    }
  });

  test('malformed profile is fatal without signing out', () async {
    final error = ProfileSchemaException(
      stage: ProfileProcessingStage.dtoParsing,
      sanitizedMessage: 'Unsupported profile schema.',
      exceptionType: 'FormatException',
      stackTrace: StackTrace.current,
    );
    final container = _container(
      auth: _RestoredAuthRepository(_session('user-1')),
      account: _FailingProvisioningRepository(error),
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(appDraftProvider.future),
      throwsA(same(error)),
    );

    final bootstrap = container.read(appBootstrapProvider);
    expect(bootstrap.status, AppBootstrapStatus.fatalError);
    expect(bootstrap.session?.userId, 'user-1');
  });

  test('definitively expired bootstrap session is cleared', () async {
    final auth = _RestoredAuthRepository(_session('user-1'));
    final container = _container(
      auth: auth,
      account: _FailingProvisioningRepository(
        const AuthSessionExpiredException(
          'Your session expired. Please sign in again.',
        ),
      ),
    );
    addTearDown(container.dispose);

    await container.read(appDraftProvider.future);

    expect(
      container.read(appBootstrapProvider).status,
      AppBootstrapStatus.expired,
    );
    expect(container.read(authSessionProvider), isNull);
    expect(auth.session, isNull);
  });
}

ProviderContainer _container({
  required AuthRepository auth,
  required AccountRepository account,
  WorkoutRepository? workouts,
}) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      accountRepositoryProvider.overrideWithValue(account),
      profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
      workoutRepositoryProvider
          .overrideWithValue(workouts ?? MockWorkoutRepository()),
      nutritionRepositoryProvider.overrideWithValue(MockNutritionRepository()),
      consistencyRepositoryProvider
          .overrideWithValue(MockConsistencyRepository()),
      programRepositoryProvider.overrideWithValue(MockProgramRepository()),
      searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
    ],
  );
}

AuthSession _session(String userId) => AuthSession(
      userId: userId,
      displayName: 'Test User',
      email: '$userId@example.com',
      accessToken: 'test-token',
      provider: 'supabase',
    );

UserProfile _provisionalProfile(String name) => UserProfile(
      name: name,
      goal: null,
      coachingPreference: null,
      userLevel: null,
      age: null,
      heightCm: null,
      weightKg: null,
      sex: null,
      availableTimeMinutes: null,
      trainingPreference: null,
      activityLevel: null,
      dietaryPreference: null,
      goalTimeframe: null,
      weeksActive: null,
      prefersVoiceLogging: null,
    );

UserProfile _completeProfile(String name) => UserProfile(
      name: name,
      goal: 'Build muscle',
      coachingPreference: 'Concise',
      userLevel: UserLevel.intermediate,
      age: 30,
      heightCm: 180,
      weightKg: 80,
      sex: 'Male',
      availableTimeMinutes: 45,
      trainingPreference: 'Gym workouts',
      activityLevel: 'Moderately active',
      dietaryPreference: 'vegetarian',
      goalTimeframe: '',
      weeksActive: 0,
      prefersVoiceLogging: false,
    );

FastApiAccountRepository _httpProfileRepository(String responseBody) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.example.test/api/v1',
      validateStatus: (status) => status != null && status < 500,
    ),
  )..httpClientAdapter = _ProfileResponseAdapter(responseBody);
  return FastApiAccountRepository(
    dio,
    tokenProvider: () async => 'test-token',
    refreshTokenProvider: () async => 'test-token',
  );
}

class _ProfileResponseAdapter implements HttpClientAdapter {
  const _ProfileResponseAdapter(this.responseBody);

  final String responseBody;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      responseBody,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _RestoredAuthRepository implements AuthRepository {
  _RestoredAuthRepository(this.session);

  AuthSession? session;

  @override
  Future<AuthSession?> currentSession() async => session;

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async =>
      session!;

  @override
  Future<AuthSession> signInWithMockProvider(String provider) async => session!;

  @override
  Future<void> signOut() async => session = null;
}

class _SwitchingAuthRepository extends _RestoredAuthRepository {
  _SwitchingAuthRepository() : super(null);

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    session = _session(email.startsWith('first') ? 'first' : 'second');
    return session!;
  }
}

class _ImmediateProvisioningRepository implements AccountRepository {
  _ImmediateProvisioningRepository({
    required this.profile,
    required this.onboardingCompleted,
  });

  final UserProfile profile;
  final bool onboardingCompleted;

  @override
  Future<ApplicationUserProvisioningResult> provisionAuthenticatedUser(
    AuthSession session,
  ) async {
    return ApplicationUserProvisioningResult(
      applicationUserId: session.userId,
      profile: profile,
      onboardingCompleted: onboardingCompleted,
    );
  }

  @override
  Future<AccountDeletionResult> deleteAccount(AuthSession session) async {
    return const AccountDeletionResult(deleted: true);
  }
}

class _ControlledProvisioningRepository implements AccountRepository {
  final _pending = <String, Completer<ApplicationUserProvisioningResult>>{};

  @override
  Future<ApplicationUserProvisioningResult> provisionAuthenticatedUser(
    AuthSession session,
  ) {
    return (_pending[session.userId] ??=
            Completer<ApplicationUserProvisioningResult>())
        .future;
  }

  void complete(
    String userId, {
    required UserProfile profile,
    required bool onboardingCompleted,
  }) {
    _pending[userId]!.complete(
      ApplicationUserProvisioningResult(
        applicationUserId: userId,
        profile: profile,
        onboardingCompleted: onboardingCompleted,
      ),
    );
  }

  @override
  Future<AccountDeletionResult> deleteAccount(AuthSession session) async {
    return const AccountDeletionResult(deleted: true);
  }
}

class _RetryProvisioningRepository implements AccountRepository {
  int calls = 0;

  @override
  Future<ApplicationUserProvisioningResult> provisionAuthenticatedUser(
    AuthSession session,
  ) async {
    calls++;
    if (calls == 1) {
      throw const UserProvisioningException();
    }
    return ApplicationUserProvisioningResult(
      applicationUserId: session.userId,
      profile: _provisionalProfile('Retry User'),
      onboardingCompleted: false,
    );
  }

  @override
  Future<AccountDeletionResult> deleteAccount(AuthSession session) async {
    return const AccountDeletionResult(deleted: true);
  }
}

class _FailingProvisioningRepository implements AccountRepository {
  _FailingProvisioningRepository(this.error);

  final Object error;

  @override
  Future<ApplicationUserProvisioningResult> provisionAuthenticatedUser(
    AuthSession session,
  ) async {
    throw error;
  }

  @override
  Future<AccountDeletionResult> deleteAccount(AuthSession session) async {
    return const AccountDeletionResult(deleted: true);
  }
}

class _QueuedProvisioningRepository implements AccountRepository {
  final requests = <Completer<ApplicationUserProvisioningResult>>[];
  var calls = 0;

  @override
  Future<ApplicationUserProvisioningResult> provisionAuthenticatedUser(
    AuthSession session,
  ) {
    calls++;
    if (calls == 1) {
      return Future.value(
        ApplicationUserProvisioningResult(
          applicationUserId: session.userId,
          profile: _provisionalProfile('Initial User'),
          onboardingCompleted: false,
        ),
      );
    }
    final request = Completer<ApplicationUserProvisioningResult>();
    requests.add(request);
    return request.future;
  }

  Future<void> waitForRequests(int count) async {
    while (requests.length < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void complete(
    int index, {
    required UserProfile profile,
    required bool onboardingCompleted,
  }) {
    requests[index].complete(
      ApplicationUserProvisioningResult(
        applicationUserId: 'user-1',
        profile: profile,
        onboardingCompleted: onboardingCompleted,
      ),
    );
  }

  @override
  Future<AccountDeletionResult> deleteAccount(AuthSession session) async {
    return const AccountDeletionResult(deleted: true);
  }
}

class _CountingWorkoutRepository extends MockWorkoutRepository {
  int saveCalls = 0;

  @override
  Future<WorkoutTemplateDraft> saveTemplate(
    AuthSession? session,
    WorkoutTemplateDraft template,
  ) async {
    saveCalls++;
    return template;
  }
}
