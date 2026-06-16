import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/notifications/workout_notification_service.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/shared/models/app_models.dart';
import 'package:jimbro/shared/models/onboarding_models.dart';

void main() {
  test('maps guided onboarding answers to backend-safe Atlas payload', () {
    final payload = atlasOnboardingPayloadFromProfile(
      _profile.copyWith(sex: 'Prefer not to say'),
      answers: const OnboardingAnswersDto(
        age: 31,
        sex: OnboardingSex.male,
        heightCm: 181,
        weightKg: 82,
        fitnessGoal: OnboardingFitnessGoal.getStronger,
        experienceLevel: OnboardingExperienceLevel.regular,
        activityLevel: OnboardingActivityLevel.moderatelyActive,
        availableTimeMin: 30,
        trainingPreference: OnboardingTrainingPreference.home,
        dietaryPreference: OnboardingDietaryPreference.simple,
      ),
    );

    expect(payload, {
      'age': 31,
      'height_cm': 181.0,
      'weight_kg': 82.0,
      'activity_level': 'moderately_active',
      'fitness_goal': 'get_stronger',
      'experience_level': 'intermediate',
      'available_time_min': 30,
      'equipment_access': 'home',
      'constraints': ['short_sessions', 'home_equipment', 'simple_meals'],
      'generate_program': true,
      'sex': 'male',
    });
  });

  test('unsupported sex is not sent as invalid Atlas enum', () {
    final payload = atlasOnboardingPayloadFromProfile(
      _profile.copyWith(sex: 'Prefer not to say'),
      answers: const OnboardingAnswersDto(
        age: 31,
        sex: OnboardingSex.preferNotToSay,
        heightCm: 181,
        weightKg: 82,
        fitnessGoal: OnboardingFitnessGoal.buildMuscle,
        experienceLevel: OnboardingExperienceLevel.justStarting,
        activityLevel: OnboardingActivityLevel.lightlyActive,
        availableTimeMin: 45,
        trainingPreference: OnboardingTrainingPreference.mixed,
      ),
    );

    expect(payload.containsKey('sex'), isFalse);
  });

  test('successful Atlas onboarding stores returned metrics', () async {
    final adapter = _AtlasAdapter();
    final container = _containerWithAtlas(adapter);
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);

    final result = await container
        .read(appDraftProvider.notifier)
        .completeOnboardingProfile(
          profile: _profile,
          answers: _answers,
        );

    final state = container.read(appDraftProvider).value!;
    expect(adapter.lastOnboardPayload?['generate_program'], isTrue);
    expect(adapter.lastOnboardPayload?['sex'], 'male');
    expect(result?.warning, isNull);
    expect(state.profile.goal, _profile.goal);
    expect(state.metrics.bmr, 1800);
    expect(state.metrics.tdee, 2700);
    expect(state.metrics.targetCalories, 2850);
    expect(state.metrics.proteinG, 160);
    expect(state.nutritionSummary.targetCalories, 2850);
    expect(state.nutritionSummary.proteinTarget, 160);
  });

  test('profile PATCH sends changed Atlas fields and refreshes metrics',
      () async {
    final adapter = _AtlasAdapter();
    final container = _containerWithAtlas(adapter);
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);
    final controller = container.read(appDraftProvider.notifier);

    await controller.updateProfile(_profile);
    await controller.updateProfile(
      _profile.copyWith(
        weightKg: 84,
        sex: 'Prefer not to say',
        activityLevel: 'Very active',
      ),
    );

    expect(adapter.lastPatchPayload?['weight_kg'], 84.0);
    expect(adapter.lastPatchPayload?['activity_level'], 'very_active');
    expect(adapter.lastPatchPayload?.containsKey('sex'), isFalse);
    final state = container.read(appDraftProvider).value!;
    expect(state.metrics.targetCalories, 2850);
    expect(state.nutritionSummary.hydrationTargetLiters, 3.1);
  });

  test('mock mode still falls back to local target formulas', () async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_ReadyAuthRepository('mock')),
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
          const _NoopWorkoutNotificationService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);

    final result =
        await container.read(appDraftProvider.notifier).updateProfile(
              _profile,
            );

    expect(result?.warning, isNull);
    expect(
      container.read(appDraftProvider).value!.metrics.targetCalories,
      greaterThan(0),
    );
    expect(container.read(appDraftProvider).value!.profile.goal, _profile.goal);
  });
}

const _answers = OnboardingAnswersDto(
  age: 30,
  sex: OnboardingSex.male,
  heightCm: 180,
  weightKg: 80,
  fitnessGoal: OnboardingFitnessGoal.getStronger,
  experienceLevel: OnboardingExperienceLevel.regular,
  activityLevel: OnboardingActivityLevel.moderatelyActive,
  availableTimeMin: 45,
  trainingPreference: OnboardingTrainingPreference.gym,
);

const _profile = UserProfile(
  name: 'Test Athlete',
  goal: 'Get stronger',
  coachingPreference: 'Simple coaching',
  userLevel: UserLevel.intermediate,
  age: 30,
  heightCm: 180,
  weightKg: 80,
  sex: 'Male',
  availableTimeMinutes: 45,
  trainingPreference: 'Gym workouts',
  activityLevel: 'Moderately active',
  dietaryPreference: 'Prioritize protein',
  goalTimeframe: '',
  weeksActive: 0,
  prefersVoiceLogging: false,
);

ProviderContainer _containerWithAtlas(_AtlasAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.example.test/api/v1',
      validateStatus: (status) => status != null && status < 500,
    ),
  )..httpClientAdapter = adapter;
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_ReadyAuthRepository('fastapi')),
      profileRepositoryProvider.overrideWithValue(
        FastApiProfileRepository(dio, MockProfileRepository()),
      ),
      workoutRepositoryProvider.overrideWithValue(MockWorkoutRepository()),
      nutritionRepositoryProvider.overrideWithValue(MockNutritionRepository()),
      consistencyRepositoryProvider
          .overrideWithValue(MockConsistencyRepository()),
      atlasRepositoryProvider.overrideWithValue(MockAtlasRepository()),
      searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
      workoutNotificationServiceProvider.overrideWithValue(
        const _NoopWorkoutNotificationService(),
      ),
    ],
  );
}

class _ReadyAuthRepository implements AuthRepository {
  const _ReadyAuthRepository(this.provider);

  final String provider;

  @override
  Future<AuthSession?> currentSession() async => AuthSession(
        userId: 'test-user',
        displayName: 'Test User',
        email: 'test@example.com',
        accessToken: 'test-token',
        provider: provider,
      );

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return (await currentSession())!;
  }

  @override
  Future<AuthSession> signInWithMockProvider(String provider) async {
    return (await currentSession())!;
  }

  @override
  Future<void> signOut() async {}
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

class _AtlasAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastOnboardPayload;
  Map<String, dynamic>? lastPatchPayload;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET' && options.path == '/supabase/profile') {
      return _json({
        'success': true,
        'data': {
          'username': 'Test User',
          'age': 30,
          'height_cm': 180,
          'weight_kg': 80,
          'sex': 'Male',
          'goal': 'Get stronger',
          'activity_level': 'Moderately active',
        },
      });
    }
    if (options.method == 'POST' && options.path == '/atlas/onboard') {
      lastOnboardPayload = Map<String, dynamic>.from(options.data as Map);
      return _json({'success': true, 'data': _metrics});
    }
    if (options.method == 'PATCH' && options.path == '/atlas/profile') {
      lastPatchPayload = Map<String, dynamic>.from(options.data as Map);
      return _json({'success': true, 'data': {}});
    }
    if (options.method == 'GET' && options.path == '/atlas/metrics') {
      return _json({'success': true, 'data': _metrics});
    }
    return _json({'success': true, 'data': []});
  }

  ResponseBody _json(Map<String, Object?> body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

const _metrics = {
  'bmr': 1800,
  'tdee': 2700,
  'target_calories': 2850,
  'maintenance_calories': 2700,
  'cut_calories': 2350,
  'bulk_calories': 2950,
  'macros': {
    'protein_g': 160,
    'carbs_g': 330,
    'fat_g': 80,
  },
  'hydration_l': 3.1,
  'summary': 'Atlas metrics',
};
