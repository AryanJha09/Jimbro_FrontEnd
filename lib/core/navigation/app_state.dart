import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/nutrition/nutrition_targets.dart';
import '../../core/notifications/workout_notification_service.dart';
import '../../core/repositories/app_repositories.dart';
import '../../shared/models/app_models.dart';
import '../../shared/models/atlas_insight.dart';
import '../../shared/models/onboarding_models.dart';

final authSessionProvider = StateProvider<AuthSession?>((ref) => null);
final isAuthenticatedProvider = StateProvider<bool>((ref) => false);
final hasCompletedOnboardingProvider = StateProvider<bool>((ref) => false);
final forceShowOnboardingProvider = StateProvider<bool>((ref) => false);
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

final agentContextProvider = FutureProvider<AgentContextSnapshot>((ref) async {
  final repository = ref.watch(agentContextRepositoryProvider);
  if (repository is MockAgentContextRepository) {
    return AgentContextSnapshot.empty;
  }
  final draft = await ref.watch(appDraftProvider.future);
  if (draft.session == null || draft.session?.provider == 'mock') {
    return AgentContextSnapshot.empty;
  }
  return repository.load(draft.session);
});

class WorkoutScheduleSaveResult {
  const WorkoutScheduleSaveResult({
    required this.entry,
    required this.notification,
  });

  final WorkoutScheduleEntry entry;
  final WorkoutReminderResult notification;
}

class ProfileSyncResult {
  const ProfileSyncResult({
    required this.profile,
    required this.metrics,
    this.warning,
  });

  final UserProfile profile;
  final UserStaticMetrics metrics;
  final String? warning;

  bool get hasWarning => warning != null && warning!.trim().isNotEmpty;
}

class AppDraftController extends AsyncNotifier<AppDraftState> {
  AuthRepository get _authRepository => ref.read(authRepositoryProvider);
  ProfileRepository get _profileRepository =>
      ref.read(profileRepositoryProvider);
  WorkoutRepository get _workoutRepository =>
      ref.read(workoutRepositoryProvider);
  WorkoutNotificationService get _workoutNotificationService =>
      ref.read(workoutNotificationServiceProvider);
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
    ref.watch(workoutNotificationServiceProvider);
    ref.watch(nutritionRepositoryProvider);
    ref.watch(consistencyRepositoryProvider);
    ref.watch(searchRepositoryProvider);

    final session = await _authRepository.currentSession();
    if (session != null) {
      ref.read(authSessionProvider.notifier).state = session;
      ref.read(isAuthenticatedProvider.notifier).state = true;
      await _flushPending(session);
    }

    late final AppDraftState draft;
    try {
      draft = await _loadDraftForSession(session);
    } on AuthSessionExpiredException {
      if (session != null) {
        try {
          await _authRepository.signOut();
        } catch (_) {
          // The backend rejected the session; local state still returns to Auth.
        }
      }
      ref.read(authSessionProvider.notifier).state = null;
      ref.read(isAuthenticatedProvider.notifier).state = false;
      ref.read(hasCompletedOnboardingProvider.notifier).state = false;
      ref.read(forceShowOnboardingProvider.notifier).state = false;
      ref.read(currentTabProvider.notifier).state = 0;
      return _loadDraftForSession(null);
    }
    if (session != null && _profileLooksOnboarded(draft.profile)) {
      ref.read(hasCompletedOnboardingProvider.notifier).state = true;
    }
    return draft;
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

  Future<void> signOut() async {
    await _authRepository.signOut();
    ref.read(authSessionProvider.notifier).state = null;
    ref.read(isAuthenticatedProvider.notifier).state = false;
    ref.read(hasCompletedOnboardingProvider.notifier).state = false;
    ref.read(forceShowOnboardingProvider.notifier).state = false;
    ref.read(currentTabProvider.notifier).state = 0;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadDraftForSession(null));
  }

  Future<ProfileSyncResult?> updateProfile(UserProfile profile) async {
    final current = state.valueOrNull;
    if (current == null) {
      return null;
    }
    final result = await _syncProfileUpdate(
      current: current,
      profile: profile,
    );
    state = AsyncData(
      current.copyWith(
        profile: result.profile,
        metrics: result.metrics,
        nutritionSummary: _applyTargetEstimate(
          current.nutritionSummary,
          result.metrics,
          clearUnavailableTargets: result.metrics.targetCalories <= 0,
        ),
      ),
    );
    _refreshAgentContext(current.session);
    return result;
  }

  Future<ProfileSyncResult?> completeOnboardingProfile({
    required UserProfile profile,
    required OnboardingAnswersDto answers,
  }) async {
    final current = state.valueOrNull;
    if (current == null) {
      return null;
    }
    final result = await _syncOnboardingProfile(
      current: current,
      profile: profile,
      answers: answers,
    );
    var templates = current.templates;
    var template = current.template;
    if (current.session != null && !result.hasWarning) {
      final loadedTemplates = await _loadOrDefault<List<WorkoutTemplateDraft>>(
        () => _workoutRepository.loadTemplates(current.session),
        current.templates,
      );
      if (loadedTemplates.isNotEmpty) {
        templates = loadedTemplates;
        template = loadedTemplates.last;
      }
    }
    state = AsyncData(
      current.copyWith(
        profile: result.profile,
        metrics: result.metrics,
        templates: templates,
        template: template,
        nutritionSummary: _applyTargetEstimate(
          current.nutritionSummary,
          result.metrics,
          clearUnavailableTargets: result.metrics.targetCalories <= 0,
        ),
      ),
    );
    _refreshAgentContext(current.session);
    return result;
  }

  Future<void> updateProfileDraft(UserProfile profile) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final estimate = NutritionTargetCalculator.estimate(profile);
    final metrics = estimate.toMetrics();
    state = AsyncData(
      current.copyWith(
        profile: profile,
        metrics: metrics,
        nutritionSummary: _applyTargetEstimate(
          current.nutritionSummary,
          metrics,
          clearUnavailableTargets: !estimate.hasRequiredProfile,
        ),
      ),
    );
  }

  Future<void> updateMetrics(UserStaticMetrics metrics) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final saved = await _runProtectedAction(
      () => _profileRepository.saveMetrics(
        current.session,
        metrics,
      ),
    );
    state = AsyncData(
      current.copyWith(
        metrics: saved,
        nutritionSummary: _applyTargetEstimate(
          current.nutritionSummary,
          saved,
        ),
      ),
    );
  }

  Future<void> updateTemplate(WorkoutTemplateDraft template) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final syncedWorkoutLog = _syncWorkoutLogWithTemplateIfIdle(
      current.workoutLog,
      template,
    );
    state = AsyncData(
      current.copyWith(
        template: template,
        workoutLog: syncedWorkoutLog,
      ),
    );
  }

  Future<void> createTemplateDraft() async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        template: WorkoutTemplateDraft.empty,
        workoutLog: WorkoutLogDraft.empty,
      ),
    );
  }

  Future<void> openWorkoutTemplate(WorkoutTemplateDraft template) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        template: template,
        workoutLog: _syncWorkoutLogWithTemplateIfIdle(
          current.workoutLog,
          template,
        ),
      ),
    );
  }

  Future<void> startWorkoutFromTemplate(WorkoutTemplateDraft template) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        template: template,
        workoutLog: WorkoutLogDraft(
          templateId: template.templateId,
          name: template.name.trim().isEmpty
              ? 'Workout Session'
              : template.name.trim(),
          notes: '',
          startedAtLabel: DateTime.now().toIso8601String(),
          endedAtLabel: '',
          exercises: _executionExercisesFromTemplate(template.exercises),
        ),
      ),
    );
  }

  Future<void> startScheduledWorkout(WorkoutScheduleEntry entry) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final template = _templateForSchedule(current.templates, entry);
    if (template == null) {
      return;
    }
    await startWorkoutFromTemplate(template);
  }

  Future<WorkoutScheduleSaveResult> scheduleWorkoutTemplate(
    WorkoutTemplateDraft template, {
    required int weekday,
    required String timeLabel,
  }) async {
    final current = state.valueOrNull;
    if (current == null) {
      throw Exception('Workout schedule state is not ready.');
    }
    if (template.templateId == null) {
      throw Exception('Save this workout template before scheduling it.');
    }
    final session = await _requireSessionForProtectedAction(
      current,
      source: 'lib/core/navigation/app_state.dart -> scheduleWorkoutTemplate',
      feature: 'workout schedule save',
    );
    final existing = _scheduleForWeekday(current.workoutSchedule, weekday);
    final draft = WorkoutScheduleEntry(
      scheduleId: existing?.scheduleId,
      userId: session.userId,
      templateId: template.templateId,
      templateName: template.name,
      weekday: weekday,
      timeLabel: _normalizeScheduleTime(timeLabel),
      repeatWeekly: true,
      active: true,
    );
    final saved = await _runProtectedAction(
      () => _workoutRepository.saveScheduleEntry(session, draft),
    );
    final schedule = _upsertWorkoutSchedule(current.workoutSchedule, saved);
    state = AsyncData(current.copyWith(workoutSchedule: schedule));
    if (existing != null && existing.scheduleId != saved.scheduleId) {
      await _workoutNotificationService.cancelReminder(existing);
    }
    final notification =
        await _workoutNotificationService.scheduleWeeklyReminder(saved);
    return WorkoutScheduleSaveResult(
      entry: saved,
      notification: notification,
    );
  }

  Future<void> deleteWorkoutSchedule(WorkoutScheduleEntry entry) async {
    final current = state.valueOrNull;
    if (current == null) {
      throw Exception('Workout schedule state is not ready.');
    }
    final session = await _requireSessionForProtectedAction(
      current,
      source: 'lib/core/navigation/app_state.dart -> deleteWorkoutSchedule',
      feature: 'workout schedule delete',
    );
    await _runProtectedAction(
      () => _workoutRepository.deleteScheduleEntry(session, entry),
    );
    await _workoutNotificationService.cancelReminder(entry);
    final schedule = current.workoutSchedule
        .where(
          (item) =>
              item.scheduleId != entry.scheduleId &&
              item.weekday != entry.weekday,
        )
        .toList(growable: false);
    state = AsyncData(current.copyWith(workoutSchedule: schedule));
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

  Future<void> updateWorkoutExercise(
    int index,
    WorkoutExerciseDraft exercise,
  ) async {
    final current = state.valueOrNull;
    if (current == null ||
        index < 0 ||
        index >= current.workoutLog.exercises.length) {
      return;
    }
    final exercises = [...current.workoutLog.exercises];
    final previous = exercises[index];
    final hasRenamedExercise =
        previous.exerciseName.trim() != exercise.exerciseName.trim();
    exercises[index] =
        hasRenamedExercise ? exercise.copyWith(exerciseId: null) : exercise;
    state = AsyncData(
      current.copyWith(
        workoutLog: current.workoutLog.copyWith(exercises: exercises),
      ),
    );
  }

  Future<void> applyWorkoutExerciseSuggestion(
    int index,
    ExerciseSuggestion suggestion,
  ) async {
    final current = state.valueOrNull;
    if (current == null ||
        index < 0 ||
        index >= current.workoutLog.exercises.length) {
      return;
    }
    final exercises = [...current.workoutLog.exercises];
    exercises[index] = exercises[index].copyWith(
      exerciseId: suggestion.exerciseId,
      exerciseName: suggestion.name,
    );
    state = AsyncData(
      current.copyWith(
        workoutLog: current.workoutLog.copyWith(exercises: exercises),
      ),
    );
  }

  Future<void> updateWorkoutSet(
    int exerciseIndex,
    int setIndex,
    SetDraft setDraft,
  ) async {
    final current = state.valueOrNull;
    if (current == null ||
        exerciseIndex < 0 ||
        exerciseIndex >= current.workoutLog.exercises.length) {
      return;
    }
    final exercises = [...current.workoutLog.exercises];
    final sets = [...exercises[exerciseIndex].sets];
    if (setIndex < 0 || setIndex >= sets.length) {
      return;
    }
    sets[setIndex] = setDraft.copyWith(isCompleted: true);
    exercises[exerciseIndex] = exercises[exerciseIndex].copyWith(sets: sets);
    state = AsyncData(
      current.copyWith(
        workoutLog: current.workoutLog.copyWith(exercises: exercises),
      ),
    );
  }

  Future<void> addWorkoutSet(int exerciseIndex) async {
    final current = state.valueOrNull;
    if (current == null ||
        exerciseIndex < 0 ||
        exerciseIndex >= current.workoutLog.exercises.length) {
      return;
    }
    final exercises = [...current.workoutLog.exercises];
    final sets = [...exercises[exerciseIndex].sets];
    sets.add(
      SetDraft(
        setNumber: sets.length + 1,
        weightKg: sets.isEmpty ? 0 : sets.last.weightKg,
        reps:
            sets.isEmpty ? exercises[exerciseIndex].targetReps : sets.last.reps,
        isWarmup: false,
        isCompleted: false,
        rpe: sets.isEmpty ? 0 : sets.last.rpe,
      ),
    );
    exercises[exerciseIndex] = exercises[exerciseIndex].copyWith(sets: sets);
    state = AsyncData(
      current.copyWith(
        workoutLog: current.workoutLog.copyWith(exercises: exercises),
      ),
    );
  }

  Future<void> removeWorkoutSet(int exerciseIndex, int setIndex) async {
    final current = state.valueOrNull;
    if (current == null ||
        exerciseIndex < 0 ||
        exerciseIndex >= current.workoutLog.exercises.length) {
      return;
    }
    final exercises = [...current.workoutLog.exercises];
    final sets = [...exercises[exerciseIndex].sets];
    if (sets.length <= 1 || setIndex < 0 || setIndex >= sets.length) {
      return;
    }
    sets.removeAt(setIndex);
    final renumbered = sets
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(setNumber: entry.key + 1))
        .toList();
    exercises[exerciseIndex] =
        exercises[exerciseIndex].copyWith(sets: renumbered);
    state = AsyncData(
      current.copyWith(
        workoutLog: current.workoutLog.copyWith(exercises: exercises),
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
        workoutLog: _syncWorkoutLogWithTemplateIfIdle(
          current.workoutLog,
          current.template.copyWith(exercises: updatedExercises),
        ),
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
        workoutLog: _syncWorkoutLogWithTemplateIfIdle(
          current.workoutLog,
          current.template.copyWith(exercises: updatedExercises),
        ),
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
        workoutLog: _syncWorkoutLogWithTemplateIfIdle(
          current.workoutLog,
          current.template.copyWith(exercises: updatedExercises),
        ),
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
        workoutLog: _syncWorkoutLogWithTemplateIfIdle(
          current.workoutLog,
          current.template.copyWith(exercises: exercises),
        ),
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
        workoutLog: _syncWorkoutLogWithTemplateIfIdle(
          current.workoutLog,
          current.template.copyWith(exercises: exercises),
        ),
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
        workoutLog: _syncWorkoutLogWithTemplateIfIdle(
          current.workoutLog,
          current.template.copyWith(exercises: exercises),
        ),
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
        workoutLog: _syncWorkoutLogWithTemplateIfIdle(
          current.workoutLog,
          current.template.copyWith(exercises: exercises),
        ),
      ),
    );
  }

  Future<void> addFoodLog([MealType mealType = MealType.snack]) async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final newFoodLogs = [
      ...current.foodLogs,
      FoodLogDraft.empty.copyWith(mealType: mealType),
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
    final quantityChanged = previous.quantityGrams != foodLog.quantityGrams;
    final foodLogWithSource = quantityChanged
        ? foodLog.copyWith(quantitySource: QuantitySource.explicit)
        : foodLog;
    final rescaledFoodLog = _rescaleFoodLog(foodLogWithSource);
    final changedFoodDefinition =
        previous.foodName.trim() != foodLogWithSource.foodName.trim() ||
            previous.calories != foodLogWithSource.calories ||
            previous.protein != foodLogWithSource.protein ||
            previous.carbs != foodLogWithSource.carbs ||
            previous.fat != foodLogWithSource.fat;
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
    final saved = await _runProtectedAction(
      () => _consistencyRepository.saveConsistency(
        current.session,
        next,
      ),
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
    final session = await _requireSessionForProtectedAction(
      current,
      source: 'lib/core/navigation/app_state.dart -> _saveFoodLogs',
      feature: 'nutrition save',
    );
    final savedLogs = await _runProtectedAction(
      () => _nutritionRepository.saveFoodLogs(
        session,
        logs,
      ),
    );
    final savedSummary = await _runProtectedAction(
      () => _nutritionRepository.loadSummary(session),
    );
    final isLiveSession = session.provider != 'mock';
    final summaryFromLogs = _rebuildNutritionSummary(
      logs: savedLogs,
      base: current.nutritionSummary,
    );
    state = AsyncData(
      current.copyWith(
        foodLogs: savedLogs,
        nutritionSummary: isLiveSession
            ? (_summaryHasVisibleTotals(savedSummary) || savedLogs.isEmpty
                ? savedSummary
                : summaryFromLogs)
            : summaryFromLogs,
      ),
    );
    _refreshAgentContext(session);
  }

  Future<void> _flushPending(AuthSession session) async {
    if (session.provider == 'mock') {
      return;
    }
    try {
      await _workoutRepository.flushPending(session);
      await _nutritionRepository.flushPending(session);
    } on AuthSessionExpiredException {
      rethrow;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'JimBro offline outbox flush deferred: ${error.runtimeType}',
        );
      }
    }
  }

  Future<WorkoutTemplateDraft> saveWorkoutTemplate() async {
    final current = state.valueOrNull;
    if (current == null) {
      throw Exception('Workout state is not ready.');
    }
    final session = await _requireSessionForProtectedAction(
      current,
      source: 'lib/core/navigation/app_state.dart -> saveWorkoutTemplate',
      feature: 'workout template save',
    );
    final saved = await _runProtectedAction(
      () => _workoutRepository.saveTemplate(
        session,
        current.template,
      ),
    );
    final templates = _upsertWorkoutTemplate(current.templates, saved);
    state = AsyncData(
      current.copyWith(
        template: saved,
        templates: templates,
        workoutLog: current.workoutLog.copyWith(
          templateId: saved.templateId,
          name: current.workoutLog.name.isEmpty
              ? saved.name
              : current.workoutLog.name,
          exercises: current.workoutLog.isInProgress
              ? current.workoutLog.exercises
              : saved.exercises,
        ),
      ),
    );
    return saved;
  }

  Future<void> deleteWorkoutTemplate(WorkoutTemplateDraft template) async {
    final current = state.valueOrNull;
    if (current == null) {
      throw Exception('Workout state is not ready.');
    }
    final templateId = template.templateId;
    if (templateId == null) {
      state = AsyncData(
        current.copyWith(
          template: current.template.templateId == null
              ? WorkoutTemplateDraft.empty
              : current.template,
        ),
      );
      return;
    }
    final session = await _requireSessionForProtectedAction(
      current,
      source: 'lib/core/navigation/app_state.dart -> deleteWorkoutTemplate',
      feature: 'workout template delete',
    );
    await _runProtectedAction(
      () => _workoutRepository.deleteTemplate(session, templateId),
    );
    final templates = current.templates
        .where((item) => item.templateId != templateId)
        .toList(growable: false);
    final removedSchedule = current.workoutSchedule
        .where((entry) => entry.templateId == templateId)
        .toList(growable: false);
    for (final entry in removedSchedule) {
      await _workoutNotificationService.cancelReminder(entry);
    }
    final schedule = current.workoutSchedule
        .where((entry) => entry.templateId != templateId)
        .toList(growable: false);
    final activeDeleted = current.template.templateId == templateId;
    state = AsyncData(
      current.copyWith(
        templates: templates,
        workoutSchedule: schedule,
        template: activeDeleted
            ? (templates.isEmpty ? WorkoutTemplateDraft.empty : templates.last)
            : current.template,
        workoutLog: current.workoutLog.templateId == templateId
            ? current.workoutLog.copyWith(templateId: null)
            : current.workoutLog,
      ),
    );
  }

  Future<WorkoutLogDraft> logWorkoutSession() async {
    final current = state.valueOrNull;
    if (current == null) {
      throw Exception('Workout state is not ready.');
    }
    final session = await _requireSessionForProtectedAction(
      current,
      source: 'lib/core/navigation/app_state.dart -> logWorkoutSession',
      feature: 'workout log save',
    );
    final nowIso = DateTime.now().toIso8601String();
    final logExercises = current.workoutLog.exercises.isEmpty
        ? _executionExercisesFromTemplate(current.template.exercises)
        : current.workoutLog.exercises;
    final draftToLog = current.workoutLog.copyWith(
      workoutLogId: null,
      templateId: current.workoutLog.templateId ?? current.template.templateId,
      name: current.workoutLog.name.trim().isEmpty
          ? (current.template.name.trim().isEmpty
              ? 'Workout Session'
              : current.template.name)
          : current.workoutLog.name,
      startedAtLabel: current.workoutLog.startedAtLabel.trim().isEmpty
          ? nowIso
          : current.workoutLog.startedAtLabel,
      endedAtLabel: current.workoutLog.endedAtLabel.trim().isEmpty
          ? nowIso
          : current.workoutLog.endedAtLabel,
      exercises: logExercises,
    );
    if (kDebugMode) {
      debugPrint(
        'JimBro workout log before repository: ${jsonEncode(_workoutLogDebugMap(draftToLog))}',
      );
    }
    final savedLog = await _runProtectedAction(
      () => _workoutRepository.saveWorkoutLog(
        session,
        draftToLog,
      ),
    );
    state = AsyncData(
      current.copyWith(
        workoutLog: savedLog,
      ),
    );
    _refreshAgentContext(session);
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

  Future<void> refreshAfterJimActions(Iterable<String> actions) async {
    final current = state.valueOrNull;
    if (current == null || current.session == null || actions.isEmpty) {
      return;
    }
    final normalized = actions.map((action) => action.toLowerCase()).toSet();
    final refreshWorkout = normalized.any(
      (action) => action.contains('log_workout') || action.contains('workout'),
    );
    final refreshNutrition = normalized.any(
      (action) => action.contains('log_food') || action.contains('food'),
    );
    final refreshTemplates = normalized.any(
      (action) => action.contains('template'),
    );

    var workoutLog = current.workoutLog;
    var templates = current.templates;
    var template = current.template;
    var foodLogs = current.foodLogs;
    var nutritionSummary = current.nutritionSummary;

    if (refreshWorkout && !current.workoutLog.isInProgress) {
      workoutLog = await _loadOrDefault(
        () => _workoutRepository.loadWorkoutLog(current.session),
        current.workoutLog,
      );
    }
    if (refreshTemplates) {
      templates = await _loadOrDefault(
        () => _workoutRepository.loadTemplates(current.session),
        current.templates,
      );
      if (current.template.name.trim().isEmpty && templates.isNotEmpty) {
        template = templates.last;
      }
    }
    if (refreshNutrition) {
      final remoteLogs = await _loadOrDefault(
        () => _nutritionRepository.loadFoodLogs(current.session),
        current.foodLogs,
      );
      final unsent = current.foodLogs
          .where((log) => log.foodLogId == null)
          .toList(growable: false);
      foodLogs = [...remoteLogs, ...unsent];
      nutritionSummary = await _loadOrDefault(
        () => _nutritionRepository.loadSummary(current.session),
        current.nutritionSummary,
      );
    }

    state = AsyncData(
      current.copyWith(
        workoutLog: workoutLog,
        templates: templates,
        template: template,
        foodLogs: foodLogs,
        nutritionSummary: nutritionSummary,
      ),
    );
    _refreshAgentContext(current.session);
    if (refreshWorkout) {
      ref.invalidate(historyInsightProvider);
    }
    if (refreshNutrition) {
      ref.invalidate(nutritionInsightProvider);
    }
  }

  void _refreshAgentContext(AuthSession? session) {
    if (session != null &&
        session.provider != 'mock' &&
        ref.read(agentContextRepositoryProvider)
            is! MockAgentContextRepository) {
      ref.invalidate(agentContextProvider);
    }
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

  bool _summaryHasVisibleTotals(DailyNutritionSummary summary) {
    return summary.consumedCalories > 0 ||
        summary.proteinConsumed > 0 ||
        summary.carbsConsumed > 0 ||
        summary.fatConsumed > 0;
  }

  DailyNutritionSummary _applyTargetEstimate(
    DailyNutritionSummary summary,
    UserStaticMetrics metrics, {
    bool clearUnavailableTargets = false,
  }) {
    if (clearUnavailableTargets && metrics.targetCalories <= 0) {
      return summary.copyWith(
        targetCalories: 0,
        proteinTarget: 0,
        carbsTarget: 0,
        fatTarget: 0,
        hydrationTargetLiters: 0,
      );
    }
    return summary.copyWith(
      targetCalories: metrics.targetCalories > 0
          ? metrics.targetCalories
          : summary.targetCalories,
      proteinTarget:
          metrics.proteinG > 0 ? metrics.proteinG : summary.proteinTarget,
      carbsTarget: metrics.carbsG > 0 ? metrics.carbsG : summary.carbsTarget,
      fatTarget: metrics.fatG > 0 ? metrics.fatG : summary.fatTarget,
      hydrationTargetLiters: metrics.hydrationL > 0
          ? metrics.hydrationL
          : summary.hydrationTargetLiters,
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

  Future<ProfileSyncResult> _syncOnboardingProfile({
    required AppDraftState current,
    required UserProfile profile,
    required OnboardingAnswersDto answers,
  }) async {
    if (current.session == null || current.session?.provider == 'mock') {
      final saved = await _profileRepository.saveProfile(
        current.session,
        profile,
      );
      final metrics = _localMetricsForProfile(saved);
      final savedMetrics = await _profileRepository.saveMetrics(
        current.session,
        metrics,
      );
      return ProfileSyncResult(profile: saved, metrics: savedMetrics);
    }

    try {
      final metrics = await _runProtectedAction(
        () => _profileRepository.submitAtlasOnboarding(
          current.session,
          profile,
          answers,
        ),
      );
      return ProfileSyncResult(profile: profile, metrics: metrics);
    } on AtlasProfileSyncException catch (error) {
      return _fallbackProfileSync(profile, error.message);
    } on DioException catch (error) {
      if (!_isRecoverableStartupFailure(error)) {
        rethrow;
      }
      return _fallbackProfileSync(
        profile,
        'Atlas is unavailable right now, so Jim kept local estimates. Try saving your profile again later.',
      );
    } on AuthSessionExpiredException {
      rethrow;
    } on Exception catch (error) {
      return _fallbackProfileSync(
        profile,
        'Atlas could not refresh metrics yet. Jim kept local estimates.\n'
        '${kDebugMode ? error.toString() : ''}',
      );
    }
  }

  Future<ProfileSyncResult> _syncProfileUpdate({
    required AppDraftState current,
    required UserProfile profile,
  }) async {
    if (current.session == null || current.session?.provider == 'mock') {
      final saved = await _profileRepository.saveProfile(
        current.session,
        profile,
      );
      final metrics = _localMetricsForProfile(saved);
      final savedMetrics = await _profileRepository.saveMetrics(
        current.session,
        metrics,
      );
      return ProfileSyncResult(profile: saved, metrics: savedMetrics);
    }

    try {
      final metrics = await _runProtectedAction(
        () => _profileRepository.patchAtlasProfile(
          current.session,
          previous: current.profile,
          next: profile,
        ),
      );
      return ProfileSyncResult(profile: profile, metrics: metrics);
    } on AtlasProfileSyncException catch (error) {
      return _fallbackProfileSync(profile, error.message);
    } on DioException catch (error) {
      if (!_isRecoverableStartupFailure(error)) {
        rethrow;
      }
      return _fallbackProfileSync(
        profile,
        'Atlas is unavailable right now, so Jim kept local estimates. Try saving your profile again later.',
      );
    } on AuthSessionExpiredException {
      rethrow;
    } on Exception catch (error) {
      return _fallbackProfileSync(
        profile,
        'Atlas could not refresh metrics yet. Jim kept local estimates.\n'
        '${kDebugMode ? error.toString() : ''}',
      );
    }
  }

  ProfileSyncResult _fallbackProfileSync(UserProfile profile, String warning) {
    return ProfileSyncResult(
      profile: profile,
      metrics: _localMetricsForProfile(profile),
      warning: warning.trim().isEmpty ? null : warning.trim(),
    );
  }

  UserStaticMetrics _localMetricsForProfile(UserProfile profile) {
    final estimate = NutritionTargetCalculator.estimate(profile);
    return estimate.hasRequiredProfile
        ? estimate.toMetrics()
        : const UserStaticMetrics(
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
          );
  }

  Future<void> _replaceSession(AuthSession session) async {
    ref.read(authSessionProvider.notifier).state = session;
    ref.read(isAuthenticatedProvider.notifier).state = true;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadDraftForSession(session));
    final loaded = state.valueOrNull;
    if (loaded != null && _profileLooksOnboarded(loaded.profile)) {
      ref.read(hasCompletedOnboardingProvider.notifier).state = true;
    }
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
          sex: '',
          availableTimeMinutes: 0,
          trainingPreference: '',
          activityLevel: '',
          dietaryPreference: '',
          goalTimeframe: '',
          weeksActive: 0,
          prefersVoiceLogging: false,
        ),
      ),
      _loadOrDefault<UserStaticMetrics>(
        () => _profileRepository.loadMetrics(session),
        const UserStaticMetrics(
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
      ),
      _loadOrDefault<WorkoutTemplateDraft>(
        () => _workoutRepository.loadTemplate(session),
        WorkoutTemplateDraft.empty,
      ),
      _loadOrDefault<List<WorkoutTemplateDraft>>(
        () => _workoutRepository.loadTemplates(session),
        const <WorkoutTemplateDraft>[],
      ),
      _loadOrDefault<List<WorkoutScheduleEntry>>(
        () => _workoutRepository.loadSchedule(session),
        const <WorkoutScheduleEntry>[],
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
    final loadedTemplates = results[3] as List<WorkoutTemplateDraft>;
    final templates = loadedTemplates.isEmpty && template.name.isNotEmpty
        ? <WorkoutTemplateDraft>[template]
        : loadedTemplates;
    final workoutSchedule = results[4] as List<WorkoutScheduleEntry>;
    final loadedWorkoutLog = results[5] as WorkoutLogDraft;
    final workoutLog = loadedWorkoutLog.name.isEmpty &&
            loadedWorkoutLog.notes.isEmpty &&
            loadedWorkoutLog.exercises.isEmpty
        ? loadedWorkoutLog.copyWith(
            name: template.name,
            templateId: template.templateId,
            exercises: template.exercises,
          )
        : loadedWorkoutLog;

    final profile = results[0] as UserProfile;
    final loadedMetrics = results[1] as UserStaticMetrics;
    final targetEstimate = NutritionTargetCalculator.estimate(profile);
    final estimatedMetrics = _metricsAreAvailable(loadedMetrics)
        ? loadedMetrics
        : targetEstimate.hasRequiredProfile
            ? targetEstimate.toMetrics()
            : loadedMetrics;
    final loadedSummary = results[7] as DailyNutritionSummary;
    final summaryWithTargets = _applyTargetEstimate(
      loadedSummary,
      estimatedMetrics,
    );
    final isLiveSession = session != null && session.provider != 'mock';
    final nutritionSummary = isLiveSession
        ? summaryWithTargets
        : _rebuildNutritionSummary(
            logs: results[6] as List<FoodLogDraft>,
            base: summaryWithTargets,
          );

    return AppDraftState(
      session: session,
      profile: profile,
      metrics: estimatedMetrics,
      template: template,
      templates: templates,
      workoutSchedule: workoutSchedule,
      workoutLog: workoutLog,
      foodLogs: results[6] as List<FoodLogDraft>,
      nutritionSummary: nutritionSummary,
      consistency: results[8] as ConsistencyState,
      search: _searchRepository.emptyState(),
    );
  }

  bool _metricsAreAvailable(UserStaticMetrics metrics) {
    return metrics.bmr > 0 ||
        metrics.tdee > 0 ||
        metrics.targetCalories > 0 ||
        metrics.proteinG > 0 ||
        metrics.hydrationL > 0;
  }

  Future<T> _loadOrDefault<T>(
    Future<T> Function() loader,
    T fallback,
  ) async {
    try {
      return await loader().timeout(const Duration(seconds: 9));
    } on AuthSessionExpiredException {
      rethrow;
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

  bool _profileLooksOnboarded(UserProfile profile) {
    return profile.name.trim().isNotEmpty &&
        profile.name != 'JimBro User' &&
        profile.age > 0 &&
        profile.heightCm > 0 &&
        profile.weightKg > 0 &&
        profile.goal.trim().isNotEmpty;
  }

  Future<AuthSession> _requireSessionForProtectedAction(
    AppDraftState current, {
    required String source,
    required String feature,
  }) async {
    final stateSession = current.session;
    if (stateSession != null) {
      return stateSession;
    }

    final providerSession = ref.read(authSessionProvider);
    if (providerSession != null) {
      state = AsyncData(current.copyWith(session: providerSession));
      return providerSession;
    }

    final repositorySession = await _authRepository.currentSession();
    if (repositorySession != null) {
      ref.read(authSessionProvider.notifier).state = repositorySession;
      ref.read(isAuthenticatedProvider.notifier).state = true;
      state = AsyncData(current.copyWith(session: repositorySession));
      return repositorySession;
    }

    throw Exception(
      'Authentication session missing before protected $feature.\n'
      'source: $source\n'
      'problem: The UI is inside the authenticated app flow, but AppDraftState.session, authSessionProvider, and AuthRepository.currentSession() are all null.\n'
      'likely_cause: App state was restored/advanced past auth without carrying the Supabase session into AppDraftState, or the Supabase session was cleared/expired after login.\n'
      'frontend_fix_attempted: The controller checked current AppDraftState.session, authSessionProvider, and AuthRepository.currentSession() immediately before sending the protected request.\n'
      'backend_request_sent: false\n'
      'isAuthenticatedProvider: ${ref.read(isAuthenticatedProvider)}\n'
      'hasCompletedOnboardingProvider: ${ref.read(hasCompletedOnboardingProvider)}\n'
      'session_in_state: missing\n'
      'session_in_auth_provider: missing\n'
      'next_step: Sign out/in once. If this repeats, inspect why SupabaseAuthRepository.currentSession() is null after login.',
    );
  }

  Future<T> _runProtectedAction<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthSessionExpiredException catch (error) {
      await _clearExpiredSession();
      throw AuthSessionExpiredException(
        'Your session expired. Please sign in again.\n'
        '${kDebugMode ? error.message : 'backend_request_sent: true'}',
      );
    }
  }

  Future<void> _clearExpiredSession() async {
    try {
      await _authRepository.signOut();
    } catch (_) {
      // The backend already rejected the session; local state must still clear.
    }
    ref.read(authSessionProvider.notifier).state = null;
    ref.read(isAuthenticatedProvider.notifier).state = false;
    ref.read(hasCompletedOnboardingProvider.notifier).state = false;
    ref.read(forceShowOnboardingProvider.notifier).state = false;
    ref.read(currentTabProvider.notifier).state = 0;
    state = AsyncData(await _loadDraftForSession(null));
  }
}

Map<String, Object?> _workoutLogDebugMap(WorkoutLogDraft log) {
  return {
    'workout_log_id': log.workoutLogId,
    'template_id': log.templateId,
    'name': log.name,
    'notes': log.notes,
    'started_at_label': log.startedAtLabel,
    'ended_at_label': log.endedAtLabel,
    'exercises': log.exercises.asMap().entries.map((entry) {
      final exercise = entry.value;
      return {
        'exercise_id': exercise.exerciseId,
        'exercise_name': exercise.exerciseName,
        'order_index': entry.key,
        'notes': exercise.notes,
        'sets': exercise.sets.map((setDraft) {
          return {
            'set_number': setDraft.setNumber,
            'reps': setDraft.reps,
            'weight_kg': setDraft.weightKg,
            'is_warmup': setDraft.isWarmup,
            'is_completed': setDraft.isCompleted,
            'rpe': setDraft.rpe,
          };
        }).toList(),
      };
    }).toList(),
  };
}

WorkoutLogDraft _syncWorkoutLogWithTemplateIfIdle(
  WorkoutLogDraft workoutLog,
  WorkoutTemplateDraft template,
) {
  if (workoutLog.isInProgress) {
    return workoutLog;
  }
  return workoutLog.copyWith(
    templateId: template.templateId,
    name: template.name,
    exercises: _copyWorkoutExercises(template.exercises),
  );
}

List<WorkoutExerciseDraft> _executionExercisesFromTemplate(
  List<WorkoutExerciseDraft> exercises,
) {
  return exercises.map((exercise) {
    final sets = exercise.sets.isNotEmpty
        ? exercise.sets
        : List<SetDraft>.generate(
            exercise.targetSets <= 0 ? 1 : exercise.targetSets,
            (index) => SetDraft(
              setNumber: index + 1,
              weightKg: 0,
              reps: exercise.targetReps,
              isWarmup: false,
              isCompleted: false,
              rpe: 0,
            ),
          );
    return exercise.copyWith(
      sets: sets
          .asMap()
          .entries
          .map(
            (entry) => entry.value.copyWith(
              setNumber: entry.key + 1,
              isCompleted: false,
            ),
          )
          .toList(growable: false),
    );
  }).toList(growable: false);
}

List<WorkoutExerciseDraft> _copyWorkoutExercises(
  List<WorkoutExerciseDraft> exercises,
) {
  return exercises
      .map(
        (exercise) => exercise.copyWith(
          sets: exercise.sets
              .map(
                (setDraft) => setDraft.copyWith(),
              )
              .toList(growable: false),
        ),
      )
      .toList(growable: false);
}

List<WorkoutTemplateDraft> _upsertWorkoutTemplate(
  List<WorkoutTemplateDraft> templates,
  WorkoutTemplateDraft saved,
) {
  final existingIndex = templates.indexWhere(
    (template) => template.templateId == saved.templateId,
  );
  if (existingIndex == -1) {
    return [...templates, saved];
  }
  final updated = [...templates];
  updated[existingIndex] = saved;
  return updated;
}

List<WorkoutScheduleEntry> _upsertWorkoutSchedule(
  List<WorkoutScheduleEntry> schedule,
  WorkoutScheduleEntry saved,
) {
  final existingIndex = schedule.indexWhere(
    (entry) =>
        entry.scheduleId == saved.scheduleId || entry.weekday == saved.weekday,
  );
  if (existingIndex == -1) {
    return [...schedule, saved]..sort(_compareScheduleEntries);
  }
  final updated = [...schedule];
  updated[existingIndex] = saved;
  return updated..sort(_compareScheduleEntries);
}

int _compareScheduleEntries(
  WorkoutScheduleEntry left,
  WorkoutScheduleEntry right,
) {
  return left.weekday.compareTo(right.weekday);
}

WorkoutScheduleEntry? _scheduleForWeekday(
  List<WorkoutScheduleEntry> schedule,
  int weekday,
) {
  for (final entry in schedule) {
    if (entry.weekday == weekday && entry.active) {
      return entry;
    }
  }
  return null;
}

WorkoutTemplateDraft? _templateForSchedule(
  List<WorkoutTemplateDraft> templates,
  WorkoutScheduleEntry entry,
) {
  for (final template in templates) {
    if (template.templateId == entry.templateId) {
      return template;
    }
  }
  final fallbackName = entry.templateName.trim().toLowerCase();
  if (fallbackName.isEmpty) {
    return null;
  }
  for (final template in templates) {
    if (template.name.trim().toLowerCase() == fallbackName) {
      return template;
    }
  }
  return null;
}

String _normalizeScheduleTime(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value.trim());
  if (match == null) {
    return '18:00';
  }
  final hour = int.tryParse(match.group(1) ?? '') ?? 18;
  final minute = int.tryParse(match.group(2) ?? '') ?? 0;
  return '${hour.clamp(0, 23).toString().padLeft(2, '0')}:'
      '${minute.clamp(0, 59).toString().padLeft(2, '0')}';
}
