import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/features/home/presentation/home_page.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  test('maps the complete agent context contract', () {
    final snapshot = agentContextFromBackend({
      'data': {
        'user_profile': {
          'name': 'Live Athlete',
          'age': 29,
          'height_cm': 178,
          'weight_kg': 76,
          'fitness_goal': 'build_muscle',
        },
        'atlas_metrics': {
          'bmr': 1750,
          'tdee': 2550,
          'target_calories': 2700,
          'macros': {'protein_g': 170, 'carbs_g': 320, 'fat_g': 75},
          'hydration_l': 3.2,
        },
        'active_template': {
          'template_id': 9,
          'name': 'Upper A',
          'days': [
            {
              'day_label': 'Monday',
              'exercises': [
                {'exercise_id': 12, 'sets': 3, 'reps': 8},
              ],
            },
          ],
        },
        'recent_workouts': [
          {
            'workout_log_id': 41,
            'workout_name': 'Upper A',
            'started_at': '2026-06-12T10:00:00Z',
            'ended_at': '2026-06-12T10:45:00Z',
            'exercises': [],
          },
        ],
        'workout_trends': {
          'rolling_days': 28,
          'workout_count': 6,
          'total_volume_kg': 12400,
          'completed_sets': 72,
          'points': [
            {'date': '2026-06-01', 'volume_kg': 5200, 'workout_count': 3},
            {'date': '2026-06-08', 'volume_kg': 7200, 'workout_count': 3},
          ],
        },
        'todays_nutrition': {
          'totals': {
            'total_calories': 1850,
            'total_protein': 140,
            'total_carbs': 180,
            'total_fat': 55,
          },
        },
      },
    });

    expect(snapshot.userProfile?.name, 'Live Athlete');
    expect(snapshot.atlasMetrics?.targetCalories, 2700);
    expect(snapshot.activeTemplate?.templateId, 9);
    expect(snapshot.recentWorkouts.single.workoutLogId, 41);
    expect(snapshot.workoutTrends.totalVolumeKg, 12400);
    expect(snapshot.todaysNutrition?.consumedCalories, 1850);
  });

  test('falls back to individual dashboard endpoints when context is absent',
      () async {
    final adapter = _ContextFallbackAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;

    final snapshot = await FastApiAgentContextRepository(dio).load(_session);

    expect(snapshot.usedFallbackEndpoints, isTrue);
    expect(snapshot.atlasMetrics?.targetCalories, 2400);
    expect(snapshot.todaysNutrition?.consumedCalories, 1850);
    expect(snapshot.workoutTrends.workoutCount, 5);
    expect(snapshot.recentWorkouts.single.name, 'Pull Day');
    expect(snapshot.activeTemplate?.name, 'Live Template');
    expect(adapter.paths.first, '/agent/context');
  });

  testWidgets(
      'Home prefers backend metrics and daily summary without demo copy',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDraftProvider.overrideWith(_HomeDraftController.new),
          agentContextRepositoryProvider.overrideWithValue(
            const _FixedContextRepository(),
          ),
          atlasRepositoryProvider.overrideWithValue(MockAtlasRepository()),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1850 / 2400 kcal'), findsWidgets);
    expect(find.text('140 / 165 g'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Hydration'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('0.0 / 3.0 L'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('demo'), findsNothing);
    expect(find.textContaining('prototype'), findsNothing);
  });
}

const _session = AuthSession(
  userId: 'live-user',
  displayName: 'Live Athlete',
  email: 'live@example.com',
  accessToken: 'test-token',
  provider: 'fastapi',
);

const _metrics = UserStaticMetrics(
  bmr: 1700,
  tdee: 2300,
  targetCalories: 2400,
  maintenanceCalories: 2300,
  cutCalories: 2000,
  bulkCalories: 2600,
  proteinG: 165,
  carbsG: 280,
  fatG: 70,
  hydrationL: 3,
  cutIntensity: 'Atlas metrics',
);

class _HomeDraftController extends AppDraftController {
  @override
  Future<AppDraftState> build() async => const AppDraftState(
        session: _session,
        profile: UserProfile(
          name: 'Local Athlete',
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
          targetCalories: 9999,
          maintenanceCalories: 0,
          cutCalories: 0,
          bulkCalories: 0,
          proteinG: 999,
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
        nutritionSummary: DailyNutritionSummary(
          targetCalories: 9999,
          consumedCalories: 1,
          proteinTarget: 999,
          proteinConsumed: 1,
          carbsTarget: 0,
          carbsConsumed: 0,
          fatTarget: 0,
          fatConsumed: 0,
          hydrationTargetLiters: 0,
          hydrationConsumedLiters: 0,
        ),
        consistency: ConsistencyState(
          currentStreak: 0,
          longestStreak: 0,
          weeklyCheckins: 0,
          totalLogs: 0,
        ),
        search: SearchState(query: '', groups: []),
      );
}

class _FixedContextRepository implements AgentContextRepository {
  const _FixedContextRepository();

  @override
  Future<AgentContextSnapshot> load(AuthSession? session) async {
    final now = DateTime.now();
    final recent = [0, 1]
        .map(
          (daysAgo) => WorkoutLogDraft(
            workoutLogId: daysAgo + 1,
            name: 'Saved workout ${daysAgo + 1}',
            notes: '',
            startedAtLabel:
                now.subtract(Duration(days: daysAgo)).toIso8601String(),
            endedAtLabel:
                now.subtract(Duration(days: daysAgo)).toIso8601String(),
            exercises: const [
              WorkoutExerciseDraft(
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
                    isCompleted: true,
                    rpe: 8,
                  ),
                ],
              ),
            ],
          ),
        )
        .toList(growable: false);
    return AgentContextSnapshot(
      atlasMetrics: _metrics,
      recentWorkouts: recent,
      workoutTrends: const WorkoutTrendSummary(
        rollingDays: 28,
        workoutCount: 2,
        totalVolumeKg: 1000,
        completedSets: 2,
        points: [
          WorkoutTrendPoint(
            label: 'This week',
            volumeKg: 1000,
            workoutCount: 2,
          ),
        ],
      ),
      todaysNutrition: const DailyNutritionSummary(
        targetCalories: 0,
        consumedCalories: 1850,
        proteinTarget: 0,
        proteinConsumed: 140,
        carbsTarget: 0,
        carbsConsumed: 180,
        fatTarget: 0,
        fatConsumed: 55,
        hydrationTargetLiters: 0,
        hydrationConsumedLiters: 0,
      ),
    );
  }
}

class _ContextFallbackAdapter implements HttpClientAdapter {
  final paths = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    if (options.path == '/food-log/summary/${_today()}') {
      return _json({
        'data': {'total_calories': 1850, 'total_protein': 140},
      });
    }
    switch (options.path) {
      case '/agent/context':
        return _json({'detail': 'Not found'}, statusCode: 404);
      case '/atlas/metrics':
        return _json({
          'data': {
            'target_calories': 2400,
            'protein_g': 165,
            'hydration_l': 3,
          },
        });
      case '/workout-logs/trends':
        return _json({
          'data': {'rolling_days': 28, 'workout_count': 5},
        });
      case '/workout-logs':
        return _json({
          'data': [
            {
              'workout_log_id': 7,
              'workout_name': 'Pull Day',
              'started_at': '2026-06-12T10:00:00Z',
              'ended_at': '2026-06-12T11:00:00Z',
              'exercises': [],
            },
          ],
        });
      case '/workout-templates':
        return _json({
          'data': [
            {'template_id': 3, 'name': 'Live Template', 'exercises': []},
          ],
        });
    }
    return _json({'data': []});
  }

  ResponseBody _json(
    Map<String, Object?> body, {
    int statusCode = 200,
  }) {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

String _today() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
