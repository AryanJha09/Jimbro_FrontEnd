import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/repositories/app_repositories.dart';
import '../../shared/models/app_models.dart';
import '../../shared/models/atlas_insight.dart';

final authSessionProvider = StateProvider<AuthSession?>((ref) => null);
final isAuthenticatedProvider = StateProvider<bool>((ref) => false);
final hasCompletedOnboardingProvider = StateProvider<bool>((ref) => false);
final currentTabProvider = StateProvider<int>((ref) => 0);

final atlasHomeInsightsProvider =
    FutureProvider<List<AtlasInsight>>((ref) async {
  final atlasRepository = ref.watch(atlasRepositoryProvider);
  final draft = await ref.watch(appDraftProvider.future);
  return atlasRepository.loadHomeInsights(draft.session, draft.profile);
});

final historyInsightProvider = FutureProvider<AtlasInsight>((ref) async {
  final atlasRepository = ref.watch(atlasRepositoryProvider);
  final draft = await ref.watch(appDraftProvider.future);
  return atlasRepository.loadHistoryInsight(draft.session);
});

final nutritionInsightProvider = FutureProvider<AtlasInsight>((ref) async {
  final atlasRepository = ref.watch(atlasRepositoryProvider);
  final draft = await ref.watch(appDraftProvider.future);
  return atlasRepository.loadNutritionInsight(
    draft.session,
    draft.nutritionSummary,
  );
});

final recoveryInsightProvider = FutureProvider<AtlasInsight>((ref) async {
  final atlasRepository = ref.watch(atlasRepositoryProvider);
  final draft = await ref.watch(appDraftProvider.future);
  return atlasRepository.loadRecoveryInsight(
    draft.session,
    draft.consistency,
  );
});

final atlasPromptPreviewProvider =
    FutureProvider.family<AtlasInsight, String>((ref, prompt) async {
  final atlasRepository = ref.watch(atlasRepositoryProvider);
  final draft = await ref.watch(appDraftProvider.future);
  return atlasRepository.previewPrompt(draft.session, prompt);
});

final appDraftProvider =
    AsyncNotifierProvider<AppDraftController, AppDraftState>(
  AppDraftController.new,
);

class AppDraftController extends AsyncNotifier<AppDraftState> {
  AuthRepository get _authRepository => ref.read(authRepositoryProvider);
  ProfileRepository get _profileRepository =>
      ref.read(profileRepositoryProvider);
  WorkoutRepository get _workoutRepository =>
      ref.read(workoutRepositoryProvider);
  NutritionRepository get _nutritionRepository =>
      ref.read(nutritionRepositoryProvider);
  ConsistencyRepository get _consistencyRepository =>
      ref.read(consistencyRepositoryProvider);
  SearchRepository get _searchRepository => ref.read(searchRepositoryProvider);

  @override
  Future<AppDraftState> build() async {
    ref.watch(authRepositoryProvider);
    ref.watch(profileRepositoryProvider);
    ref.watch(workoutRepositoryProvider);
    ref.watch(nutritionRepositoryProvider);
    ref.watch(consistencyRepositoryProvider);
    ref.watch(searchRepositoryProvider);

    final session = await _authRepository.currentSession();
    if (session != null) {
      ref.read(authSessionProvider.notifier).state = session;
      ref.read(isAuthenticatedProvider.notifier).state = true;
    }

    return _loadDraftForSession(session);
  }

  Future<void> signInWithMockProvider(String provider) async {
    final session = await _authRepository.signInWithMockProvider(provider);
    await _replaceSession(session);
  }

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final session = await _authRepository.signInWithEmailPassword(
      email: email,
      password: password,
    );
    await _replaceSession(session);
  }

  Future<void> updateProfile(UserProfile profile) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final saved = await _profileRepository.saveProfile(
      current.session,
      profile,
    );
    state = AsyncData(current.copyWith(profile: saved));
  }

  Future<void> updateMetrics(UserStaticMetrics metrics) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final saved = await _profileRepository.saveMetrics(
      current.session,
      metrics,
    );
    state = AsyncData(current.copyWith(metrics: saved));
  }

  Future<void> updateTemplate(WorkoutTemplateDraft template) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        template: template,
        workoutLog: current.workoutLog.copyWith(
          name: current.workoutLog.name.isEmpty
              ? template.name
              : current.workoutLog.name,
          templateId: template.templateId,
          exercises: template.exercises,
        ),
      ),
    );
  }

  Future<void> updateWorkoutNotes(String notes) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        workoutLog: current.workoutLog.copyWith(notes: notes),
      ),
    );
  }

  Future<void> updateExercise(
    int index,
    WorkoutExerciseDraft exercise,
  ) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final updatedExercises = [...current.template.exercises];
    final previous = updatedExercises[index];
    final hasRenamedExercise =
        previous.exerciseName.trim() != exercise.exerciseName.trim();
    updatedExercises[index] =
        hasRenamedExercise ? exercise.copyWith(exerciseId: null) : exercise;
    state = AsyncData(
      current.copyWith(
        template: current.template.copyWith(exercises: updatedExercises),
        workoutLog: current.workoutLog.copyWith(exercises: updatedExercises),
      ),
    );
  }

  Future<List<ExerciseSuggestion>> searchExerciseSuggestions(
    String query,
  ) async {
    return _workoutRepository.searchExercises(query);
  }

  Future<void> applyExerciseSuggestion(
    int index,
    ExerciseSuggestion suggestion,
  ) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final updatedExercises = [...current.template.exercises];
    updatedExercises[index] = updatedExercises[index].copyWith(
      exerciseId: suggestion.exerciseId,
      exerciseName: suggestion.name,
    );
    state = AsyncData(
      current.copyWith(
        template: current.template.copyWith(exercises: updatedExercises),
        workoutLog: current.workoutLog.copyWith(exercises: updatedExercises),
      ),
    );
  }

  Future<void> addExercise() async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final updatedExercises = [...current.template.exercises];
    updatedExercises.add(
      const WorkoutExerciseDraft(
        exerciseName: '',
        notes: '',
        targetSets: 3,
        targetReps: 10,
        sets: [
          SetDraft(
            setNumber: 1,
            weightKg: 0,
            reps: 0,
            isWarmup: false,
            isCompleted: false,
            rpe: 0,
          ),
        ],
      ),
    );
    state = AsyncData(
      current.copyWith(
        template: current.template.copyWith(exercises: updatedExercises),
        workoutLog: current.workoutLog.copyWith(exercises: updatedExercises),
      ),
    );
  }

  Future<void> updateSet(
    int exerciseIndex,
    int setIndex,
    SetDraft setDraft,
  ) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final exercises = [...current.template.exercises];
    final sets = [...exercises[exerciseIndex].sets];
    sets[setIndex] = setDraft;
    exercises[exerciseIndex] = exercises[exerciseIndex].copyWith(sets: sets);
    state = AsyncData(
      current.copyWith(
        template: current.template.copyWith(exercises: exercises),
        workoutLog: current.workoutLog.copyWith(exercises: exercises),
      ),
    );
  }

  Future<void> addSet(int exerciseIndex) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final exercises = [...current.template.exercises];
    final sets = [...exercises[exerciseIndex].sets];
    sets.add(
      SetDraft(
        setNumber: sets.length + 1,
        weightKg: sets.isEmpty ? 0 : sets.last.weightKg,
        reps: sets.isEmpty ? 0 : sets.last.reps,
        isWarmup: false,
        isCompleted: false,
        rpe: sets.isEmpty ? 0 : sets.last.rpe,
      ),
    );
    exercises[exerciseIndex] = exercises[exerciseIndex].copyWith(sets: sets);
    state = AsyncData(
      current.copyWith(
        template: current.template.copyWith(exercises: exercises),
        workoutLog: current.workoutLog.copyWith(exercises: exercises),
      ),
    );
  }

  Future<void> removeSet(int exerciseIndex, int setIndex) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final exercises = [...current.template.exercises];
    final sets = [...exercises[exerciseIndex].sets]..removeAt(setIndex);
    final renumbered = sets
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(setNumber: entry.key + 1))
        .toList();
    exercises[exerciseIndex] =
        exercises[exerciseIndex].copyWith(sets: renumbered);
    state = AsyncData(
      current.copyWith(
        template: current.template.copyWith(exercises: exercises),
        workoutLog: current.workoutLog.copyWith(exercises: exercises),
      ),
    );
  }

  Future<void> removeExercise(int index) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final exercises = [...current.template.exercises]..removeAt(index);
    state = AsyncData(
      current.copyWith(
        template: current.template.copyWith(exercises: exercises),
        workoutLog: current.workoutLog.copyWith(exercises: exercises),
      ),
    );
  }

  Future<void> addFoodLog() async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final newFoodLogs = [
      ...current.foodLogs,
      FoodLogDraft.empty,
    ];
    state = AsyncData(
      current.copyWith(
        foodLogs: newFoodLogs,
        nutritionSummary: _rebuildNutritionSummary(
          logs: newFoodLogs,
          base: current.nutritionSummary,
        ),
      ),
    );
  }

  Future<void> updateFoodLog(int index, FoodLogDraft foodLog) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final newFoodLogs = [...current.foodLogs];
    final previous = newFoodLogs[index];
    final rescaledFoodLog = _rescaleFoodLog(foodLog);
    final changedFoodDefinition =
        previous.foodName.trim() != foodLog.foodName.trim() ||
            previous.calories != foodLog.calories ||
            previous.protein != foodLog.protein ||
            previous.carbs != foodLog.carbs ||
            previous.fat != foodLog.fat;
    newFoodLogs[index] = changedFoodDefinition
        ? rescaledFoodLog.copyWith(foodId: null)
        : rescaledFoodLog;
    state = AsyncData(
      current.copyWith(
        foodLogs: newFoodLogs,
        nutritionSummary: _rebuildNutritionSummary(
          logs: newFoodLogs,
          base: current.nutritionSummary,
        ),
      ),
    );
  }

  Future<List<FoodSuggestion>> searchFoodSuggestions(String query) async {
    return _nutritionRepository.searchFoods(query);
  }

  Future<void> applyFoodSuggestion(
    int index,
    FoodSuggestion suggestion,
  ) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final newFoodLogs = [...current.foodLogs];
    newFoodLogs[index] = suggestion.applyTo(newFoodLogs[index]);
    state = AsyncData(
      current.copyWith(
        foodLogs: newFoodLogs,
        nutritionSummary: _rebuildNutritionSummary(
          logs: newFoodLogs,
          base: current.nutritionSummary,
        ),
      ),
    );
  }

  Future<void> removeFoodLog(int index) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final newFoodLogs = [...current.foodLogs]..removeAt(index);
    state = AsyncData(
      current.copyWith(
        foodLogs: newFoodLogs,
        nutritionSummary: _rebuildNutritionSummary(
          logs: newFoodLogs,
          base: current.nutritionSummary,
        ),
      ),
    );
  }

  Future<void> updateHydration(double liters) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        nutritionSummary: current.nutritionSummary.copyWith(
          hydrationConsumedLiters: liters,
        ),
      ),
    );
  }

  Future<void> adjustConsistency(int delta) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final nextStreak = (current.consistency.currentStreak + delta).clamp(
      0,
      120,
    );
    final nextLongest = nextStreak > current.consistency.longestStreak
        ? nextStreak
        : current.consistency.longestStreak;
    final next = current.consistency.copyWith(
      currentStreak: nextStreak,
      longestStreak: nextLongest,
      weeklyCheckins: nextStreak == 0 ? 0 : nextStreak.clamp(0, 7),
      totalLogs: current.consistency.totalLogs + (delta > 0 ? delta : 0),
    );
    final saved = await _consistencyRepository.saveConsistency(
      current.session,
      next,
    );
    state = AsyncData(current.copyWith(consistency: saved));
  }

  Future<void> updateSearchQuery(String query) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final groups = await _searchRepository.search(current.session, query);
    state = AsyncData(
      current.copyWith(
        search: current.search.copyWith(query: query, groups: groups),
      ),
    );
  }

  Future<void> _saveFoodLogs(
    AppDraftState current,
    List<FoodLogDraft> logs,
  ) async {
    final savedLogs = await _nutritionRepository.saveFoodLogs(
      current.session,
      logs,
    );
    state = AsyncData(
      current.copyWith(
        foodLogs: savedLogs,
        nutritionSummary: _rebuildNutritionSummary(
          logs: savedLogs,
          base: current.nutritionSummary,
        ),
      ),
    );
  }

  Future<WorkoutTemplateDraft> saveWorkoutTemplate() async {
    final current = state.valueOrNull;
    if (current == null) {
      throw Exception('Workout state is not ready.');
    }
    final saved = await _workoutRepository.saveTemplate(
      current.session,
      current.template,
    );
    state = AsyncData(
      current.copyWith(
        template: saved,
        workoutLog: current.workoutLog.copyWith(
          templateId: saved.templateId,
          name: current.workoutLog.name.isEmpty
              ? saved.name
              : current.workoutLog.name,
          exercises: saved.exercises,
        ),
      ),
    );
    return saved;
  }

  Future<WorkoutLogDraft> logWorkoutSession() async {
    final current = state.valueOrNull;
    if (current == null) {
      throw Exception('Workout state is not ready.');
    }
    final draftToLog = current.workoutLog.copyWith(
      workoutLogId: null,
      templateId: current.template.templateId,
      name: current.workoutLog.name.isEmpty
          ? (current.template.name.isEmpty
              ? 'Workout Session'
              : current.template.name)
          : current.workoutLog.name,
      exercises: current.template.exercises,
    );
    final savedLog = await _workoutRepository.saveWorkoutLog(
      current.session,
      draftToLog,
    );
    state = AsyncData(
      current.copyWith(
        workoutLog: savedLog,
      ),
    );
    return savedLog;
  }

  Future<List<FoodLogDraft>> saveNutritionLogs() async {
    final current = state.valueOrNull;
    if (current == null) {
      throw Exception('Nutrition state is not ready.');
    }
    await _saveFoodLogs(current, current.foodLogs);
    return state.valueOrNull?.foodLogs ?? const [];
  }

  DailyNutritionSummary _rebuildNutritionSummary({
    required List<FoodLogDraft> logs,
    required DailyNutritionSummary base,
  }) {
    double calories = 0;
    double protein = 0;
    double carbs = 0;
    double fat = 0;
    for (final log in logs) {
      calories += log.calories;
      protein += log.protein;
      carbs += log.carbs;
      fat += log.fat;
    }
    return base.copyWith(
      consumedCalories: calories,
      proteinConsumed: protein,
      carbsConsumed: carbs,
      fatConsumed: fat,
    );
  }

  FoodLogDraft _rescaleFoodLog(FoodLogDraft log) {
    final caloriesPer100g = log.caloriesPer100g;
    final proteinPer100g = log.proteinPer100g;
    final carbsPer100g = log.carbsPer100g;
    final fatPer100g = log.fatPer100g;
    if (caloriesPer100g == null ||
        proteinPer100g == null ||
        carbsPer100g == null ||
        fatPer100g == null) {
      return log;
    }
    final multiplier = log.quantityGrams / 100;
    return log.copyWith(
      calories: caloriesPer100g * multiplier,
      protein: proteinPer100g * multiplier,
      carbs: carbsPer100g * multiplier,
      fat: fatPer100g * multiplier,
    );
  }

  Future<void> _replaceSession(AuthSession session) async {
    ref.read(authSessionProvider.notifier).state = session;
    ref.read(isAuthenticatedProvider.notifier).state = true;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadDraftForSession(session));
  }

  Future<AppDraftState> _loadDraftForSession(AuthSession? session) async {
    final results = await Future.wait<Object>([
      _loadOrDefault<UserProfile>(
        () => _profileRepository.loadProfile(session),
        const UserProfile(
          name: 'JimBro User',
          goal: '',
          coachingPreference: '',
          userLevel: UserLevel.beginner,
          age: 0,
          heightCm: 0,
          weightKg: 0,
          weeksActive: 0,
          prefersVoiceLogging: false,
        ),
      ),
      _loadOrDefault<UserStaticMetrics>(
        () => _profileRepository.loadMetrics(session),
        const UserStaticMetrics(
          bmr: 0,
          tdee: 0,
          maintenanceCalories: 0,
          cutCalories: 0,
          bulkCalories: 0,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
          hydrationL: 0,
          cutIntensity: '',
        ),
      ),
      _loadOrDefault<WorkoutTemplateDraft>(
        () => _workoutRepository.loadTemplate(session),
        WorkoutTemplateDraft.empty,
      ),
      _loadOrDefault<WorkoutLogDraft>(
        () => _workoutRepository.loadWorkoutLog(session),
        WorkoutLogDraft.empty,
      ),
      _loadOrDefault<List<FoodLogDraft>>(
        () => _nutritionRepository.loadFoodLogs(session),
        const <FoodLogDraft>[],
      ),
      _loadOrDefault<DailyNutritionSummary>(
        () => _nutritionRepository.loadSummary(session),
        DailyNutritionSummary.empty,
      ),
      _loadOrDefault<ConsistencyState>(
        () => _consistencyRepository.loadConsistency(session),
        const ConsistencyState(
          currentStreak: 0,
          longestStreak: 0,
          weeklyCheckins: 0,
          totalLogs: 0,
        ),
      ),
    ]);

    final template = results[2] as WorkoutTemplateDraft;
    final loadedWorkoutLog = results[3] as WorkoutLogDraft;
    final workoutLog = loadedWorkoutLog.name.isEmpty &&
            loadedWorkoutLog.notes.isEmpty &&
            loadedWorkoutLog.exercises.isEmpty
        ? loadedWorkoutLog.copyWith(
            name: template.name,
            templateId: template.templateId,
            exercises: template.exercises,
          )
        : loadedWorkoutLog;

    return AppDraftState(
      session: session,
      profile: results[0] as UserProfile,
      metrics: results[1] as UserStaticMetrics,
      template: template,
      workoutLog: workoutLog,
      foodLogs: results[4] as List<FoodLogDraft>,
      nutritionSummary: results[5] as DailyNutritionSummary,
      consistency: results[6] as ConsistencyState,
      search: _searchRepository.emptyState(),
    );
  }

  Future<T> _loadOrDefault<T>(
    Future<T> Function() loader,
    T fallback,
  ) async {
    try {
      return await loader().timeout(const Duration(seconds: 9));
    } on TimeoutException {
      return fallback;
    } on DioException catch (error) {
      if (_isRecoverableStartupFailure(error)) {
        return fallback;
      }
      rethrow;
    }
  }

  bool _isRecoverableStartupFailure(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError =>
        true,
      DioExceptionType.badResponse => (error.response?.statusCode ?? 0) >= 500,
      DioExceptionType.badCertificate ||
      DioExceptionType.cancel ||
      DioExceptionType.unknown =>
        false,
    };
  }
}
