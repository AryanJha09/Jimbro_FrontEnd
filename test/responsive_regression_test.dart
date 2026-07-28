import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/core/theme/jim_theme.dart';
import 'package:jimbro/features/history/presentation/history_page.dart';
import 'package:jimbro/features/home/presentation/home_page.dart';
import 'package:jimbro/features/nutrition/presentation/nutrition_page.dart';
import 'package:jimbro/features/onboarding/presentation/onboarding_page.dart';
import 'package:jimbro/features/profile/presentation/profile_page.dart';
import 'package:jimbro/features/workouts/application/active_workout_controller.dart';
import 'package:jimbro/features/workouts/presentation/workouts_page.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  final viewports = <_ViewportCase>[
    for (final width in const [320.0, 375.0, 430.0]) ...[
      _ViewportCase(
        label: '${width.toInt()} short portrait 1.0x',
        size: Size(width, 568),
        textScale: 1,
      ),
      _ViewportCase(
        label: '${width.toInt()} normal portrait 1.3x',
        size: Size(width, 812),
        textScale: 1.3,
      ),
      _ViewportCase(
        label: '${width.toInt()} portrait 2.0x',
        size: Size(width, 812),
        textScale: 2,
      ),
      _ViewportCase(
        label: '${width.toInt()} short landscape 1.3x',
        size: Size(568, width),
        textScale: 1.3,
      ),
      _ViewportCase(
        label: '${width.toInt()} landscape 2.0x',
        size: Size(812, width),
        textScale: 2,
      ),
    ],
  ];

  final authenticatedScreens = <({String name, Widget widget})>[
    (name: 'Home', widget: const HomePage()),
    (name: 'Workouts library', widget: const WorkoutsPage()),
    (name: 'Template builder', widget: const TemplateBuilderPage()),
    (
      name: 'Active workout',
      widget: const ActiveWorkoutPage(sessionId: 'fixture-session'),
    ),
    (name: 'Nutrition', widget: const NutritionPage()),
    (name: 'Profile', widget: const ProfilePage()),
    (name: 'History/Analytics', widget: const HistoryPage()),
  ];

  for (final viewport in viewports) {
    for (final screen in authenticatedScreens) {
      testWidgets('${screen.name}: ${viewport.label}', (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.binding.setSurfaceSize(viewport.size);
        await _pumpFixture(
          tester,
          screen.widget,
          viewport: viewport,
        );
        await _exerciseScrollableContent(tester);
        _expectNoLayoutException(
          tester,
          reason: '${screen.name}: ${viewport.label}',
        );
      });
    }
  }

  const keyboardViewport = _ViewportCase(
    label: '320 keyboard 2.0x',
    size: Size(320, 568),
    textScale: 2,
    keyboardHeight: 260,
  );
  for (final screen in <({String name, Widget widget})>[
    (name: 'Template builder', widget: const TemplateBuilderPage()),
    (
      name: 'Active workout',
      widget: const ActiveWorkoutPage(sessionId: 'fixture-session'),
    ),
    (name: 'Nutrition search/results', widget: const NutritionPage()),
    (name: 'Profile', widget: const ProfilePage()),
  ]) {
    testWidgets('${screen.name}: ${keyboardViewport.label}', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(keyboardViewport.size);
      await _pumpFixture(tester, screen.widget, viewport: keyboardViewport);
      await _exerciseScrollableContent(tester);
      _expectNoLayoutException(
        tester,
        reason: '${screen.name}: ${keyboardViewport.label}',
      );
    });
  }

  for (final viewport in viewports) {
    testWidgets('Onboarding: ${viewport.label}', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(viewport.size);
      await _pumpFixture(
        tester,
        const OnboardingPreviewPage(),
        viewport: viewport,
      );
      await _exerciseScrollableContent(tester);
      _expectNoLayoutException(
        tester,
        reason: 'Onboarding: ${viewport.label}',
      );
    });
  }

  testWidgets('authenticated pages render loading and error states safely',
      (tester) async {
    const viewport = _ViewportCase(
      label: '320 short portrait 2.0x',
      size: Size(320, 568),
      textScale: 2,
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(viewport.size);

    for (final state in _FixtureProviderState.values) {
      for (final screen in <Widget>[
        const HomePage(),
        const WorkoutsPage(),
        const NutritionPage(),
        const ProfilePage(),
        const HistoryPage(),
      ]) {
        await _pumpFixture(
          tester,
          screen,
          viewport: viewport,
          providerState: state,
        );
        _expectNoLayoutException(
          tester,
          reason: '${screen.runtimeType} ${state.name}',
        );
      }
    }
  });

  testWidgets('authenticated pages render empty states safely', (tester) async {
    const viewport = _ViewportCase(
      label: '320 short portrait 2.0x',
      size: Size(320, 568),
      textScale: 2,
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(viewport.size);
    for (final screen in authenticatedScreens) {
      await _pumpFixture(
        tester,
        screen.widget,
        viewport: viewport,
        providerState: _FixtureProviderState.empty,
      );
      await _exerciseScrollableContent(tester);
      _expectNoLayoutException(
        tester,
        reason: '${screen.name} empty state',
      );
    }
  });

  testWidgets('food search exposes loading, result, empty, and error states',
      (tester) async {
    const viewport = _ViewportCase(
      label: '320 short portrait 2.0x',
      size: Size(320, 568),
      textScale: 2,
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(viewport.size);
    await _pumpFixture(
      tester,
      const NutritionPage(),
      viewport: viewport,
      providerState: _FixtureProviderState.search,
    );
    final field = find.byKey(const ValueKey('food-name-field-0'));
    await tester.scrollUntilVisible(
      field,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('nutrition-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();

    await tester.enterText(field, 'greek');
    await tester.pump();
    expect(find.text('Searching foods...'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Greek Yogurt Result'), findsOneWidget);

    await tester.enterText(field, 'none');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('No food results found.'), findsOneWidget);

    await tester.enterText(field, 'error');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    _expectNoLayoutException(tester, reason: 'food search state transitions');
  });
}

enum _FixtureProviderState { data, empty, search, loading, error }

class _ViewportCase {
  const _ViewportCase({
    required this.label,
    required this.size,
    required this.textScale,
    this.keyboardHeight = 0,
  });

  final String label;
  final Size size;
  final double textScale;
  final double keyboardHeight;
}

Future<void> _pumpFixture(
  WidgetTester tester,
  Widget screen, {
  required _ViewportCase viewport,
  _FixtureProviderState providerState = _FixtureProviderState.data,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDraftProvider.overrideWith(
          () => _FixtureDraftController(providerState),
        ),
        activeWorkoutProvider.overrideWith(_FixtureActiveWorkoutController.new),
        workoutRepositoryProvider.overrideWithValue(
          _FixtureWorkoutRepository(),
        ),
      ],
      child: MaterialApp(
        theme: JimTheme.lightTheme,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(viewport.textScale),
              viewInsets: EdgeInsets.only(bottom: viewport.keyboardHeight),
            ),
            child: child!,
          );
        },
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _exerciseScrollableContent(WidgetTester tester) async {
  for (var pass = 0; pass < 12; pass++) {
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) {
      break;
    }
    await tester.drag(scrollables.first, const Offset(0, -360));
    await tester.pump();
  }
  for (var pass = 0; pass < 12; pass++) {
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) {
      break;
    }
    await tester.drag(scrollables.first, const Offset(0, 360));
    await tester.pump();
  }
}

void _expectNoLayoutException(
  WidgetTester tester, {
  required String reason,
}) {
  final exceptions = <Object>[];
  Object? exception;
  while ((exception = tester.takeException()) != null) {
    exceptions.add(exception!);
  }
  expect(
    exceptions,
    isEmpty,
    reason: '$reason\n${exceptions.join('\n\n')}',
  );
}

class _FixtureDraftController extends AppDraftController {
  _FixtureDraftController(this.fixtureState);

  final _FixtureProviderState fixtureState;

  @override
  Future<AppDraftState> build() async {
    switch (fixtureState) {
      case _FixtureProviderState.data:
        return _largeDraft;
      case _FixtureProviderState.empty:
        return _emptyDraft;
      case _FixtureProviderState.search:
        return _searchDraft;
      case _FixtureProviderState.loading:
        return Completer<AppDraftState>().future;
      case _FixtureProviderState.error:
        throw StateError('fixture load failed');
    }
  }

  @override
  Future<List<FoodSuggestion>> searchFoodSuggestions(String query) async {
    switch (query.trim().toLowerCase()) {
      case 'none':
        return const [];
      case 'error':
        throw StateError('fixture search failed');
      default:
        return const [
          FoodSuggestion(
            foodId: 'fixture-food',
            name: 'Greek Yogurt Result',
            caloriesPer100g: 59,
            proteinPer100g: 10,
            carbsPer100g: 3.6,
            fatPer100g: 0.4,
            source: 'fixture',
          ),
        ];
    }
  }
}

class _FixtureActiveWorkoutController extends ActiveWorkoutController {
  @override
  Future<ActiveWorkoutState> build() async => ActiveWorkoutState(
        session: _activeSession,
      );
}

class _FixtureWorkoutRepository extends MockWorkoutRepository
    implements WorkoutHistoryRepository {
  @override
  Future<List<WorkoutLogDraft>> loadWorkoutHistory(
    AuthSession? session, {
    int limit = 50,
    int offset = 0,
  }) async =>
      List<WorkoutLogDraft>.generate(
        120,
        (index) => _completedWorkout.copyWith(
          workoutLogId: index + 1,
          name: 'Completed workout ${index + 1}',
        ),
      );
}

const _longText =
    'A deliberately long user-entered value that must wrap without pushing actions beyond the viewport';

const _session = AuthSession(
  userId: 'fixture-user',
  displayName: _longText,
  email: 'fixture@example.test',
  accessToken: 'fixture-token',
  provider: 'mock',
);

const _sets = [
  SetDraft(
    setNumber: 1,
    weightKg: 125.5,
    reps: 12,
    isWarmup: false,
    isCompleted: true,
    rpe: 9,
  ),
  SetDraft(
    setNumber: 2,
    weightKg: 125.5,
    reps: 10,
    isWarmup: false,
    isCompleted: false,
    rpe: 8,
  ),
];

const _exercise = WorkoutExerciseDraft(
  exerciseId: 1,
  exerciseName: _longText,
  notes: _longText,
  targetSets: 2,
  targetReps: 12,
  sets: _sets,
);

const _template = WorkoutTemplateDraft(
  templateId: 1,
  name: _longText,
  description: _longText,
  durationMinutes: 90,
  goal: _longText,
  exercises: [_exercise, _exercise, _exercise],
);

const _completedWorkout = WorkoutLogDraft(
  workoutLogId: 1,
  templateId: 1,
  name: _longText,
  notes: _longText,
  startedAtLabel: '2026-07-22T08:00:00.000Z',
  endedAtLabel: '2026-07-22T09:30:00.000Z',
  exercises: [_exercise, _exercise, _exercise],
);

final _largeDraft = AppDraftState(
  session: _session,
  profile: const UserProfile(
    name: _longText,
    goal: _longText,
    coachingPreference: _longText,
    userLevel: UserLevel.advanced,
    age: 29,
    heightCm: 181,
    weightKg: 84,
    sex: 'Prefer not to say',
    availableTimeMinutes: 90,
    trainingPreference: 'A flexible mix',
    activityLevel: 'Very active',
    dietaryPreference: 'omnivore',
    goalTimeframe: _longText,
    weeksActive: 999,
    prefersVoiceLogging: false,
  ),
  metrics: const UserStaticMetrics(
    bmr: 1999,
    tdee: 3199,
    targetCalories: 3499,
    maintenanceCalories: 3199,
    cutCalories: 2699,
    bulkCalories: 3499,
    proteinG: 220,
    carbsG: 430,
    fatG: 110,
    hydrationL: 4.5,
    cutIntensity: 'moderate',
  ),
  template: _template,
  templates: List<WorkoutTemplateDraft>.generate(
    120,
    (index) => _template.copyWith(
      templateId: index + 1,
      name: 'Template ${index + 1}: $_longText',
    ),
  ),
  workoutSchedule: const [
    WorkoutScheduleEntry(
      scheduleId: 'fixture-schedule',
      templateId: 1,
      templateName: _longText,
      weekday: DateTime.wednesday,
      timeLabel: '18:00',
    ),
  ],
  workoutLog: _completedWorkout,
  foodLogs: List<FoodLogDraft>.generate(
    120,
    (index) => FoodLogDraft(
      foodLogId: 'food-$index',
      foodId: 'catalog-$index',
      logDate: DateTime(2026, 7, 22),
      quantitySource: QuantitySource.explicit,
      foodName: 'Food ${index + 1}: $_longText',
      quantityGrams: 9999,
      mealType: MealType.values[index % MealType.values.length],
      calories: 9999,
      protein: 999,
      carbs: 999,
      fat: 999,
    ),
  ),
  nutritionSummary: const DailyNutritionSummary(
    targetCalories: 3499,
    consumedCalories: 99999,
    proteinTarget: 220,
    proteinConsumed: 9999,
    carbsTarget: 430,
    carbsConsumed: 9999,
    fatTarget: 110,
    fatConsumed: 9999,
    hydrationTargetLiters: 4.5,
    hydrationConsumedLiters: 12.5,
  ),
  consistency: const ConsistencyState(
    currentStreak: 9999,
    longestStreak: 99999,
    weeklyCheckins: 7,
    totalLogs: 999999,
  ),
);

final _emptyDraft = _largeDraft.copyWith(
  template: WorkoutTemplateDraft.empty,
  templates: const [],
  workoutSchedule: const [],
  workoutLog: WorkoutLogDraft.empty,
  foodLogs: const [],
  nutritionSummary: DailyNutritionSummary.empty,
  consistency: const ConsistencyState(
    currentStreak: 0,
    longestStreak: 0,
    weeklyCheckins: 0,
    totalLogs: 0,
  ),
);

final _searchDraft = _emptyDraft.copyWith(
  foodLogs: [FoodLogDraft.empty.copyWith(mealType: MealType.breakfast)],
);

final _activeSession = ActiveWorkoutSession(
  sessionId: 'fixture-session',
  sourceTemplateId: 1,
  name: _longText,
  notes: _longText,
  exercises: [_exercise, _exercise, _exercise],
  startedAt: _fixtureStartedAt,
  lastCheckpointAt: _fixtureStartedAt,
  revision: 4,
  restDeadline: null,
  localStatus: ActiveWorkoutLocalStatus.checkpointed,
  remoteStatus: ActiveWorkoutRemoteStatus.localOnly,
  lifecycle: ActiveWorkoutLifecycle.active,
);

final _fixtureStartedAt =
    DateTime.fromMillisecondsSinceEpoch(1753171200000, isUtc: true);
