import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/features/workouts/application/active_workout_controller.dart';
import 'package:jimbro/features/workouts/presentation/workout_routes.dart';
import 'package:jimbro/features/workouts/presentation/workouts_page.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('workout route map has unique direct routes', () {
    final names = <String>{
      WorkoutRoutes.root,
      WorkoutRoutes.createTemplate,
      WorkoutRoutes.editTemplate(12),
      WorkoutRoutes.activeSession('session-12'),
      WorkoutRoutes.finishSummary('session-12'),
      WorkoutRoutes.history,
      WorkoutRoutes.historyDetail(33),
    };
    expect(names, hasLength(7));
    for (final name in names) {
      expect(
        WorkoutRoutes.onGenerateRoute(RouteSettings(name: name)),
        isNotNull,
      );
    }
    expect(
      WorkoutRoutes.onGenerateRoute(
        const RouteSettings(name: '/app/workouts/templates/not-an-id/edit'),
      ),
      isNull,
    );
  });

  testWidgets('Edit and Start open different workout destinations',
      (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);
    await container.read(activeWorkoutProvider.future);
    final draftController = container.read(appDraftProvider.notifier);
    await draftController.updateTemplate(_template);
    await draftController.saveWorkoutTemplate();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          onGenerateRoute: WorkoutRoutes.onGenerateRoute,
          home: const Scaffold(body: WorkoutsPage()),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Edit template'), findsOneWidget);
    expect(find.text('Active workout'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Active workout'), findsOneWidget);
    expect(find.text('Edit template'), findsNothing);
  });

  testWidgets('active page has one Finish and guards back navigation',
      (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);
    await container.read(activeWorkoutProvider.future);
    final active = await container
        .read(activeWorkoutProvider.notifier)
        .startOrResume(_template);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ActiveWorkoutPage(sessionId: active.sessionId),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    for (var index = 0; index < 5; index++) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const ValueKey('active-finish-action')), findsOneWidget);
    expect(find.text('Finish Workout'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Leave active workout?'), findsOneWidget);
    expect(find.text('Leave and resume later'), findsOneWidget);
    expect(container.read(activeWorkoutProvider).value?.session, isNotNull);
  });

  testWidgets('app pause checkpoints and resume preserves the session',
      (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);
    await container.read(activeWorkoutProvider.future);
    final controller = container.read(activeWorkoutProvider.notifier);
    final active = await controller.startOrResume(_template);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ActiveWorkoutPage(sessionId: active.sessionId),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    controller.updateNotes('Checkpoint on pause');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    final stored = await const ActiveWorkoutCheckpointStore()
        .load(_ReadyAuthRepository.session);
    expect(stored.session?.notes, 'Checkpoint on pause');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(activeWorkoutProvider).value?.session?.sessionId,
        active.sessionId);
  });

  testWidgets('completed workout detail is read-only', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);
    await container.read(activeWorkoutProvider.future);
    final activeController = container.read(activeWorkoutProvider.notifier);
    await activeController.startOrResume(_template);
    await activeController.finish();
    final logId =
        container.read(appDraftProvider).value!.workoutLog.workoutLogId!;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: WorkoutHistoryDetailPage(logId: logId),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Read-only completed session'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Finish Workout'), findsNothing);
  });
}

const _template = WorkoutTemplateDraft(
  templateId: 12,
  name: 'Route Push',
  description: 'A routed template',
  durationMinutes: 0,
  goal: '',
  exercises: [
    WorkoutExerciseDraft(
      exerciseId: 111,
      exerciseName: 'Bench Press',
      notes: '',
      targetSets: 1,
      targetReps: 8,
      sets: [
        SetDraft(
          setNumber: 1,
          weightKg: 60,
          reps: 8,
          isWarmup: false,
          isCompleted: false,
          rpe: 7,
        ),
      ],
    ),
  ],
);

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_ReadyAuthRepository()),
      profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
      workoutRepositoryProvider.overrideWithValue(MockWorkoutRepository()),
      nutritionRepositoryProvider.overrideWithValue(MockNutritionRepository()),
      consistencyRepositoryProvider.overrideWithValue(
        MockConsistencyRepository(),
      ),
      atlasRepositoryProvider.overrideWithValue(MockAtlasRepository()),
      searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
    ],
  );
}

class _ReadyAuthRepository implements AuthRepository {
  static const session = AuthSession(
    userId: 'route-user',
    displayName: 'Route User',
    email: 'route@example.test',
    accessToken: 'route-token',
    provider: 'test',
  );

  @override
  Future<AuthSession?> currentSession() async => session;

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async =>
      session;

  @override
  Future<AuthSession> signInWithMockProvider(String provider) async => session;

  @override
  Future<void> signOut() async {}
}
