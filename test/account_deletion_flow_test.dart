import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jimbro/app/app.dart';
import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('successful account deletion clears session and account local data',
      () async {
    final authRepository = _MutableAuthRepository();
    final accountRepository = _ImmediateAccountRepository();
    final profileRepository = _CacheAwareProfileRepository();
    final workoutRepository = _CacheAwareWorkoutRepository();
    final nutritionRepository = _CacheAwareNutritionRepository();
    SharedPreferences.setMockInitialValues({
      'offline_outbox_test-user': '[]',
      'jimbro.workout_schedule.test-user': '[]',
      'jimbro.onboarding.v1.test-user': '{}',
      'jimbro.onboarding.v1.test-user.tmp': '{}',
    });
    final container = _container(
      authRepository: authRepository,
      accountRepository: accountRepository,
      profileRepository: profileRepository,
      workoutRepository: workoutRepository,
      nutritionRepository: nutritionRepository,
    );
    addTearDown(container.dispose);

    await container.read(appDraftProvider.future);
    await container.read(appDraftProvider.notifier).deleteAccount();

    final prefs = await SharedPreferences.getInstance();
    expect(accountRepository.calls, 1);
    expect(authRepository.signOutCalled, isTrue);
    expect(container.read(authSessionProvider), isNull);
    expect(container.read(isAuthenticatedProvider), isFalse);
    expect(container.read(hasCompletedOnboardingProvider), isFalse);
    expect(container.read(appDraftProvider).value?.session, isNull);
    expect(prefs.getString('offline_outbox_test-user'), isNull);
    expect(prefs.getString('jimbro.workout_schedule.test-user'), isNull);
    expect(prefs.getString('jimbro.onboarding.v1.test-user'), isNull);
    expect(prefs.getString('jimbro.onboarding.v1.test-user.tmp'), isNull);
    expect(profileRepository.clearedUserIds, ['test-user']);
    expect(workoutRepository.clearedUserIds, ['test-user']);
    expect(nutritionRepository.clearedUserIds, ['test-user']);
  });

  test('failed account deletion preserves session and local data', () async {
    final authRepository = _MutableAuthRepository();
    final accountRepository = _ImmediateAccountRepository(succeed: false);
    SharedPreferences.setMockInitialValues({
      'offline_outbox_test-user': '[]',
    });
    final container = _container(
      authRepository: authRepository,
      accountRepository: accountRepository,
    );
    addTearDown(container.dispose);

    await container.read(appDraftProvider.future);
    await expectLater(
      container.read(appDraftProvider.notifier).deleteAccount(),
      throwsA(isA<AccountDeletionException>()),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(accountRepository.calls, 1);
    expect(authRepository.signOutCalled, isFalse);
    expect(container.read(authSessionProvider), _session);
    expect(container.read(isAuthenticatedProvider), isTrue);
    expect(container.read(appDraftProvider).value?.session, _session);
    expect(prefs.getString('offline_outbox_test-user'), '[]');
  });

  testWidgets('Delete Account opens confirmation and cancel/dismiss do nothing',
      (tester) async {
    final accountRepository = _ControlledAccountRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(accountRepository),
        ],
        child: const JimBroApp(),
      ),
    );
    await _enterApp(tester);
    await _tapBottomNav(tester, Icons.person_outline_rounded);

    expect(
      find.byKey(const ValueKey('profile-sign-out-button')),
      findsOneWidget,
    );
    expect(find.text('Delete Account'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('profile-delete-account-button')));
    await tester.pumpAndSettle();

    expect(find.text('Delete your account?'), findsOneWidget);
    expect(
      find.text(
        'This permanently deletes your account and all your data. '
        'This cannot be undone.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(accountRepository.calls, 0);

    await tester
        .tap(find.byKey(const ValueKey('profile-delete-account-button')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.text('Delete your account?'), findsNothing);
    expect(accountRepository.calls, 0);
  });

  testWidgets(
      'confirming deletion sends one request, shows loading, and returns to auth',
      (tester) async {
    final accountRepository = _ControlledAccountRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(accountRepository),
        ],
        child: const JimBroApp(),
      ),
    );
    await _enterApp(tester);
    await _tapBottomNav(tester, Icons.person_outline_rounded);

    await tester
        .tap(find.byKey(const ValueKey('profile-delete-account-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(accountRepository.calls, 1);
    expect(find.text('Deleting...'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('profile-delete-account-button')));
    await tester.pump();
    expect(accountRepository.calls, 1);

    accountRepository.succeedNext();
    await tester.pumpAndSettle();

    expect(find.text('Meet Jim'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Shape your coaching plan'), findsNothing);
  });

  testWidgets('failure keeps session, shows generic error, and allows retry',
      (tester) async {
    final accountRepository = _ControlledAccountRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(accountRepository),
        ],
        child: const JimBroApp(),
      ),
    );
    await _enterApp(tester);
    await _tapBottomNav(tester, Icons.person_outline_rounded);

    await tester
        .tap(find.byKey(const ValueKey('profile-delete-account-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    accountRepository.failNext();
    await tester.pumpAndSettle();

    expect(find.text('Shape your coaching plan'), findsOneWidget);
    expect(
      find.text('Unable to delete your account. Please try again.'),
      findsOneWidget,
    );
    expect(accountRepository.calls, 1);

    await tester
        .tap(find.byKey(const ValueKey('profile-delete-account-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(accountRepository.calls, 2);
    accountRepository.succeedNext();
    await tester.pumpAndSettle();
    expect(find.text('Meet Jim'), findsOneWidget);
  });
}

const _session = AuthSession(
  userId: 'test-user',
  displayName: 'Test User',
  email: 'test@example.com',
  accessToken: 'test-token',
  provider: 'fastapi',
);

ProviderContainer _container({
  required AuthRepository authRepository,
  required AccountRepository accountRepository,
  ProfileRepository? profileRepository,
  WorkoutRepository? workoutRepository,
  NutritionRepository? nutritionRepository,
}) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepository),
      accountRepositoryProvider.overrideWithValue(accountRepository),
      profileRepositoryProvider
          .overrideWithValue(profileRepository ?? MockProfileRepository()),
      workoutRepositoryProvider
          .overrideWithValue(workoutRepository ?? MockWorkoutRepository()),
      nutritionRepositoryProvider
          .overrideWithValue(nutritionRepository ?? MockNutritionRepository()),
      consistencyRepositoryProvider
          .overrideWithValue(MockConsistencyRepository()),
      atlasRepositoryProvider.overrideWithValue(MockAtlasRepository()),
      agentContextRepositoryProvider
          .overrideWithValue(MockAgentContextRepository()),
      programRepositoryProvider.overrideWithValue(MockProgramRepository()),
      searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
    ],
  );
}

class _CacheAwareProfileRepository extends MockProfileRepository
    implements UserScopedCache {
  final clearedUserIds = <String>[];

  @override
  void clearUserCache(String userId) => clearedUserIds.add(userId);
}

class _CacheAwareWorkoutRepository extends MockWorkoutRepository
    implements UserScopedCache {
  final clearedUserIds = <String>[];

  @override
  void clearUserCache(String userId) => clearedUserIds.add(userId);
}

class _CacheAwareNutritionRepository extends MockNutritionRepository
    implements UserScopedCache {
  final clearedUserIds = <String>[];

  @override
  void clearUserCache(String userId) => clearedUserIds.add(userId);
}

Future<void> _enterApp(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue with Google'));
  await tester.pumpAndSettle();
  await _completeOnboardingFlow(tester);
}

Future<void> _completeOnboardingFlow(WidgetTester tester) async {
  await _tapOnboardingCta(tester, 'Start setup');
  await _selectOnboardingOption(tester, 'Build muscle');
  await _tapOnboardingCta(tester, 'Continue');
  await _selectOnboardingOption(tester, 'I want more energy');
  await _tapOnboardingCta(tester, 'Continue');
  await _selectOnboardingOption(
    tester,
    'I’ve trained before, but not consistently',
  );
  await _tapOnboardingCta(tester, 'Continue');
  await _tapOnboardingCta(tester, 'Continue');
  await _selectOnboardingOption(tester, 'Lightly active');
  await _tapOnboardingCta(tester, 'Continue');
  await _selectOnboardingOption(tester, '30 minutes');
  await _tapOnboardingCta(tester, 'Continue');
  await _selectOnboardingOption(tester, 'Home workouts');
  await _tapOnboardingCta(tester, 'Continue');
  await _tapOnboardingCta(tester, 'Continue');
  await _selectOnboardingOption(tester, 'Vegetarian');
  await _tapOnboardingCta(tester, 'Continue');
  await _tapOnboardingCta(tester, 'Continue');
  await _selectOnboardingOption(tester, 'Prefer not to say');
  await _tapOnboardingCta(tester, 'Continue');
  await _tapOnboardingCta(tester, 'Continue');
  await _tapOnboardingCta(tester, 'Continue');
  await _tapOnboardingCta(tester, 'Start my plan');
  await tester.pumpAndSettle();
  if (find.text('Skip for now').evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const ValueKey('skip-program-button')));
    await tester.pumpAndSettle();
  }
}

Future<void> _tapBottomNav(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon).last);
  await tester.pumpAndSettle();
}

Future<void> _selectOnboardingOption(
  WidgetTester tester,
  String label,
) async {
  final option = find.byKey(ValueKey('onboarding-option-$label'));
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  final topLeft = tester.getTopLeft(option);
  await tester.tapAt(topLeft + const Offset(32, 24));
  await tester.pumpAndSettle();
}

Future<void> _tapOnboardingCta(
  WidgetTester tester,
  String label,
) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class _MutableAuthRepository implements AuthRepository {
  AuthSession? session = _session;
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

class _ImmediateAccountRepository implements AccountRepository {
  _ImmediateAccountRepository({this.succeed = true});

  final bool succeed;
  int calls = 0;

  @override
  Future<ApplicationUserProvisioningResult> provisionAuthenticatedUser(
    AuthSession session,
  ) async {
    return ApplicationUserProvisioningResult(
      applicationUserId: session.userId,
    );
  }

  @override
  Future<AccountDeletionResult> deleteAccount(AuthSession session) async {
    calls++;
    if (!succeed) {
      throw const AccountDeletionException();
    }
    return const AccountDeletionResult(deleted: true);
  }
}

class _ControlledAccountRepository implements AccountRepository {
  final _pending = <Completer<AccountDeletionResult>>[];
  int calls = 0;

  @override
  Future<ApplicationUserProvisioningResult> provisionAuthenticatedUser(
    AuthSession session,
  ) async {
    return ApplicationUserProvisioningResult(
      applicationUserId: session.userId,
    );
  }

  @override
  Future<AccountDeletionResult> deleteAccount(AuthSession session) {
    calls++;
    final completer = Completer<AccountDeletionResult>();
    _pending.add(completer);
    return completer.future;
  }

  void succeedNext() {
    _pending.removeAt(0).complete(
          const AccountDeletionResult(deleted: true),
        );
  }

  void failNext() {
    _pending.removeAt(0).completeError(const AccountDeletionException());
  }
}
