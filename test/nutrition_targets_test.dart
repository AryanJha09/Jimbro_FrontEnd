import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/notifications/workout_notification_service.dart';
import 'package:jimbro/core/nutrition/nutrition_targets.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('estimates muscle gain targets from complete profile', () {
    const profile = UserProfile(
      name: 'Test Athlete',
      goal: 'Build muscle',
      coachingPreference: '',
      userLevel: UserLevel.intermediate,
      age: 30,
      heightCm: 180,
      weightKg: 80,
      sex: 'Male',
      availableTimeMinutes: 45,
      trainingPreference: 'Gym workouts',
      activityLevel: 'Moderately active',
      dietaryPreference: 'Help me eat more protein',
      goalTimeframe: '',
      weeksActive: 0,
      prefersVoiceLogging: false,
    );

    final estimate = NutritionTargetCalculator.estimate(profile);

    expect(estimate.hasRequiredProfile, isTrue);
    expect(estimate.bmr, 1780);
    expect(estimate.tdee, 2760);
    expect(estimate.calorieTarget, 3040);
    expect(estimate.proteinG, 152);
    expect(estimate.hydrationL, 2.8);
    expect(estimate.goalLabel, 'Moderate surplus');
  });

  test('estimates fat loss targets with a moderate deficit', () {
    const profile = UserProfile(
      name: 'Test Athlete',
      goal: 'Lose weight',
      coachingPreference: '',
      userLevel: UserLevel.beginner,
      age: 40,
      heightCm: 165,
      weightKg: 70,
      sex: 'Female',
      availableTimeMinutes: 30,
      trainingPreference: 'Home workouts',
      activityLevel: 'Mostly sitting',
      dietaryPreference: 'Keep food simple',
      goalTimeframe: '',
      weeksActive: 0,
      prefersVoiceLogging: false,
    );

    final estimate = NutritionTargetCalculator.estimate(profile);

    expect(estimate.bmr, 1370);
    expect(estimate.tdee, 1640);
    expect(estimate.calorieTarget, 1390);
    expect(estimate.proteinG, 119);
    expect(estimate.hydrationL, 2.5);
    expect(estimate.goalLabel, 'Moderate deficit');
  });

  test('handles missing profile fields without inventing targets', () {
    const profile = UserProfile(
      name: 'Test Athlete',
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
    );

    final estimate = NutritionTargetCalculator.estimate(profile);

    expect(estimate.hasRequiredProfile, isFalse);
    expect(estimate.bmr, 0);
    expect(estimate.tdee, 0);
    expect(estimate.calorieTarget, 0);
    expect(estimate.proteinG, 0);
    expect(estimate.hydrationL, 0);
  });

  test('profile changes refresh stored metrics and nutrition targets',
      () async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_ReadyAuthRepository()),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
        workoutRepositoryProvider.overrideWithValue(MockWorkoutRepository()),
        nutritionRepositoryProvider
            .overrideWithValue(MockNutritionRepository()),
        consistencyRepositoryProvider.overrideWithValue(
          MockConsistencyRepository(),
        ),
        atlasRepositoryProvider.overrideWithValue(MockAtlasRepository()),
        searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
        workoutNotificationServiceProvider.overrideWithValue(
          const NoopWorkoutNotificationService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(appDraftProvider.future);
    final controller = container.read(appDraftProvider.notifier);
    final current = container.read(appDraftProvider).value!;

    await controller.updateProfile(
      current.profile.copyWith(
        goal: 'Get stronger',
        age: 30,
        heightCm: 180,
        weightKg: 80,
        sex: 'Male',
        activityLevel: 'Moderately active',
        dietaryPreference: 'Help me eat more protein',
      ),
    );

    final updated = container.read(appDraftProvider).value!;
    expect(updated.metrics.bmr, 1780);
    expect(updated.metrics.tdee, 2760);
    expect(updated.metrics.targetCalories, 2900);
    expect(updated.metrics.proteinG, 144);
    expect(updated.metrics.hydrationL, 2.8);
    expect(updated.nutritionSummary.targetCalories, 2900);
    expect(updated.nutritionSummary.proteinTarget, 144);
    expect(updated.nutritionSummary.hydrationTargetLiters, 2.8);
  });

  test('manual food create then log uses backend payload and summary refresh',
      () async {
    final adapter = _NutritionDioAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiNutritionRepository(dio);

    final saved = await repository.saveFoodLogs(
      _liveSession,
      [
        FoodLogDraft.empty.copyWith(
          foodName: 'Paneer bowl',
          quantityGrams: 150,
          quantitySource: QuantitySource.explicit,
          mealType: MealType.lunch,
          calories: 420,
          protein: 28,
          carbs: 24,
          fat: 22,
        ),
      ],
    );
    final summary = await repository.loadSummary(_liveSession);

    expect(adapter.createdFoodPayloads, hasLength(1));
    expect(adapter.foodLogPayloads, hasLength(1));
    expect(adapter.foodLogPayloads.single, {
      'food_id': 'custom-food-1',
      'quantity_g': 150.0,
      'meal_type': 'lunch',
      'log_date': adapter.today,
      'quantity_source': 'explicit',
    });
    expect(saved.single.calories, 500);
    expect(summary.consumedCalories, 500);
    expect(summary.proteinConsumed, 35);
  });

  test('search result logs backend food id without custom food create',
      () async {
    final adapter = _NutritionDioAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiNutritionRepository(dio);

    final suggestions = await repository.searchFoods('Greek');
    await repository.saveFoodLogs(
      _liveSession,
      [
        suggestions.single.applyTo(
          FoodLogDraft.empty.copyWith(
            quantityGrams: 100,
            mealType: MealType.breakfast,
          ),
        ),
      ],
    );

    expect(suggestions.single.foodId, 'catalog-food-1');
    expect(adapter.createdFoodPayloads, isEmpty);
    expect(adapter.foodLogPayloads.single['food_id'], 'catalog-food-1');
    expect(adapter.foodLogPayloads.single['quantity_source'], 'default_100g');
  });

  test('delete removes backend log and refreshes summary', () async {
    final adapter = _NutritionDioAdapter()
      ..existingLogs = [
        {
          'food_log_id': 'log-delete',
          'food_id': 'catalog-food-1',
          'food_name': 'Greek yogurt',
          'quantity_g': 100,
          'meal_type': 'snack',
          'log_date': '2026-06-14',
          'calories_snapshot': 120,
          'protein_snapshot': 15,
          'carbs_snapshot': 8,
          'fat_snapshot': 2,
        },
      ]
      ..summaryCalories = 0
      ..summaryProtein = 0;
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiNutritionRepository(dio);

    await repository.saveFoodLogs(_liveSession, const []);
    final summary = await repository.loadSummary(_liveSession);

    expect(adapter.deletedLogIds, ['log-delete']);
    expect(summary.consumedCalories, 0);
    expect(summary.proteinConsumed, 0);
  });

  test('food summary 404 falls back to food-log list aggregation', () async {
    final adapter = _NutritionDioAdapter()
      ..summaryUnsupported = true
      ..existingLogs = [
        {
          'food_log_id': 'log-1',
          'food_id': 'food-1',
          'food_name': 'Greek yogurt',
          'quantity_g': 100,
          'meal_type': 'breakfast',
          'log_date': '2026-06-14',
          'calories_snapshot': 120,
          'protein_snapshot': 15,
          'carbs_snapshot': 8,
          'fat_snapshot': 2,
        },
        {
          'food_log_id': 'log-2',
          'food_id': 'food-2',
          'food_name': 'Rice bowl',
          'quantity_g': 200,
          'meal_type': 'lunch',
          'log_date': '2026-06-14',
          'calories_snapshot': 420,
          'protein_snapshot': 22,
          'carbs_snapshot': 65,
          'fat_snapshot': 8,
        },
      ];
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiNutritionRepository(dio);

    final summary = await repository.loadSummary(_liveSession);

    expect(adapter.summaryPaths.single, '/food-log/summary/${adapter.today}');
    expect(summary.consumedCalories, 540);
    expect(summary.proteinConsumed, 37);
    expect(summary.carbsConsumed, 73);
    expect(summary.fatConsumed, 10);
  });

  test('nutrition logs queue offline and flush food create before food log',
      () async {
    SharedPreferences.setMockInitialValues({});
    final adapter = _NutritionDioAdapter()..offlineFoodCreate = true;
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    const outbox = OfflineOutboxStore();
    final repository = FastApiNutritionRepository(dio, outbox: outbox);

    final local = await repository.saveFoodLogs(
      _liveSession,
      [
        FoodLogDraft.empty.copyWith(
          foodName: 'Offline paneer',
          quantityGrams: 150,
          quantitySource: QuantitySource.explicit,
          mealType: MealType.dinner,
          calories: 420,
          protein: 28,
          carbs: 24,
          fat: 22,
        ),
      ],
    );

    expect(local.single.foodName, 'Offline paneer');
    expect(await outbox.load(_liveSession), hasLength(1));

    adapter.offlineFoodCreate = false;
    await repository.flushPending(_liveSession);

    expect(adapter.createdFoodPayloads, hasLength(1));
    expect(adapter.foodLogPayloads, hasLength(1));
    expect(adapter.foodLogPayloads.single['food_id'], 'custom-food-1');
    expect(await outbox.load(_liveSession), isEmpty);
  });

  test('backend totals override local food row totals in live mode', () async {
    final nutritionRepository = _LiveTotalsNutritionRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_LiveAuthRepository()),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
        workoutRepositoryProvider.overrideWithValue(MockWorkoutRepository()),
        nutritionRepositoryProvider.overrideWithValue(nutritionRepository),
        consistencyRepositoryProvider.overrideWithValue(
          MockConsistencyRepository(),
        ),
        atlasRepositoryProvider.overrideWithValue(MockAtlasRepository()),
        searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
        workoutNotificationServiceProvider.overrideWithValue(
          const NoopWorkoutNotificationService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(appDraftProvider.future);

    expect(state.foodLogs.single.calories, 10);
    expect(state.nutritionSummary.consumedCalories, 777);
    expect(state.nutritionSummary.proteinConsumed, 55);
  });

  test('mock mode still locally sums food rows', () async {
    final repository = MockNutritionRepository();
    final saved = await repository.saveFoodLogs(
      null,
      [
        FoodLogDraft.empty.copyWith(
          foodName: 'Mock oats',
          quantityGrams: 100,
          mealType: MealType.breakfast,
          calories: 220,
          protein: 12,
          carbs: 36,
          fat: 5,
        ),
      ],
    );
    final summary = await repository.loadSummary(null);

    expect(saved, hasLength(1));
    expect(summary.consumedCalories, 220);
    expect(summary.proteinConsumed, 12);
  });
}

const _liveSession = AuthSession(
  userId: 'live-user',
  displayName: 'Live User',
  email: 'live@example.com',
  accessToken: 'token',
  provider: 'test',
);

class _ReadyAuthRepository extends MockAuthRepository {
  @override
  Future<AuthSession?> currentSession() async => const AuthSession(
        userId: 'test-user',
        displayName: 'Test Athlete',
        email: 'test@example.com',
        accessToken: 'token',
        provider: 'mock',
      );
}

class _LiveAuthRepository extends MockAuthRepository {
  @override
  Future<AuthSession?> currentSession() async => _liveSession;
}

class _LiveTotalsNutritionRepository implements NutritionRepository {
  @override
  Future<List<FoodLogDraft>> loadFoodLogs(AuthSession? session) async {
    return [
      FoodLogDraft.empty.copyWith(
        foodLogId: 'row-1',
        foodId: 'food-1',
        foodName: 'Backend food row',
        quantityGrams: 100,
        mealType: MealType.breakfast,
        calories: 10,
        protein: 1,
        carbs: 1,
        fat: 1,
      ),
    ];
  }

  @override
  Future<DailyNutritionSummary> loadSummary(AuthSession? session) async {
    return const DailyNutritionSummary(
      targetCalories: 0,
      consumedCalories: 777,
      proteinTarget: 0,
      proteinConsumed: 55,
      carbsTarget: 0,
      carbsConsumed: 88,
      fatTarget: 0,
      fatConsumed: 22,
      hydrationTargetLiters: 0,
      hydrationConsumedLiters: 0,
    );
  }

  @override
  Future<List<FoodSuggestion>> searchFoods(String query) async => const [];

  @override
  Future<List<FoodLogDraft>> saveFoodLogs(
    AuthSession? session,
    List<FoodLogDraft> logs,
  ) async {
    return logs;
  }

  @override
  Future<void> flushPending(AuthSession? session) async {}
}

class _NutritionDioAdapter implements HttpClientAdapter {
  final createdFoodPayloads = <Map<String, dynamic>>[];
  final foodLogPayloads = <Map<String, dynamic>>[];
  final deletedLogIds = <String>[];
  final summaryPaths = <String>[];
  List<Map<String, dynamic>> existingLogs = [];
  double summaryCalories = 500;
  double summaryProtein = 35;
  bool summaryUnsupported = false;
  bool offlineFoodCreate = false;

  String get today => DateTime.now().toIso8601String().substring(0, 10);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET' && options.path == '/food-log') {
      return _json(200, {'success': true, 'data': existingLogs});
    }
    if (options.method == 'GET' &&
        options.path.startsWith('/food-log/summary/')) {
      summaryPaths.add(options.path);
      if (summaryUnsupported) {
        return _json(404, {'detail': 'not found'});
      }
      return _json(200, {
        'success': true,
        'data': {
          'total_calories': summaryCalories,
          'total_protein': summaryProtein,
          'total_carbs': 45,
          'total_fat': 18,
        },
      });
    }
    if (options.method == 'GET' && options.path == '/food/search') {
      return _json(200, {
        'success': true,
        'data': [
          {
            'food_id': 'catalog-food-1',
            'name': 'Greek yogurt',
            'calories_per_100g': 120,
            'protein_per_100g': 15,
            'carbs_per_100g': 8,
            'fat_per_100g': 2,
            'source': 'Catalog',
          },
        ],
      });
    }
    if (options.method == 'POST' && options.path == '/food') {
      if (offlineFoodCreate) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'offline',
        );
      }
      createdFoodPayloads.add(Map<String, dynamic>.from(options.data as Map));
      return _json(200, {
        'success': true,
        'data': {
          'food_id': 'custom-food-1',
          ...createdFoodPayloads.last,
        },
      });
    }
    if (options.method == 'POST' && options.path == '/food-log') {
      foodLogPayloads.add(Map<String, dynamic>.from(options.data as Map));
      return _json(200, {
        'success': true,
        'data': {
          'food_log_id': 'log-1',
          'food_name': 'Backend owned food',
          ...foodLogPayloads.last,
          'calories_snapshot': 500,
          'protein_snapshot': 35,
          'carbs_snapshot': 45,
          'fat_snapshot': 18,
        },
      });
    }
    if (options.method == 'DELETE' && options.path.startsWith('/food-log/')) {
      deletedLogIds.add(options.path.split('/').last);
      existingLogs = const [];
      return _json(200, {'success': true, 'data': {}});
    }
    return _json(404, {'detail': 'not found'});
  }

  ResponseBody _json(int statusCode, Object body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class NoopWorkoutNotificationService implements WorkoutNotificationService {
  const NoopWorkoutNotificationService();

  @override
  Future<void> cancelReminder(WorkoutScheduleEntry entry) async {}

  @override
  Future<WorkoutReminderResult> scheduleWeeklyReminder(
    WorkoutScheduleEntry entry,
  ) async {
    return const WorkoutReminderResult(
      status: WorkoutReminderStatus.unavailable,
      message: 'Notifications disabled in test.',
    );
  }
}
