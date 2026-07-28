import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jimbro/app/app.dart';
import 'package:jimbro/core/config/app_config.dart';
import 'package:jimbro/core/errors/profile_schema_exception.dart';
import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/core/theme/jim_theme.dart';
import 'package:jimbro/features/auth/presentation/auth_page.dart';
import 'package:jimbro/shared/components/backend_state_view.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('provisioning failure blocks navigation and successful retry',
      (tester) async {
    final accounts = _RetryAccountRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountRepositoryProvider.overrideWithValue(accounts)],
        child: const JimBroApp(),
      ),
    );
    await tester.pumpAndSettle();

    final emailToggle = find.text('Email');
    await tester.ensureVisible(emailToggle);
    await tester.pumpAndSettle();
    await tester.tap(emailToggle);
    await tester.pumpAndSettle();
    final createAccountToggle = find.text('Create account').first;
    await tester.ensureVisible(createAccountToggle);
    await tester.pumpAndSettle();
    await tester.tap(createAccountToggle);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Email address',
      ),
      'new-user@example.com',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == 'Password',
      ),
      'test-password',
    );
    final submitButton = find.byKey(const ValueKey('email-auth-submit-button'));
    await tester.ensureVisible(submitButton);
    await tester.pumpAndSettle();
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Your account is signed in, but we could not finish creating your JimBro profile.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recovery-retry-button')),
      findsOneWidget,
    );
    expect(find.byType(AuthPage), findsNothing);
    expect(find.byType(AuthenticatedRecoveryView), findsOneWidget);
    expect(find.text('Today\'s focus'), findsNothing);
    expect(
      find.text('Ready to set up your first coaching plan?'),
      findsNothing,
    );

    final retryButton = find.byKey(const ValueKey('recovery-retry-button'));
    await tester.ensureVisible(retryButton);
    await tester.pumpAndSettle();
    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(accounts.provisionCalls, 2);
    expect(
      find.text('Ready to set up your first coaching plan?'),
      findsOneWidget,
    );
  });

  testWidgets('restored session is not ready until bootstrap confirms user',
      (tester) async {
    final accounts = _ControlledAccountRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          _RestoredAuthRepository(),
        ),
        accountRepositoryProvider.overrideWithValue(accounts),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const JimBroApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 100));

    expect(accounts.provisionCalls, 1);
    expect(container.read(isAuthenticatedProvider), isTrue);
    expect(
      container.read(appBootstrapProvider).allowsProtectedWrites,
      isFalse,
    );
    expect(find.text('Today\'s focus'), findsNothing);
    expect(
      find.text('Ready to set up your first coaching plan?'),
      findsNothing,
    );

    accounts.succeed();
    await tester.pumpAndSettle();

    expect(container.read(isAuthenticatedProvider), isTrue);
    expect(
      find.text('Ready to set up your first coaching plan?'),
      findsOneWidget,
    );
  });

  testWidgets('successful retry removes recovery view without lifecycle errors',
      (tester) async {
    final retry = _ControlledRetryController();
    final observer = _CountingNavigatorObserver();
    await _pumpRetryHarness(tester, retry, observer: observer);
    final initialPushes = observer.pushes;

    await _tapRetry(tester);
    retry.completeSuccess();
    await tester.pump();

    expect(find.byType(AuthenticatedRecoveryView), findsNothing);
    expect(find.byKey(const ValueKey('retry-success-destination')),
        findsOneWidget);
    retry.finishRequest();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(observer.pushes, initialPushes,
        reason: 'AppFlow/provider state owns the transition');
  });

  testWidgets('failed retry keeps recovery view mounted and shows a safe error',
      (tester) async {
    final retry = _ControlledRetryController();
    await _pumpRetryHarness(tester, retry);

    await _tapRetry(tester);
    retry.completeFailure();
    await tester.pumpAndSettle();

    expect(find.byType(AuthenticatedRecoveryView), findsOneWidget);
    expect(
        find.text(const UserProvisioningException().message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GET profile schema failure never claims the account was created',
      (tester) async {
    final error = ProfileSchemaException(
      stage: ProfileProcessingStage.dtoParsing,
      sanitizedMessage: 'Unsupported profile schema.',
      exceptionType: 'FormatException',
      stackTrace: StackTrace.current,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: JimTheme.lightTheme,
        home: AuthenticatedRecoveryView(
          error: error,
          fatal: true,
          onRetry: () async {},
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'JimBro received profile data in an unexpected format. Retry once. If the problem continues, update the app or contact support.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('account was created'), findsNothing);
  });

  testWidgets('disposed recovery view ignores a late retry result',
      (tester) async {
    final retry = _ControlledRetryController();
    await _pumpRetryHarness(tester, retry);

    await _tapRetry(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    retry.completeFailure();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated retry taps start only one request', (tester) async {
    final retry = _ControlledRetryController();
    await _pumpRetryHarness(tester, retry);
    final button = find.byKey(const ValueKey('recovery-retry-button'));

    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();

    expect(retry.retryCalls, 1);
    retry.completeFailure();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('transient profile timeout shows recovery instead of auth',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_RestoredAuthRepository()),
        accountRepositoryProvider.overrideWithValue(
          _TransientAccountRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const JimBroApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('We couldn’t connect to JimBro'), findsOneWidget);
    expect(find.byType(AuthenticatedRecoveryView), findsOneWidget);
    expect(find.byType(AuthPage), findsNothing);
    expect(find.text('Email address'), findsNothing);
    expect(container.read(authSessionProvider)?.userId, 'restored-user');
  });

  testWidgets('recovery remains usable on a small iPhone viewport',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 1.25;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: JimTheme.lightTheme,
        home: Scaffold(
          body: AuthenticatedRecoveryView(
            error: DioException(
              requestOptions: RequestOptions(path: '/supabase/profile'),
              type: DioExceptionType.receiveTimeout,
            ),
            onRetry: () async {},
            onSignOut: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final signOut = find.byKey(const ValueKey('recovery-sign-out-button'));
    await tester.scrollUntilVisible(signOut, 120);
    expect(signOut, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live auth hides providers that are not configured',
      (tester) async {
    const liveConfig = AppConfig(
      backendMode: BackendMode.fastApi,
      authMode: AuthMode.supabase,
      fastApiBaseUrl: 'https://api.example.test/api/v1',
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'public-anon-key',
      supabaseRedirectScheme: 'jimbro',
      supabaseRedirectHost: 'login-callback',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appConfigProvider.overrideWithValue(liveConfig)],
        child: MaterialApp(
          theme: JimTheme.lightTheme,
          home: const Scaffold(body: AuthPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('Continue with Apple'), findsNothing);
    expect(find.text('Phone no'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Email address',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Supabase session token'), findsNothing);
  });
}

Future<void> _pumpRetryHarness(
  WidgetTester tester,
  _ControlledRetryController retry, {
  NavigatorObserver? observer,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDraftProvider.overrideWith(() => retry),
        appBootstrapProvider.overrideWith(
          (ref) => const AppBootstrapState(
            status: AppBootstrapStatus.fatalError,
            session: _retrySession,
            error: UserProvisioningException(),
          ),
        ),
      ],
      child: MaterialApp(
        navigatorObservers: [if (observer != null) observer],
        home: const _RetryLifecycleHarness(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('recovery-retry-button')), findsOneWidget);
}

Future<void> _tapRetry(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('recovery-retry-button'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

class _RetryLifecycleHarness extends ConsumerWidget {
  const _RetryLifecycleHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appDraftProvider);
    final bootstrap = ref.watch(appBootstrapProvider);
    if (bootstrap.status == AppBootstrapStatus.ready) {
      return const Scaffold(
        body: SizedBox(key: ValueKey('retry-success-destination')),
      );
    }
    return Scaffold(
      body: AuthenticatedRecoveryView(
        error: bootstrap.error ?? const UserProvisioningException(),
        fatal: true,
        onRetry: () =>
            ref.read(appDraftProvider.notifier).retryAccountProvisioning(),
        onSignOut: () => ref.read(appDraftProvider.notifier).signOut(),
      ),
    );
  }
}

class _ControlledRetryController extends AppDraftController {
  final _result = Completer<void>();
  final _finish = Completer<void>();
  int retryCalls = 0;

  @override
  Future<AppDraftState> build() async {
    throw const UserProvisioningException();
  }

  @override
  Future<void> retryAccountProvisioning() async {
    retryCalls++;
    await _result.future;
    state = const AsyncData(_retryDraft);
    ref.read(appBootstrapProvider.notifier).state = const AppBootstrapState(
      status: AppBootstrapStatus.ready,
      session: _retrySession,
    );
    await _finish.future;
  }

  void completeSuccess() => _result.complete();

  void completeFailure() =>
      _result.completeError(const UserProvisioningException());

  void finishRequest() => _finish.complete();
}

class _TransientAccountRepository implements AccountRepository {
  @override
  Future<ApplicationUserProvisioningResult> provisionAuthenticatedUser(
    AuthSession session,
  ) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/supabase/profile'),
      type: DioExceptionType.receiveTimeout,
    );
  }

  @override
  Future<AccountDeletionResult> deleteAccount(AuthSession session) async {
    return const AccountDeletionResult(deleted: true);
  }
}

class _CountingNavigatorObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

const _retrySession = AuthSession(
  userId: 'retry-user',
  displayName: 'Retry User',
  email: 'retry@example.test',
  accessToken: 'test-token',
  provider: 'test',
);

const _retryDraft = AppDraftState(
  session: _retrySession,
  profile: UserProfile(
    name: 'Retry User',
    goal: '',
    coachingPreference: '',
    userLevel: UserLevel.beginner,
    age: 0,
    heightCm: 0,
    weightKg: 0,
    sex: '',
    availableTimeMinutes: 0,
    trainingPreference: '',
    activityLevel: '',
    dietaryPreference: '',
    goalTimeframe: '',
    weeksActive: 0,
    prefersVoiceLogging: false,
  ),
  metrics: UserStaticMetrics(
    bmr: 0,
    tdee: 0,
    targetCalories: 0,
    maintenanceCalories: 0,
    cutCalories: 0,
    bulkCalories: 0,
    proteinG: 0,
    carbsG: 0,
    fatG: 0,
    hydrationL: 0,
    cutIntensity: '',
  ),
  template: WorkoutTemplateDraft.empty,
  templates: [],
  workoutSchedule: [],
  workoutLog: WorkoutLogDraft.empty,
  foodLogs: [],
  nutritionSummary: DailyNutritionSummary.empty,
  consistency: ConsistencyState(
    currentStreak: 0,
    longestStreak: 0,
    weeklyCheckins: 0,
    totalLogs: 0,
  ),
);

class _RetryAccountRepository implements AccountRepository {
  int provisionCalls = 0;

  @override
  Future<ApplicationUserProvisioningResult> provisionAuthenticatedUser(
    AuthSession session,
  ) async {
    provisionCalls++;
    if (provisionCalls == 1) {
      throw const UserProvisioningException();
    }
    return ApplicationUserProvisioningResult(
      applicationUserId: session.userId,
    );
  }

  @override
  Future<AccountDeletionResult> deleteAccount(AuthSession session) async {
    return const AccountDeletionResult(deleted: true);
  }
}

class _ControlledAccountRepository implements AccountRepository {
  final _completer = Completer<ApplicationUserProvisioningResult>();
  int provisionCalls = 0;

  @override
  Future<ApplicationUserProvisioningResult> provisionAuthenticatedUser(
    AuthSession session,
  ) {
    provisionCalls++;
    return _completer.future;
  }

  void succeed() {
    _completer.complete(
      const ApplicationUserProvisioningResult(
        applicationUserId: 'restored-user',
      ),
    );
  }

  @override
  Future<AccountDeletionResult> deleteAccount(AuthSession session) async {
    return const AccountDeletionResult(deleted: true);
  }
}

class _RestoredAuthRepository extends MockAuthRepository {
  static const session = AuthSession(
    userId: 'restored-user',
    displayName: 'Restored User',
    email: 'restored@example.com',
    accessToken: 'test-token',
    provider: 'test',
  );

  @override
  Future<AuthSession?> currentSession() async => session;
}
