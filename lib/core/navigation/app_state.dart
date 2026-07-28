import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/profile_schema_exception.dart';
import '../../core/nutrition/nutrition_targets.dart';
import '../../core/notifications/workout_notification_service.dart';
import '../../core/repositories/app_repositories.dart';
import '../../shared/models/app_models.dart';
import '../../shared/models/atlas_insight.dart';
import '../../shared/models/onboarding_models.dart';

enum AppBootstrapStatus {
  unauthenticated,
  authenticating,
  authenticatedProvisioning,
  onboardingRequired,
  ready,
  expired,
  recoverableError,
  fatalError,
}

class AppBootstrapState {
  const AppBootstrapState({
    required this.status,
    this.session,
    this.error,
  });

  const AppBootstrapState.authenticating()
      : this(status: AppBootstrapStatus.authenticating);

  final AppBootstrapStatus status;
  final AuthSession? session;
  final Object? error;

  bool get isAuthenticated =>
      session != null &&
      status != AppBootstrapStatus.unauthenticated &&
      status != AppBootstrapStatus.expired;

  bool get onboardingCompleted => status == AppBootstrapStatus.ready;

  bool get allowsProtectedWrites =>
      status == AppBootstrapStatus.onboardingRequired ||
      status == AppBootstrapStatus.ready;

  AppBootstrapState copyWith({
    AppBootstrapStatus? status,
    Object? session = _bootstrapUnset,
    Object? error = _bootstrapUnset,
  }) {
    return AppBootstrapState(
      status: status ?? this.status,
      session: identical(session, _bootstrapUnset)
          ? this.session
          : session as AuthSession?,
      error: identical(error, _bootstrapUnset) ? this.error : error,
    );
  }
}

const _bootstrapUnset = Object();

AppBootstrapStatus _bootstrapFailureStatus(Object error) {
  if (error is AuthSessionExpiredException ||
      error is AppError && error.code == AppErrorCode.sessionExpired) {
    return AppBootstrapStatus.expired;
  }
  if (error is UserProvisioningException) {
    return AppBootstrapStatus.fatalError;
  }
  final mapped = mapAppError(
    error,
    fallbackMessage:
        'JimBro could not load your profile. Please try again or sign out.',
    method: 'GET',
    route: '/supabase/profile',
  );
  return mapped.diagnostics.retryable
      ? AppBootstrapStatus.recoverableError
      : AppBootstrapStatus.fatalError;
}

final appBootstrapProvider = StateProvider<AppBootstrapState>(
  (ref) => const AppBootstrapState.authenticating(),
);
final authSessionProvider = Provider<AuthSession?>(
  (ref) => ref.watch(appBootstrapProvider).session,
);
final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(appBootstrapProvider).isAuthenticated,
);
final hasCompletedOnboardingProvider = Provider<bool>(
  (ref) => ref.watch(appBootstrapProvider).onboardingCompleted,
);
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

final workoutHistoryProvider =
    FutureProvider<List<WorkoutLogDraft>>((ref) async {
  final repository = ref.watch(workoutRepositoryProvider);
  final session = ref.watch(authSessionProvider);
  if (repository is WorkoutHistoryRepository) {
    return (repository as WorkoutHistoryRepository).loadWorkoutHistory(session);
  }
  final latest = await repository.loadWorkoutLog(session);
  return latest.workoutLogId == null ? const [] : [latest];
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
  final session = ref.watch(authSessionProvider);
  if (session == null || session.provider == 'mock') {
    return AgentContextSnapshot.empty;
  }
  return repository.load(session);
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
    this.profileSyncStatus = ProfileSyncStatus.synced,
    this.atlasMetricsStatus = AtlasMetricsStatus.available,
    this.lastSyncErrorCode,
  });

  final UserProfile profile;
  final UserStaticMetrics metrics;
  final String? warning;
  final ProfileSyncStatus profileSyncStatus;
  final AtlasMetricsStatus atlasMetricsStatus;
  final String? lastSyncErrorCode;

  bool get hasWarning => warning != null && warning!.trim().isNotEmpty;
}

class AppDraftController extends AsyncNotifier<AppDraftState> {
  int _bootstrapGeneration = 0;
  Future<void>? _sessionBootstrapInFlight;
  String? _sessionBootstrapUserId;
  Future<WorkoutTemplateDraft>? _templateSaveInFlight;

  AuthRepository get _authRepository => ref.read(authRepositoryProvider);
  AccountRepository get _accountRepository =>
      ref.read(accountRepositoryProvider);
  LocalAccountDataStore get _localAccountDataStore =>
      ref.read(localAccountDataStoreProvider);
  WorkoutTemplateDraftStore get _workoutTemplateDraftStore =>
      ref.read(workoutTemplateDraftStoreProvider);
  ProfileRepository get _profileRepository =>
      ref.read(profileRepositoryProvider);
  WorkoutRepository get _workoutRepository =>
      ref.read(workoutRepositoryProvider);
  WorkoutNotificationService get _workoutNotificationService =>
      ref.read(workoutNotificationServiceProvider);
  NutritionRepository get _nutritionRepository =>
      ref.read(nutritionRepositoryProvider);
  ProgramRepository get _programRepository =>
      ref.read(programRepositoryProvider);
  ConsistencyRepository get _consistencyRepository =>
      ref.read(consistencyRepositoryProvider);

  @override
  Future<AppDraftState> build() async {
    ref.watch(authRepositoryProvider);
    ref.watch(accountRepositoryProvider);
    ref.watch(localAccountDataStoreProvider);
    ref.watch(profileRepositoryProvider);
    ref.watch(workoutRepositoryProvider);
    ref.watch(workoutNotificationServiceProvider);
    ref.watch(nutritionRepositoryProvider);
    ref.watch(programRepositoryProvider);
    ref.watch(consistencyRepositoryProvider);

    final generation = ++_bootstrapGeneration;
    _setBootstrap(const AppBootstrapState.authenticating());
    try {
      final session = await _authRepository.currentSession();
      if (session == null) {
        final draft = await _loadDraftForSession(null);
        if (generation == _bootstrapGeneration) {
          _setBootstrap(
            const AppBootstrapState(
              status: AppBootstrapStatus.unauthenticated,
            ),
          );
        }
        return draft;
      }
      _setBootstrap(
        AppBootstrapState(
          status: AppBootstrapStatus.authenticatedProvisioning,
          session: session,
        ),
      );
      final bootstrap = await _confirmApplicationUser(session);
      await _flushPending(session);
      final draft = await _loadDraftForSession(
        session,
        canonicalProfile: bootstrap.profile,
      );
      if (generation == _bootstrapGeneration) {
        final onboardingCompleted = bootstrap.onboardingCompleted ?? false;
        final nextStatus = onboardingCompleted
            ? AppBootstrapStatus.ready
            : AppBootstrapStatus.onboardingRequired;
        _setBootstrap(
          ref.read(appBootstrapProvider).copyWith(
                status: nextStatus,
                session: session,
                error: null,
              ),
        );
        if (kDebugMode) {
          debugPrint(
            'Profile bootstrap assignment: status=${nextStatus.name} '
            'loading=false errorCleared=true.',
          );
        }
      }
      return draft;
    } on AuthSessionExpiredException {
      try {
        await _authRepository.signOut();
      } catch (_) {
        // The backend rejected the session; local state still returns to Auth.
      }
      ref.read(forceShowOnboardingProvider.notifier).state = false;
      ref.read(currentTabProvider.notifier).state = 0;
      final draft = await _loadDraftForSession(null);
      if (generation == _bootstrapGeneration) {
        _setBootstrap(
          const AppBootstrapState(status: AppBootstrapStatus.expired),
        );
      }
      return draft;
    } catch (error) {
      if (generation == _bootstrapGeneration) {
        _setBootstrap(
          AppBootstrapState(
            status: _bootstrapFailureStatus(error),
            session: ref.read(appBootstrapProvider).session,
            error: error,
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> signInWithMockProvider(String provider) async {
    final session = await _authRepository.signInWithMockProvider(provider);
    await _bootstrapSession(session);
  }

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final session = await _authRepository.signInWithEmailPassword(
      email: email,
      password: password,
    );
    await _bootstrapSession(session);
  }

  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final repository = _authRepository;
    if (repository is! EmailSignUpRepository) {
      throw UnsupportedError('Email sign-up is unavailable in this mode.');
    }
    final session =
        await (repository as EmailSignUpRepository).signUpWithEmailPassword(
      email: email,
      password: password,
    );
    await _bootstrapSession(session);
  }

  Future<void> retryAccountProvisioning() async {
    final session =
        ref.read(authSessionProvider) ?? await _authRepository.currentSession();
    if (session == null) {
      throw const AuthSessionExpiredException(
        'Your session expired. Please sign in again.',
      );
    }
    await _bootstrapSession(session);
  }

  Future<void> signOut() async {
    await _clearLocalSession();
  }

  Future<void> deleteAccount() async {
    final current = state.valueOrNull;
    if (current == null) {
      throw const AccountDeletionException();
    }
    final session = await _requireSessionForProtectedAction(
      current,
      source: 'lib/core/navigation/app_state.dart -> deleteAccount',
      feature: 'account deletion',
    );
    await _accountRepository.deleteAccount(session);
    await _clearLocalSession(deletedAccount: session);
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
        profileSyncStatus: result.profileSyncStatus,
        atlasMetricsStatus: result.atlasMetricsStatus,
        lastLocalProfileUpdate: DateTime.now(),
        lastBackendProfileUpdate:
            result.profileSyncStatus == ProfileSyncStatus.synced
                ? DateTime.now()
                : null,
        lastSyncErrorCode: result.lastSyncErrorCode,
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
    final localMetrics = _localMetricsForProfile(profile);
    state = AsyncData(
      current.copyWith(
        profile: profile,
        metrics: localMetrics,
        nutritionSummary: _applyTargetEstimate(
          current.nutritionSummary,
          localMetrics,
          clearUnavailableTargets: !_metricsAreAvailable(localMetrics),
        ),
        profileSyncStatus: ProfileSyncStatus.pending,
        atlasMetricsStatus: AtlasMetricsStatus.pending,
        lastLocalProfileUpdate: DateTime.now(),
        lastSyncErrorCode: null,
        programGenerationChoice: ProgramGenerationChoice.pending,
        programGenerationStatus: ProgramGenerationStatus.idle,
      ),
    );
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
        profileSyncStatus: result.profileSyncStatus,
        atlasMetricsStatus: result.atlasMetricsStatus,
        lastLocalProfileUpdate: DateTime.now(),
        lastBackendProfileUpdate:
            result.profileSyncStatus == ProfileSyncStatus.synced
                ? DateTime.now()
                : null,
        lastSyncErrorCode: result.lastSyncErrorCode,
        programGenerationChoice: ProgramGenerationChoice.pending,
        programGenerationStatus: ProgramGenerationStatus.idle,
      ),
    );
    _refreshAgentContext(current.session);
    return result;
  }

  Future<ProgramGenerationResult> generateProgramAfterOnboarding() async {
    final current = state.valueOrNull;
    if (current == null) {
      return const ProgramGenerationResult.failure(
        'Jim could not build your split yet. You can retry or skip for now.',
      );
    }
    if (current.programGenerationStatus == ProgramGenerationStatus.generating) {
      return const ProgramGenerationResult.failure(
        'Jim is already building your split.',
      );
    }

    state = AsyncData(
      current.copyWith(
        programGenerationChoice: ProgramGenerationChoice.accepted,
        programGenerationStatus: ProgramGenerationStatus.generating,
      ),
    );

    final result = await _programRepository.generateProgram(current.session);
    final latest = state.valueOrNull ?? current;
    if (!result.isSuccess) {
      state = AsyncData(
        latest.copyWith(
          programGenerationChoice: ProgramGenerationChoice.accepted,
          programGenerationStatus: ProgramGenerationStatus.failed,
        ),
      );
      return result;
    }

    var templates = latest.templates;
    var template = latest.template;
    var schedule = latest.workoutSchedule;
    var workoutLog = latest.workoutLog;
    if (latest.session != null) {
      templates = await _loadOrDefault(
        () => _workoutRepository.loadTemplates(latest.session),
        latest.templates,
      );
      if (templates.isNotEmpty) {
        template = templates.last;
      }
      schedule = await _loadOrDefault(
        () => _workoutRepository.loadSchedule(latest.session),
        latest.workoutSchedule,
      );
      workoutLog = await _loadOrDefault(
        () => _workoutRepository.loadWorkoutLog(latest.session),
        latest.workoutLog,
      );
    }

    state = AsyncData(
      latest.copyWith(
        templates: templates,
        template: template,
        workoutSchedule: schedule,
        workoutLog: workoutLog,
        programGenerationChoice: ProgramGenerationChoice.accepted,
        programGenerationStatus: ProgramGenerationStatus.generated,
      ),
    );
    _refreshAgentContext(latest.session);
    ref.read(currentTabProvider.notifier).state = 0;
    return result;
  }

  Future<void> skipProgramGenerationAfterOnboarding() async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        programGenerationChoice: ProgramGenerationChoice.skipped,
        programGenerationStatus: ProgramGenerationStatus.idle,
      ),
    );
    ref.read(currentTabProvider.notifier).state = 0;
  }

  Future<ProfileSyncResult?> retryProfileSync() async {
    final current = state.valueOrNull;
    if (current == null) {
      return null;
    }
    return updateProfile(current.profile);
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
        templateDraftDirty: true,
      ),
    );
    await _workoutTemplateDraftStore.write(current.session, template);
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
        templateDraftDirty: false,
      ),
    );
    await _workoutTemplateDraftStore.clear(current.session);
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
        templateDraftDirty: false,
      ),
    );
    await _workoutTemplateDraftStore.clear(current.session);
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
    return _workoutRepository.searchExercises(
      query,
      state.valueOrNull?.session,
    );
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
    newFoodLogs[index] = (changedFoodDefinition
            ? rescaledFoodLog.copyWith(foodId: null)
            : rescaledFoodLog)
        .copyWith(isDirty: true);
    state = AsyncData(
      current.copyWith(
        foodLogs: newFoodLogs,
      ),
    );
  }

  Future<List<FoodSuggestion>> searchFoodSuggestions(String query) async {
    return _nutritionRepository.searchFoods(
      query,
      state.valueOrNull?.session,
    );
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
    newFoodLogs[index] =
        suggestion.applyTo(newFoodLogs[index]).copyWith(isDirty: true);
    state = AsyncData(
      current.copyWith(
        foodLogs: newFoodLogs,
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
      ),
    );
  }

  Future<FoodLogDraft> deleteFoodLog(int index) async {
    final current = state.valueOrNull;
    if (current == null) {
      throw Exception('Nutrition state is not ready.');
    }
    final deleted = current.foodLogs[index];
    final next = [...current.foodLogs]..removeAt(index);
    if (deleted.foodLogId == null) {
      state = AsyncData(current.copyWith(foodLogs: next));
      return deleted;
    }
    await _saveFoodLogs(current, next);
    return deleted;
  }

  Future<void> restoreDeletedFoodLog(
    int index,
    FoodLogDraft deleted,
  ) async {
    final current = state.valueOrNull;
    if (current == null) {
      throw Exception('Nutrition state is not ready.');
    }
    final restored = deleted.copyWith(foodLogId: null);
    final next = [...current.foodLogs]
      ..insert(index.clamp(0, current.foodLogs.length), restored);
    if (deleted.foodLogId == null) {
      state = AsyncData(current.copyWith(foodLogs: next));
      return;
    }
    await _saveFoodLogs(current, next);
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

  Future<NutritionMutationResult> _saveFoodLogs(
    AppDraftState current,
    List<FoodLogDraft> logs,
  ) async {
    final session = await _requireSessionForProtectedAction(
      current,
      source: 'lib/core/navigation/app_state.dart -> _saveFoodLogs',
      feature: 'nutrition save',
    );
    final mutation = await _runProtectedAction(
      () => _nutritionRepository.saveFoodLogs(
        session,
        logs,
      ),
    );
    final savedLogs = mutation.entries;
    final savedSummary = mutation.summary;
    final usesAuthoritativeBackendTotals =
        _nutritionRepository is! MockNutritionRepository;
    final summaryFromLogs = _rebuildNutritionSummary(
      logs: savedLogs,
      base: current.nutritionSummary,
    );
    state = AsyncData(
      current.copyWith(
        foodLogs: savedLogs,
        nutritionSummary: usesAuthoritativeBackendTotals
            ? (_summaryHasVisibleTotals(savedSummary) || savedLogs.isEmpty
                ? savedSummary
                : summaryFromLogs)
            : summaryFromLogs,
      ),
    );
    _refreshAgentContext(session);
    return mutation;
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
    final inFlight = _templateSaveInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final save = _saveWorkoutTemplateOnce();
    _templateSaveInFlight = save;
    try {
      return await save;
    } finally {
      _templateSaveInFlight = null;
    }
  }

  Future<WorkoutTemplateDraft> _saveWorkoutTemplateOnce() async {
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
        templateDraftDirty: false,
      ),
    );
    await _workoutTemplateDraftStore.clear(session);
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
          templateDraftDirty: false,
        ),
      );
      await _workoutTemplateDraftStore.clear(current.session);
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

  Future<WorkoutMutationResult> logWorkoutSession() async {
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
        'JimBro workout log prepared: '
        'exercise_count=${draftToLog.exercises.length} '
        'set_count=${draftToLog.exercises.fold<int>(0, (total, exercise) => total + exercise.sets.length)}. '
        'No member or exercise values logged.',
      );
    }
    final result = await _runProtectedAction(
      () => _workoutRepository.saveWorkoutLog(
        session,
        draftToLog,
      ),
    );
    final displayedWorkout = result.authoritativeWorkout ?? draftToLog;
    state = AsyncData(current.copyWith(
      workoutLog: displayedWorkout,
      lastWorkoutMutation: result,
    ));
    _refreshAgentContext(session);
    return result;
  }

  Future<WorkoutMutationResult> finishActiveWorkout(
    ActiveWorkoutSession activeSession,
  ) async {
    final current = state.valueOrNull;
    if (current == null) {
      throw Exception('Workout state is not ready.');
    }
    final session = await _requireSessionForProtectedAction(
      current,
      source: 'lib/core/navigation/app_state.dart -> finishActiveWorkout',
      feature: 'active workout completion',
    );

    final pending = current.lastWorkoutMutation;
    if (pending != null &&
        pending.mutationId == activeSession.sessionId &&
        pending.syncStatus == WorkoutSyncStatus.pendingSync) {
      await _runProtectedAction(() => _workoutRepository.flushPending(session));
      final authoritative = await _runProtectedAction(
          () => _workoutRepository.loadWorkoutLog(session));
      if (authoritative.workoutLogId != null) {
        final synced = WorkoutMutationResult(
          localWorkoutId: pending.localWorkoutId,
          serverLogId: authoritative.workoutLogId,
          mutationId: pending.mutationId,
          syncStatus: WorkoutSyncStatus.synced,
          errorCode: null,
          retryable: false,
          authoritativeWorkout: authoritative,
        );
        state = AsyncData(
          current.copyWith(
            workoutLog: authoritative,
            lastWorkoutMutation: synced,
          ),
        );
        return synced;
      }
      return pending;
    }

    final draftToLog = activeSession.toCompletedDraft(DateTime.now());
    final repository = _workoutRepository;
    final result = await _runProtectedAction(
      () => repository is IdempotentWorkoutCompletionRepository
          ? (repository as IdempotentWorkoutCompletionRepository).finishWorkout(
              session,
              draftToLog,
              mutationId: activeSession.sessionId,
            )
          : repository.saveWorkoutLog(session, draftToLog),
    );
    final displayedWorkout = result.authoritativeWorkout ?? draftToLog;
    state = AsyncData(
      current.copyWith(
        workoutLog: displayedWorkout,
        lastWorkoutMutation: result,
      ),
    );
    _refreshAgentContext(session);
    ref.invalidate(workoutHistoryProvider);
    return result;
  }

  Future<void> retryWorkoutSync() async {
    final current = state.valueOrNull;
    final pending = current?.lastWorkoutMutation;
    if (current == null || pending == null || !pending.retryable) {
      return;
    }
    final session = await _requireSessionForProtectedAction(
      current,
      source: 'lib/core/navigation/app_state.dart -> retryWorkoutSync',
      feature: 'workout sync retry',
    );
    await _workoutRepository.flushPending(session);
    final authoritative = await _workoutRepository.loadWorkoutLog(session);
    if (authoritative.workoutLogId == null) {
      return;
    }
    state = AsyncData(current.copyWith(
      workoutLog: authoritative,
      lastWorkoutMutation: WorkoutMutationResult(
        localWorkoutId: pending.localWorkoutId,
        serverLogId: authoritative.workoutLogId,
        mutationId: pending.mutationId,
        syncStatus: WorkoutSyncStatus.synced,
        errorCode: null,
        retryable: false,
        authoritativeWorkout: authoritative,
      ),
    ));
  }

  Future<NutritionMutationResult> saveNutritionLogs() async {
    final current = state.valueOrNull;
    if (current == null) {
      throw Exception('Nutrition state is not ready.');
    }
    return _saveFoodLogs(current, current.foodLogs);
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
    if (current.session == null ||
        current.session?.provider == 'mock' ||
        _profileRepository is MockProfileRepository) {
      final saved = await _profileRepository.saveProfile(
        current.session,
        profile,
        onboardingCompleted: true,
      );
      final metrics = _localMetricsForProfile(saved);
      final savedMetrics = await _profileRepository.saveMetrics(
        current.session,
        metrics,
      );
      return ProfileSyncResult(profile: saved, metrics: savedMetrics);
    }

    final canonicalProfile = await _profileRepository.saveProfile(
      current.session,
      profile,
      onboardingCompleted: true,
    );

    try {
      var metrics = await _runProtectedAction(
        () => _profileRepository.submitAtlasOnboarding(
          current.session,
          canonicalProfile,
          answers,
        ),
      );
      try {
        final patchedMetrics = await _runProtectedAction(
          () => _profileRepository.patchAtlasProfile(
            current.session,
            previous: current.profile,
            next: canonicalProfile,
          ),
        );
        if (_metricsAreAvailable(patchedMetrics)) {
          metrics = patchedMetrics;
        }
      } on AuthSessionExpiredException {
        rethrow;
      } on Exception {
        // Onboarding metrics remain usable when the follow-up profile patch
        // is not yet supported by the deployed coaching service.
      }
      if (!_metricsAreAvailable(metrics)) {
        return _fallbackProfileSync(
          canonicalProfile,
          'Your setup is saved on this device. Atlas is still preparing your coaching targets.',
        );
      }
      return ProfileSyncResult(profile: canonicalProfile, metrics: metrics);
    } on AtlasProfileSyncException catch (error) {
      return _fallbackProfileSync(canonicalProfile, error.message);
    } on DioException catch (error) {
      if (!_isRecoverableStartupFailure(error)) {
        rethrow;
      }
      return _fallbackProfileSync(
        canonicalProfile,
        'Your setup is saved on this device. Jim will sync it when the coaching service is available.',
      );
    } on AuthSessionExpiredException {
      rethrow;
    } on Exception {
      return _fallbackProfileSync(
        canonicalProfile,
        'Your setup is saved on this device. Jim will sync it when the coaching service is available.',
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

    final canonicalProfile = await _profileRepository.saveProfile(
      current.session,
      profile,
    );

    try {
      final metrics = await _runProtectedAction(
        () => _profileRepository.patchAtlasProfile(
          current.session,
          previous: current.profile,
          next: canonicalProfile,
        ),
      );
      if (!_metricsAreAvailable(metrics)) {
        return _fallbackProfileSync(
          canonicalProfile,
          'Your profile is saved. Atlas is still preparing your coaching targets.',
        );
      }
      return ProfileSyncResult(profile: canonicalProfile, metrics: metrics);
    } on AtlasProfileSyncException catch (error) {
      return _fallbackProfileSync(canonicalProfile, error.message);
    } on DioException catch (error) {
      if (!_isRecoverableStartupFailure(error)) {
        rethrow;
      }
      return _fallbackProfileSync(
        canonicalProfile,
        'Atlas is unavailable right now, so Jim kept local estimates. Try saving your profile again later.',
      );
    } on AuthSessionExpiredException {
      rethrow;
    } on Exception {
      return _fallbackProfileSync(
        canonicalProfile,
        'Atlas could not refresh metrics yet. Jim kept local estimates.',
      );
    }
  }

  ProfileSyncResult _fallbackProfileSync(UserProfile profile, String warning) {
    return ProfileSyncResult(
      profile: profile,
      metrics: _localMetricsForProfile(profile),
      warning: warning.trim().isEmpty ? null : warning.trim(),
      profileSyncStatus: ProfileSyncStatus.pending,
      atlasMetricsStatus: AtlasMetricsStatus.pending,
      lastSyncErrorCode: 'atlas_sync_pending',
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

  Future<void> _bootstrapSession(AuthSession session) {
    final existing = _sessionBootstrapInFlight;
    if (existing != null && _sessionBootstrapUserId == session.userId) {
      return existing;
    }

    final operation = _replaceSession(session);
    _sessionBootstrapInFlight = operation;
    _sessionBootstrapUserId = session.userId;
    void clearInFlight() {
      if (identical(_sessionBootstrapInFlight, operation)) {
        _sessionBootstrapInFlight = null;
        _sessionBootstrapUserId = null;
      }
    }

    unawaited(
      operation.then<void>(
        (_) => clearInFlight(),
        onError: (Object _, StackTrace __) => clearInFlight(),
      ),
    );
    return operation;
  }

  Future<void> _replaceSession(AuthSession session) async {
    final generation = ++_bootstrapGeneration;
    _setBootstrap(
      AppBootstrapState(
        status: AppBootstrapStatus.authenticatedProvisioning,
        session: session,
      ),
    );
    state = const AsyncLoading();
    try {
      final bootstrap = await _confirmApplicationUser(session);
      final loaded = await _loadDraftForSession(
        session,
        canonicalProfile: bootstrap.profile,
      );
      if (generation != _bootstrapGeneration) {
        return;
      }
      state = AsyncData(loaded);
      final onboardingCompleted = bootstrap.onboardingCompleted ?? false;
      final nextStatus = onboardingCompleted
          ? AppBootstrapStatus.ready
          : AppBootstrapStatus.onboardingRequired;
      _setBootstrap(
        ref.read(appBootstrapProvider).copyWith(
              status: nextStatus,
              session: session,
              error: null,
            ),
      );
      if (kDebugMode) {
        debugPrint(
          'Profile bootstrap transition: status=${nextStatus.name} '
          'errorCleared=true.',
        );
      }
    } catch (error, stackTrace) {
      if (generation != _bootstrapGeneration) {
        return;
      }
      if (error is AuthSessionExpiredException) {
        try {
          await _authRepository.signOut();
        } catch (_) {
          // The session is unusable locally even if remote sign-out fails.
        }
      }
      state = AsyncError(error, stackTrace);
      _setBootstrap(
        AppBootstrapState(
          status: _bootstrapFailureStatus(error),
          session: error is AuthSessionExpiredException ? null : session,
          error: error,
        ),
      );
      rethrow;
    }
  }

  void _setBootstrap(AppBootstrapState bootstrap) {
    final previous = ref.read(appBootstrapProvider);
    if (kDebugMode &&
        (previous.status != bootstrap.status ||
            previous.session?.userId != bootstrap.session?.userId)) {
      debugPrint(
        'JimBro bootstrap transition: generation=$_bootstrapGeneration '
        'from=${previous.status.name} to=${bootstrap.status.name} '
        'sessionPresent=${bootstrap.session != null} '
        'errorType=${bootstrap.error?.runtimeType ?? 'none'}.',
      );
    }
    ref.read(appBootstrapProvider.notifier).state = bootstrap;
  }

  void markOnboardingComplete() {
    final bootstrap = ref.read(appBootstrapProvider);
    final session = bootstrap.session;
    if (session == null) {
      return;
    }
    _setBootstrap(
      AppBootstrapState(
        status: AppBootstrapStatus.ready,
        session: session,
      ),
    );
  }

  Future<ApplicationUserProvisioningResult> _confirmApplicationUser(
    AuthSession session,
  ) async {
    try {
      final result = await _accountRepository.provisionAuthenticatedUser(
        session,
      );
      if (result.applicationUserId.trim().isEmpty) {
        throw const UserProvisioningException();
      }
      if (kDebugMode) {
        debugPrint(
          result.reconciled
              ? 'Application user ready. code=AUTH_USER_RECONCILED.'
              : 'Application user profile lookup confirmed.',
        );
      }
      return result;
    } on AuthSessionExpiredException {
      rethrow;
    } on AppError {
      rethrow;
    } on DioException {
      rethrow;
    } on ProfileSchemaException {
      rethrow;
    } on UserProvisioningException {
      rethrow;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Application-user provisioning failed. '
          'code=USER_PROVISIONING_FAILED error_type=${error.runtimeType}. '
          'No token or profile payload logged.',
        );
      }
      throw AppError(
        code: AppErrorCode.malformedResponse,
        userMessage:
            'JimBro received profile data it could not read. Please try again or sign out.',
        diagnostics: const AppErrorDiagnostics(
          method: 'GET',
          route: '/supabase/profile',
          retryable: false,
        ),
      );
    }
  }

  Future<void> _clearLocalSession({AuthSession? deletedAccount}) async {
    ++_bootstrapGeneration;
    final signingOutSession = state.valueOrNull?.session;
    if (signingOutSession != null) {
      await _workoutTemplateDraftStore.clear(signingOutSession);
    }
    if (deletedAccount != null) {
      for (final repository in <Object>[
        _profileRepository,
        _workoutRepository,
        _nutritionRepository,
      ]) {
        if (repository is UserScopedCache) {
          repository.clearUserCache(deletedAccount.userId);
        }
      }
    }
    try {
      await _authRepository.signOut();
    } catch (_) {
      if (deletedAccount == null) {
        rethrow;
      }
    }
    _setBootstrap(
      const AppBootstrapState(
        status: AppBootstrapStatus.unauthenticated,
      ),
    );
    ref.read(forceShowOnboardingProvider.notifier).state = false;
    ref.read(currentTabProvider.notifier).state = 0;
    state = const AsyncLoading();
    if (deletedAccount != null) {
      try {
        await _localAccountDataStore.clearDeletedAccount(deletedAccount);
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            'JimBro deleted-account local cleanup deferred: '
            '${error.runtimeType}. No account data values logged.',
          );
        }
      }
    }
    state = await AsyncValue.guard(() => _loadDraftForSession(null));
  }

  Future<AppDraftState> _loadDraftForSession(
    AuthSession? session, {
    UserProfile? canonicalProfile,
  }) async {
    final results = await Future.wait<Object?>([
      canonicalProfile != null
          ? Future<UserProfile>.value(canonicalProfile)
          : _loadOrDefault<UserProfile>(
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
      _workoutTemplateDraftStore.load(session),
      _workoutRepository is PendingWorkoutMutationSource
          ? (_workoutRepository as PendingWorkoutMutationSource)
              .loadPendingWorkoutMutation(session)
          : Future<WorkoutMutationResult?>.value(),
    ]);

    final loadedTemplates = results[2] as List<WorkoutTemplateDraft>;
    final templates = loadedTemplates;
    final checkpoint = results[8] as WorkoutTemplateDraft?;
    final pendingWorkout = results[9] as WorkoutMutationResult?;
    final template = checkpoint ??
        (templates.isEmpty ? WorkoutTemplateDraft.empty : templates.last);
    final workoutSchedule = results[3] as List<WorkoutScheduleEntry>;
    final loadedWorkoutLog = results[4] as WorkoutLogDraft;
    final workoutLog = pendingWorkout?.authoritativeWorkout ??
        (loadedWorkoutLog.name.isEmpty &&
                loadedWorkoutLog.notes.isEmpty &&
                loadedWorkoutLog.exercises.isEmpty
            ? loadedWorkoutLog.copyWith(
                name: template.name,
                templateId: template.templateId,
                exercises: template.exercises,
              )
            : loadedWorkoutLog);

    final profile = results[0] as UserProfile;
    final loadedMetrics = results[1] as UserStaticMetrics;
    final targetEstimate = NutritionTargetCalculator.estimate(profile);
    final estimatedMetrics = _metricsAreAvailable(loadedMetrics)
        ? loadedMetrics
        : targetEstimate.hasRequiredProfile
            ? targetEstimate.toMetrics()
            : loadedMetrics;
    final loadedSummary = results[6] as DailyNutritionSummary;
    final summaryWithTargets = _applyTargetEstimate(
      loadedSummary,
      estimatedMetrics,
    );
    final isLiveSession = session != null && session.provider != 'mock';
    final nutritionSummary = isLiveSession
        ? summaryWithTargets
        : _rebuildNutritionSummary(
            logs: results[5] as List<FoodLogDraft>,
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
      foodLogs: results[5] as List<FoodLogDraft>,
      nutritionSummary: nutritionSummary,
      consistency: results[7] as ConsistencyState,
      profileSyncStatus: ProfileSyncStatus.synced,
      atlasMetricsStatus: _metricsAreAvailable(loadedMetrics)
          ? AtlasMetricsStatus.available
          : _metricsAreAvailable(estimatedMetrics)
              ? AtlasMetricsStatus.pending
              : AtlasMetricsStatus.unavailable,
      templateDraftDirty: checkpoint != null,
      templatesAreStale: _workoutRepository is TemplateLoadMetadata &&
          (_workoutRepository as TemplateLoadMetadata).templatesAreStale,
      lastWorkoutMutation: pendingWorkout,
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

  Future<AuthSession> _requireSessionForProtectedAction(
    AppDraftState current, {
    required String source,
    required String feature,
  }) async {
    final bootstrap = ref.read(appBootstrapProvider);
    if (!bootstrap.allowsProtectedWrites) {
      throw AppError(
        code: AppErrorCode.synchronizationFailed,
        userMessage: 'Your account is still being prepared. Please wait.',
        diagnostics: const AppErrorDiagnostics(retryable: true),
      );
    }
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
      state = AsyncData(current.copyWith(session: repositorySession));
      return repositorySession;
    }

    throw AppError(
      code: AppErrorCode.sessionExpired,
      userMessage: 'Your session expired. Please sign in again.',
      diagnostics: const AppErrorDiagnostics(retryable: false),
    );
  }

  Future<T> _runProtectedAction<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthSessionExpiredException {
      await _clearExpiredSession();
      throw const AuthSessionExpiredException(
        'Your session expired. Please sign in again.',
      );
    }
  }

  Future<void> _clearExpiredSession() async {
    ++_bootstrapGeneration;
    try {
      await _authRepository.signOut();
    } catch (_) {
      // The backend already rejected the session; local state must still clear.
    }
    _setBootstrap(
      const AppBootstrapState(status: AppBootstrapStatus.expired),
    );
    ref.read(forceShowOnboardingProvider.notifier).state = false;
    ref.read(currentTabProvider.notifier).state = 0;
    state = AsyncData(await _loadDraftForSession(null));
  }
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
