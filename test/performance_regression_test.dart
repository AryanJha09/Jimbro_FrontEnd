import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/theme/jim_theme.dart';
import 'package:jimbro/features/home/presentation/home_shell.dart';
import 'package:jimbro/features/nutrition/presentation/nutrition_page.dart';
import 'package:jimbro/features/workouts/application/active_workout_controller.dart';
import 'package:jimbro/features/workouts/presentation/workouts_page.dart';
import 'package:jimbro/shared/models/app_models.dart';
import 'package:jimbro/shared/models/atlas_insight.dart';

void main() {
  testWidgets('records authenticated shell startup and hidden-tab work',
      (tester) async {
    final counts = _BuildCounts();
    final stopwatch = Stopwatch()..start();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDraftProvider.overrideWith(_PerformanceDraftController.new),
          activeWorkoutProvider.overrideWith(
            () => _CountingActiveWorkoutController(counts),
          ),
          atlasHomeInsightsProvider.overrideWith((ref) async {
            counts.homeInsights++;
            return const [];
          }),
          nutritionInsightProvider.overrideWith((ref) async {
            counts.nutritionInsights++;
            return _insight;
          }),
          historyInsightProvider.overrideWith((ref) async {
            counts.historyInsights++;
            return _insight;
          }),
          recoveryInsightProvider.overrideWith((ref) async {
            counts.recoveryInsights++;
            return _insight;
          }),
        ],
        child: MaterialApp(
          theme: JimTheme.lightTheme,
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    stopwatch.stop();

    // Keep the measurement visible in CI output without making elapsed time a
    // flaky pass/fail threshold.
    // ignore: avoid_print
    print('PERF shell_startup_us=${stopwatch.elapsedMicroseconds} '
        'home=${counts.homeInsights} nutrition=${counts.nutritionInsights} '
        'history=${counts.historyInsights} recovery=${counts.recoveryInsights} '
        'active_workout=${counts.activeWorkoutBuilds}');

    expect(counts.homeInsights, 1);
    expect(counts.nutritionInsights, 0);
    expect(counts.historyInsights, 0);
    expect(counts.recoveryInsights, 0);
    expect(counts.activeWorkoutBuilds, 0);

    final homeScroll =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    homeScroll.position.jumpTo(120);
    await tester.pump();

    final switchStopwatch = Stopwatch()..start();
    await tester.tap(find.byIcon(Icons.fitness_center_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.ramen_dining_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.show_chart_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    switchStopwatch.stop();

    // ignore: avoid_print
    print('PERF first_tab_cycle_us=${switchStopwatch.elapsedMicroseconds}');
    expect(counts.activeWorkoutBuilds, 1);
    expect(counts.nutritionInsights, 1);
    expect(counts.historyInsights, 1);
    expect(counts.recoveryInsights, 1);
    expect(counts.homeInsights, 1, reason: 'home must not refetch on return');
    expect(homeScroll.position.pixels, 120,
        reason: 'home scroll state is cached');

    await tester.tap(find.byIcon(Icons.ramen_dining_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    expect(counts.nutritionInsights, 1,
        reason: 'visited tabs must not refetch');
  });

  testWidgets('measures hundreds of templates, foods, and history rows',
      (tester) async {
    final templatesDraft = _draft.copyWith(
      template: _template,
      templates: List.generate(
        300,
        (index) => _template.copyWith(
          templateId: index + 1,
          name: 'Template ${index + 1}',
        ),
      ),
    );
    final templateTime = await _pumpPage(
      tester,
      const WorkoutsPage(),
      draft: templatesDraft,
    );
    final builtTemplateActions = find.text('Open').evaluate().length;
    final moreTemplates = find.text('Show more templates (280)');
    await tester.ensureVisible(moreTemplates);
    await tester.pumpAndSettle();
    await tester.tap(moreTemplates);
    await tester.pump();
    final builtTemplatesAfterPage = find.text('Open').evaluate().length;

    final foodsDraft = _draft.copyWith(
      foodLogs: List.generate(
        300,
        (index) => FoodLogDraft(
          foodLogId: 'food-$index',
          foodName: 'Food ${index + 1}',
          quantityGrams: 100,
          mealType: MealType.values[index % MealType.values.length],
          calories: 100,
          protein: 10,
          carbs: 10,
          fat: 2,
        ),
      ),
    );
    final foodTime = await _pumpPage(
      tester,
      const NutritionPage(),
      draft: foodsDraft,
    );
    final nutritionScroll = find
        .descendant(
          of: find.byKey(const ValueKey('nutrition-scroll-view')),
          matching: find.byType(Scrollable),
        )
        .first;
    final nutritionState = tester.state<ScrollableState>(nutritionScroll);
    final moreBreakfast = find.textContaining('Show more Breakfast');
    for (var scroll = 0;
        scroll < 12 && moreBreakfast.evaluate().isEmpty;
        scroll++) {
      nutritionState.position.jumpTo(
        (nutritionState.position.pixels + 500).clamp(
          0,
          nutritionState.position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
    final retainedFoodFields = find.byType(TextFormField).evaluate().length;
    expect(moreBreakfast, findsOneWidget);
    await tester.ensureVisible(moreBreakfast);
    await tester.pumpAndSettle();
    await tester.tap(moreBreakfast);
    await tester.pump();
    final retainedFoodFieldsAfterPage =
        find.byType(TextFormField).evaluate().length;

    final history = List.generate(
      300,
      (index) => WorkoutLogDraft(
        workoutLogId: index + 1,
        name: 'Completed ${index + 1}',
        notes: '',
        startedAtLabel: '2026-07-22T08:00:00Z',
        endedAtLabel: '2026-07-22T09:00:00Z',
        exercises: const [],
      ),
    );
    final historyTime = await _pumpPage(
      tester,
      const WorkoutHistoryPage(),
      draft: _draft,
      extraOverrides: [
        workoutHistoryProvider.overrideWith((ref) async => history),
      ],
    );
    final builtHistoryRows =
        find.byIcon(Icons.chevron_right_rounded).evaluate().length;
    final historyScroll = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    historyScroll.position.jumpTo(historyScroll.position.maxScrollExtent);
    await tester.pump();
    expect(tester.takeException(), isNull);

    // ignore: avoid_print
    print('PERF large_templates_us=$templateTime '
        'built_template_actions=$builtTemplateActions '
        'after_page=$builtTemplatesAfterPage large_food_day_us=$foodTime '
        'retained_food_fields=$retainedFoodFields '
        'after_page=$retainedFoodFieldsAfterPage '
        'large_history_us=$historyTime built_history_rows=$builtHistoryRows');

    expect(builtTemplateActions, 20);
    expect(builtTemplatesAfterPage, 40);
    expect(retainedFoodFields, lessThanOrEqualTo(120));
    expect(retainedFoodFieldsAfterPage, greaterThan(retainedFoodFields));
    expect(builtHistoryRows, lessThan(300),
        reason: 'history rows should be created lazily by the outer list');
  });

  testWidgets('measures large editable workout and typing rebuilds',
      (tester) async {
    final controller = _EditableDraftController(
      _draft.copyWith(
        template: _template.copyWith(
          exercises: List.generate(
            200,
            (index) => _exercise.copyWith(exerciseName: 'Exercise $index'),
          ),
        ),
      ),
    );
    final initialTime = await _pumpPage(
      tester,
      const TemplateBuilderPage(),
      draftController: controller,
    );
    final visibleEditors = find
        .widgetWithText(
          TextFormField,
          'Exercise name',
        )
        .first;
    expect(visibleEditors, findsOneWidget);

    final typing = Stopwatch()..start();
    for (var index = 0; index < 20; index++) {
      await tester.enterText(visibleEditors, 'Exercise update $index');
      await tester.pump();
    }
    typing.stop();

    // ignore: avoid_print
    print('PERF large_template_editor_us=$initialTime '
        'typing_20_updates_us=${typing.elapsedMicroseconds} '
        'template_updates=${controller.templateUpdates}');
    expect(controller.templateUpdates, 20);

    final activeSession = _activeSession.copyWith(
      exercises: List.generate(
        200,
        (index) => _exercise.copyWith(exerciseName: 'Active exercise $index'),
      ),
    );
    final activeTime = await _pumpPage(
      tester,
      const ActiveWorkoutPage(sessionId: 'performance-session'),
      activeController: _FixedActiveWorkoutController(activeSession),
    );
    final mountedExerciseLabels =
        find.textContaining(RegExp(r'^Exercise \d+$')).evaluate().length;
    // ignore: avoid_print
    print('PERF large_active_workout_us=$activeTime '
        'mounted_exercise_editors=$mountedExerciseLabels');
    expect(mountedExerciseLabels, lessThan(200));

    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<int> _pumpPage(
  WidgetTester tester,
  Widget page, {
  AppDraftState draft = _draft,
  AppDraftController? draftController,
  ActiveWorkoutController? activeController,
  List<Override> extraOverrides = const [],
}) async {
  final stopwatch = Stopwatch()..start();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        appDraftProvider.overrideWith(
          () => draftController ?? _FixedDraftController(draft),
        ),
        activeWorkoutProvider.overrideWith(
          () => activeController ?? _EmptyActiveWorkoutController(),
        ),
        nutritionInsightProvider.overrideWith((ref) async => _insight),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: JimTheme.lightTheme,
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds;
}

class _BuildCounts {
  int homeInsights = 0;
  int nutritionInsights = 0;
  int historyInsights = 0;
  int recoveryInsights = 0;
  int activeWorkoutBuilds = 0;
}

class _PerformanceDraftController extends AppDraftController {
  @override
  Future<AppDraftState> build() async => _draft;
}

class _FixedDraftController extends AppDraftController {
  _FixedDraftController(this.draft);

  final AppDraftState draft;

  @override
  Future<AppDraftState> build() async => draft;
}

class _EditableDraftController extends _FixedDraftController {
  _EditableDraftController(super.draft);

  int templateUpdates = 0;

  @override
  Future<void> updateExercise(
    int index,
    WorkoutExerciseDraft exercise,
  ) async {
    templateUpdates++;
    final current = state.requireValue;
    final exercises = [...current.template.exercises];
    exercises[index] = exercise;
    state = AsyncData(
      current.copyWith(
        template: current.template.copyWith(exercises: exercises),
      ),
    );
  }
}

class _EmptyActiveWorkoutController extends ActiveWorkoutController {
  @override
  Future<ActiveWorkoutState> build() async => const ActiveWorkoutState();
}

class _FixedActiveWorkoutController extends ActiveWorkoutController {
  _FixedActiveWorkoutController(this.session);

  final ActiveWorkoutSession session;

  @override
  Future<ActiveWorkoutState> build() async => ActiveWorkoutState(
        session: session,
      );
}

class _CountingActiveWorkoutController extends ActiveWorkoutController {
  _CountingActiveWorkoutController(this.counts);

  final _BuildCounts counts;

  @override
  Future<ActiveWorkoutState> build() async {
    counts.activeWorkoutBuilds++;
    return const ActiveWorkoutState();
  }
}

const _insight = AtlasInsight(
  title: 'Fixture insight',
  mainText: 'Fixture body',
  confidence: AtlasConfidence.high,
);

const _exercise = WorkoutExerciseDraft(
  exerciseId: 1,
  exerciseName: 'Squat',
  notes: '',
  targetSets: 1,
  targetReps: 5,
  sets: [
    SetDraft(
      setNumber: 1,
      weightKg: 100,
      reps: 5,
      isWarmup: false,
      isCompleted: false,
      rpe: 7,
    ),
  ],
);

const _template = WorkoutTemplateDraft(
  templateId: 1,
  name: 'Performance template',
  description: '',
  durationMinutes: 60,
  goal: '',
  exercises: [_exercise],
);

final _activeSession = ActiveWorkoutSession(
  sessionId: 'performance-session',
  sourceTemplateId: 1,
  name: 'Performance session',
  notes: '',
  exercises: const [_exercise],
  startedAt: DateTime.fromMillisecondsSinceEpoch(1753171200000, isUtc: true),
  lastCheckpointAt:
      DateTime.fromMillisecondsSinceEpoch(1753171200000, isUtc: true),
  revision: 1,
  restDeadline: null,
  localStatus: ActiveWorkoutLocalStatus.checkpointed,
  remoteStatus: ActiveWorkoutRemoteStatus.localOnly,
  lifecycle: ActiveWorkoutLifecycle.active,
);

const _draft = AppDraftState(
  session: null,
  profile: UserProfile(
    name: 'Performance fixture',
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
