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
      account: _account,
    );

    expect(payload, {
      'username': 'Test Athlete',
      'email': 'test@example.com',
      'password': 'test-password',
      'age': 31,
      'height_cm': 181.0,
      'weight_kg': 82.0,
      'activity_level': 'moderately_active',
      'fitness_goal': 'athletic_performance',
      'experience_level': 'intermediate',
      'available_time_min': 30,
      'equipment_access': 'home_gym',
      'constraints_json': [
        'short_sessions',
        'home_equipment',
        'simple_meals',
      ],
      'sex': 'male',
    });
    expect(payload.containsKey('constraints'), isFalse);
    expect(payload.containsKey('generate_program'), isFalse);
  });

  test('canonical enum serializer maps UI labels to backend values', () {
    expect(
      BackendProfileEnums.fromValues(
        goal: 'Lose fat',
        activityLevel: 'Mostly sitting',
        equipmentAccess: 'Gym',
        experienceLevel: 'Beginner',
      ).fitnessGoal,
      'lose_fat',
    );
    expect(
      BackendProfileEnums.fromValues(
        goal: 'Build muscle',
        activityLevel: 'Mostly sitting',
        equipmentAccess: 'Gym',
        experienceLevel: 'Beginner',
      ).fitnessGoal,
      'gain_muscle',
    );
    expect(
      BackendProfileEnums.fromValues(
        goal: 'Get stronger',
        activityLevel: 'Mostly sitting',
        equipmentAccess: 'Gym',
        experienceLevel: 'Intermediate',
      ),
      isA<BackendProfileEnums>()
          .having((value) => value.fitnessGoal, 'fitness goal',
              'athletic_performance')
          .having((value) => value.activityLevel, 'activity level', 'sedentary')
          .having(
              (value) => value.equipmentAccess, 'equipment access', 'full_gym'),
    );
    expect(
      BackendProfileEnums.fromValues(
        goal: 'Maintain',
        activityLevel: 'Lightly active',
        equipmentAccess: 'Home',
        experienceLevel: 'Beginner',
      ).experienceLevel,
      'novice',
    );
    expect(
      BackendProfileEnums.fromValues(
        goal: 'Maintain',
        activityLevel: 'Lightly active',
        equipmentAccess: 'Home',
        experienceLevel: 'Advanced Beginner',
      ).experienceLevel,
      'advanced_beginner',
    );
    expect(
      BackendProfileEnums.fromValues(
        goal: 'Maintain',
        activityLevel: 'Lightly active',
        equipmentAccess: 'Home',
        experienceLevel: 'Intermediate',
      ).experienceLevel,
      'intermediate',
    );
    expect(
      BackendProfileEnums.fromValues(
        goal: 'Maintain',
        activityLevel: 'Lightly active',
        equipmentAccess: 'Home',
        experienceLevel: 'Advanced',
      ).experienceLevel,
      'expert',
    );
  });

  test('profile save uses the same canonical backend enums as onboarding', () {
    final payload = profileBackendPayload(
      _profile.copyWith(
        goal: 'Build muscle',
        activityLevel: 'Mostly sitting',
        trainingPreference: 'Gym',
        userLevel: UserLevel.advanced,
      ),
    );

    expect(payload['fitness_goal'], 'gain_muscle');
    expect(payload['activity_level'], 'sedentary');
    expect(payload['equipment_access'], 'full_gym');
    expect(payload['experience_level'], 'expert');
    expect(payload.containsKey('goal'), isFalse);
    expect(payload.containsKey('training_preference'), isFalse);
    expect(payload.containsKey('user_level'), isFalse);
  });

  test('fresh local profile wins over a stale backend profile response',
      () async {
    final adapter = _AtlasAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiProfileRepository(dio, MockProfileRepository());
    const session = AuthSession(
      userId: 'fresh-profile-user',
      displayName: 'Test User',
      email: 'test@example.com',
      accessToken: 'test-token',
      provider: 'fastapi',
    );

    await repository.saveProfile(session, _profile);
    final loaded = await repository.loadProfile(session);

    expect(loaded.name, _profile.name);
    expect(loaded.goal, _profile.goal);
    expect(adapter.profileGetCalls, 0);
  });

  test('profile patch uses canonical experience-level serialization', () {
    final payload = atlasProfilePatchPayload(
      previous: _profile,
      next: _profile.copyWith(userLevel: UserLevel.advanced),
    );

    expect(payload['experience_level'], 'expert');
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
      account: _account,
    );

    expect(payload.containsKey('sex'), isFalse);
  });

  test('successful Atlas onboarding stores returned metrics', () async {
    final adapter = _AtlasAdapter();
    final container = _containerWithAtlas(adapter);
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);
    await container.read(appDraftProvider.notifier).signInWithEmailPassword(
          email: 'test@example.com',
          password: 'test-password',
        );

    final result = await container
        .read(appDraftProvider.notifier)
        .completeOnboardingProfile(
          profile: _profile,
          answers: _answers,
        );

    final state = container.read(appDraftProvider).value!;
    expect(adapter.lastOnboardPayload?['username'], 'Test Athlete');
    expect(adapter.lastOnboardPayload?['email'], 'test@example.com');
    expect(adapter.lastOnboardPayload?['password'], 'test-password');
    expect(adapter.lastOnboardPayload?['constraints_json'], isA<List>());
    expect(
        adapter.lastOnboardPayload?.containsKey('generate_program'), isFalse);
    expect(adapter.lastOnboardPayload?.containsKey('constraints'), isFalse);
    expect(adapter.lastOnboardPayload?['sex'], 'male');
    expect(result?.warning, isNull);
    expect(state.profile.name, _profile.name);
    expect(state.profile.goal, _profile.goal);
    expect(state.profile.age, _profile.age);
    expect(state.profile.heightCm, _profile.heightCm);
    expect(state.profile.weightKg, _profile.weightKg);
    expect(state.profile.activityLevel, _profile.activityLevel);
    expect(state.profile.trainingPreference, _profile.trainingPreference);
    expect(state.metrics.bmr, 1800);
    expect(state.metrics.tdee, 2700);
    expect(state.metrics.targetCalories, 2850);
    expect(state.metrics.proteinG, 160);
    expect(state.nutritionSummary.targetCalories, 2850);
    expect(state.nutritionSummary.proteinTarget, 160);
    expect(state.profileSyncStatus, ProfileSyncStatus.synced);
    expect(state.atlasMetricsStatus, AtlasMetricsStatus.available);
  });

  test('live onboarding saves locally when password is unavailable', () async {
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

    expect(adapter.lastOnboardPayload, isNull);
    final state = container.read(appDraftProvider).value!;
    expect(result?.warning, contains('saved on this device'));
    expect(state.profile.name, _profile.name);
    expect(state.metrics.targetCalories, greaterThan(0));
    expect(state.nutritionSummary.targetCalories, greaterThan(0));
    expect(state.profileSyncStatus, ProfileSyncStatus.pending);
    expect(state.atlasMetricsStatus, AtlasMetricsStatus.pending);
  });

  test('Atlas metrics 404 falls back without failing app load', () async {
    final adapter = _AtlasAdapter(metricsNotFound: true);
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiProfileRepository(dio, MockProfileRepository());

    final metrics = await repository.loadAtlasMetrics(
      const AuthSession(
        userId: 'test-user',
        displayName: 'Test User',
        email: 'test@example.com',
        accessToken: 'test-token',
        provider: 'fastapi',
      ),
    );

    expect(metrics.targetCalories, 0);
  });

  test('pending Atlas metrics keep local onboarding targets and warn',
      () async {
    final adapter = _AtlasAdapter(
      metricsNotFound: true,
      onboardingMetricsPending: true,
    );
    final container = _containerWithAtlas(adapter);
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);
    await container.read(appDraftProvider.notifier).signInWithEmailPassword(
          email: 'test@example.com',
          password: 'test-password',
        );

    final result = await container
        .read(appDraftProvider.notifier)
        .completeOnboardingProfile(profile: _profile, answers: _answers);

    final state = container.read(appDraftProvider).value!;
    expect(adapter.lastOnboardPayload, isNotNull);
    expect(result?.warning, contains('still preparing'));
    expect(state.profile, same(_profile));
    expect(state.metrics.targetCalories, greaterThan(0));
    expect(state.nutritionSummary.targetCalories, greaterThan(0));
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

  test('startup loads workout templates once', () async {
    final workouts = _CountingWorkoutRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider
            .overrideWithValue(const _ReadyAuthRepository('mock')),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
        workoutRepositoryProvider.overrideWithValue(workouts),
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

    expect(workouts.loadTemplatesCalls, 1);
    expect(workouts.loadTemplateCalls, 0);
  });

  test('program generation repository posts to documented endpoint', () async {
    final adapter = _AtlasAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiProgramRepository(dio);

    final result = await repository.generateProgram(
      const AuthSession(
        userId: 'test-user',
        displayName: 'Test User',
        email: 'test@example.com',
        accessToken: 'test-token',
        provider: 'fastapi',
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(adapter.programGenerateCalls, 1);
    expect(adapter.lastProgramGeneratePath, '/programs/generate');
  });

  test('program generation success refreshes home data and marks generated',
      () async {
    final workouts = _CountingWorkoutRepository();
    final programs = _SlowProgramRepository();
    final container = _containerWithAtlas(
      _AtlasAdapter(),
      workoutRepository: workouts,
      programRepository: programs,
    );
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);

    final future = container
        .read(appDraftProvider.notifier)
        .generateProgramAfterOnboarding();
    programs.complete();
    final result = await future;

    final state = container.read(appDraftProvider).value!;
    expect(result.isSuccess, isTrue);
    expect(programs.generateCalls, 1);
    expect(workouts.loadTemplatesCalls, 2);
    expect(state.programGenerationChoice, ProgramGenerationChoice.accepted);
    expect(state.programGenerationStatus, ProgramGenerationStatus.generated);
  });

  test('double tap cannot create duplicate program generation posts', () async {
    final programs = _SlowProgramRepository();
    final container = _containerWithAtlas(
      _AtlasAdapter(),
      programRepository: programs,
    );
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);
    final controller = container.read(appDraftProvider.notifier);

    final first = controller.generateProgramAfterOnboarding();
    final second = controller.generateProgramAfterOnboarding();
    programs.complete();
    await Future.wait([first, second]);

    expect(programs.generateCalls, 1);
    expect(
      container.read(appDraftProvider).value!.programGenerationStatus,
      ProgramGenerationStatus.generated,
    );
  });

  test('mock program generation succeeds locally', () async {
    final repository = MockProgramRepository();

    final result = await repository.generateProgram(null);

    expect(result.isSuccess, isTrue);
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

const _account = AtlasOnboardingAccount(
  username: 'Test Athlete',
  email: 'test@example.com',
  password: 'test-password',
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

ProviderContainer _containerWithAtlas(
  _AtlasAdapter adapter, {
  _ReadyAuthRepository authRepository = const _ReadyAuthRepository('fastapi'),
  WorkoutRepository? workoutRepository,
  ProgramRepository? programRepository,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.example.test/api/v1',
      validateStatus: (status) => status != null && status < 500,
    ),
  )..httpClientAdapter = adapter;
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepository),
      profileRepositoryProvider.overrideWithValue(
        FastApiProfileRepository(dio, MockProfileRepository()),
      ),
      workoutRepositoryProvider
          .overrideWithValue(workoutRepository ?? MockWorkoutRepository()),
      nutritionRepositoryProvider.overrideWithValue(MockNutritionRepository()),
      consistencyRepositoryProvider
          .overrideWithValue(MockConsistencyRepository()),
      atlasRepositoryProvider.overrideWithValue(MockAtlasRepository()),
      programRepositoryProvider
          .overrideWithValue(programRepository ?? MockProgramRepository()),
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
  _AtlasAdapter({
    this.metricsNotFound = false,
    this.onboardingMetricsPending = false,
  });

  final bool metricsNotFound;
  final bool onboardingMetricsPending;
  Map<String, dynamic>? lastOnboardPayload;
  Map<String, dynamic>? lastPatchPayload;
  String? lastProgramGeneratePath;
  int profileGetCalls = 0;
  int programGenerateCalls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET' && options.path == '/supabase/profile') {
      profileGetCalls++;
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
      return _json({
        'success': true,
        'data': onboardingMetricsPending ? <String, Object?>{} : _metrics,
      });
    }
    if (options.method == 'PATCH' && options.path == '/atlas/profile') {
      lastPatchPayload = Map<String, dynamic>.from(options.data as Map);
      return _json({'success': true, 'data': {}});
    }
    if (options.method == 'GET' && options.path == '/atlas/metrics') {
      if (metricsNotFound) {
        return _json({
          'success': false,
          'error': {'code': 'ATLAS_METRICS_NOT_FOUND'},
        }, statusCode: 404);
      }
      return _json({'success': true, 'data': _metrics});
    }
    if (options.method == 'POST' && options.path == '/programs/generate') {
      programGenerateCalls++;
      lastProgramGeneratePath = options.path;
      return ResponseBody.fromString(
        'generated',
        201,
        headers: {
          Headers.contentTypeHeader: [Headers.textPlainContentType],
        },
      );
    }
    return _json({'success': true, 'data': []});
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

class _CountingWorkoutRepository extends MockWorkoutRepository {
  int loadTemplatesCalls = 0;
  int loadTemplateCalls = 0;

  @override
  Future<List<WorkoutTemplateDraft>> loadTemplates(AuthSession? session) async {
    loadTemplatesCalls++;
    return super.loadTemplates(session);
  }

  @override
  Future<WorkoutTemplateDraft> loadTemplate(AuthSession? session) async {
    loadTemplateCalls++;
    return super.loadTemplate(session);
  }
}

class _SlowProgramRepository implements ProgramRepository {
  int generateCalls = 0;
  final Completer<void> _completer = Completer<void>();

  @override
  Future<ProgramGenerationResult> generateProgram(AuthSession? session) async {
    generateCalls++;
    await _completer.future;
    return const ProgramGenerationResult.success();
  }

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
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
