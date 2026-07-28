import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/repositories/app_repositories.dart';
import '../../../shared/models/app_models.dart';

class ActiveWorkoutState {
  const ActiveWorkoutState({
    this.session,
    this.corruptedCheckpointRecovered = false,
  });

  final ActiveWorkoutSession? session;
  final bool corruptedCheckpointRecovered;

  ActiveWorkoutState copyWith({
    Object? session = _activeUnset,
    bool? corruptedCheckpointRecovered,
  }) {
    return ActiveWorkoutState(
      session: identical(session, _activeUnset)
          ? this.session
          : session as ActiveWorkoutSession?,
      corruptedCheckpointRecovered:
          corruptedCheckpointRecovered ?? this.corruptedCheckpointRecovered,
    );
  }
}

const _activeUnset = Object();

final activeWorkoutProvider =
    AsyncNotifierProvider<ActiveWorkoutController, ActiveWorkoutState>(
  ActiveWorkoutController.new,
);

class ActiveWorkoutController extends AsyncNotifier<ActiveWorkoutState> {
  Timer? _checkpointTimer;
  Future<void> _checkpointTail = Future.value();
  Future<WorkoutMutationResult?>? _finishInFlight;
  final Random _random = Random();

  ActiveWorkoutCheckpointStore get _store =>
      ref.read(activeWorkoutCheckpointStoreProvider);

  @override
  Future<ActiveWorkoutState> build() async {
    ref.onDispose(() => _checkpointTimer?.cancel());
    final authSession = ref.watch(authSessionProvider);
    final loaded = await _store.load(authSession);
    return ActiveWorkoutState(
      session: loaded.session,
      corruptedCheckpointRecovered: loaded.corrupted,
    );
  }

  Future<ActiveWorkoutSession> startOrResume(
    WorkoutTemplateDraft template,
  ) async {
    final currentState = state.valueOrNull ?? await future;
    final existing = currentState.session;
    if (existing != null &&
        existing.lifecycle != ActiveWorkoutLifecycle.discarded) {
      return existing;
    }

    final now = DateTime.now();
    final created = ActiveWorkoutSession(
      sessionId:
          'session-${now.microsecondsSinceEpoch}-${_random.nextInt(1 << 20)}',
      sourceTemplateId: template.templateId,
      name: template.name.trim().isEmpty
          ? 'Workout Session'
          : template.name.trim(),
      notes: '',
      exercises: _executionCopy(template.exercises),
      startedAt: now,
      lastCheckpointAt: null,
      revision: 1,
      restDeadline: null,
      localStatus: ActiveWorkoutLocalStatus.dirty,
      remoteStatus: ActiveWorkoutRemoteStatus.localOnly,
      lifecycle: ActiveWorkoutLifecycle.active,
    );
    state = AsyncData(currentState.copyWith(session: created));
    await checkpointNow();
    return state.valueOrNull?.session ?? created;
  }

  void updateNotes(String notes) {
    _mutate((session) => session.copyWith(notes: notes));
  }

  void updateExercise(int index, WorkoutExerciseDraft exercise) {
    _mutate((session) {
      if (index < 0 || index >= session.exercises.length) {
        return session;
      }
      final exercises = [...session.exercises];
      exercises[index] = exercise;
      return session.copyWith(exercises: exercises);
    });
  }

  void updateSet(int exerciseIndex, int setIndex, SetDraft setDraft) {
    _mutate((session) {
      if (exerciseIndex < 0 || exerciseIndex >= session.exercises.length) {
        return session;
      }
      final exercises = [...session.exercises];
      final sets = [...exercises[exerciseIndex].sets];
      if (setIndex < 0 || setIndex >= sets.length) {
        return session;
      }
      sets[setIndex] = setDraft;
      exercises[exerciseIndex] = exercises[exerciseIndex].copyWith(sets: sets);
      return session.copyWith(exercises: exercises);
    });
  }

  void addSet(int exerciseIndex) {
    _mutate((session) {
      if (exerciseIndex < 0 || exerciseIndex >= session.exercises.length) {
        return session;
      }
      final exercises = [...session.exercises];
      final sets = [...exercises[exerciseIndex].sets];
      final previous = sets.isEmpty ? null : sets.last;
      sets.add(
        SetDraft(
          setNumber: sets.length + 1,
          weightKg: previous?.weightKg ?? 0,
          reps: previous?.reps ?? 0,
          isWarmup: false,
          isCompleted: false,
          rpe: previous?.rpe ?? 0,
        ),
      );
      exercises[exerciseIndex] = exercises[exerciseIndex].copyWith(sets: sets);
      return session.copyWith(exercises: exercises);
    });
  }

  void removeSet(int exerciseIndex, int setIndex) {
    _mutate((session) {
      if (exerciseIndex < 0 || exerciseIndex >= session.exercises.length) {
        return session;
      }
      final exercises = [...session.exercises];
      final sets = [...exercises[exerciseIndex].sets];
      if (sets.length <= 1 || setIndex < 0 || setIndex >= sets.length) {
        return session;
      }
      sets.removeAt(setIndex);
      final renumbered = sets
          .asMap()
          .entries
          .map((entry) => entry.value.copyWith(setNumber: entry.key + 1))
          .toList(growable: false);
      exercises[exerciseIndex] =
          exercises[exerciseIndex].copyWith(sets: renumbered);
      return session.copyWith(exercises: exercises);
    });
  }

  void setRestDeadline(DateTime? deadline) {
    _mutate((session) => session.copyWith(restDeadline: deadline));
  }

  Duration restRemaining(DateTime now) {
    final deadline = state.valueOrNull?.session?.restDeadline;
    if (deadline == null || !deadline.isAfter(now)) {
      return Duration.zero;
    }
    return deadline.difference(now);
  }

  void _mutate(
    ActiveWorkoutSession Function(ActiveWorkoutSession session) change,
  ) {
    final currentState = state.valueOrNull;
    final current = currentState?.session;
    if (currentState == null || current == null || !current.isActive) {
      return;
    }
    final changed = change(current);
    if (identical(changed, current)) {
      return;
    }
    state = AsyncData(
      currentState.copyWith(
        session: changed.copyWith(
          revision: current.revision + 1,
          localStatus: ActiveWorkoutLocalStatus.dirty,
        ),
      ),
    );
    _scheduleCheckpoint();
  }

  void _scheduleCheckpoint() {
    _checkpointTimer?.cancel();
    _checkpointTimer = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(checkpointNow()),
    );
  }

  Future<void> checkpointNow() async {
    _checkpointTimer?.cancel();
    final currentState = state.valueOrNull;
    final current = currentState?.session;
    final authSession = ref.read(authSessionProvider);
    if (currentState == null || current == null || authSession == null) {
      return;
    }
    final checkpointed = current.copyWith(
      lastCheckpointAt: DateTime.now(),
      localStatus: ActiveWorkoutLocalStatus.checkpointing,
    );
    state = AsyncData(currentState.copyWith(session: checkpointed));
    final persisted = checkpointed.copyWith(
      localStatus: ActiveWorkoutLocalStatus.checkpointed,
    );
    _checkpointTail = _checkpointTail.then((_) async {
      await _store.write(authSession, persisted);
      final latestState = state.valueOrNull;
      final latest = latestState?.session;
      if (latestState != null &&
          latest != null &&
          latest.sessionId == persisted.sessionId &&
          latest.revision == persisted.revision) {
        state = AsyncData(
          latestState.copyWith(
            session: latest.copyWith(
              lastCheckpointAt: persisted.lastCheckpointAt,
              localStatus: ActiveWorkoutLocalStatus.checkpointed,
            ),
          ),
        );
      }
    });
    await _checkpointTail;
  }

  Future<WorkoutMutationResult?> finish() {
    final inFlight = _finishInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final operation = _finishOnce();
    _finishInFlight = operation;
    return operation.whenComplete(() => _finishInFlight = null);
  }

  Future<WorkoutMutationResult?> _finishOnce() async {
    final currentState = state.valueOrNull ?? await future;
    final current = currentState.session;
    if (current == null ||
        current.lifecycle == ActiveWorkoutLifecycle.discarded) {
      return null;
    }
    final finishing = current.copyWith(
      lifecycle: ActiveWorkoutLifecycle.finishing,
      remoteStatus: ActiveWorkoutRemoteStatus.pendingSync,
      revision: current.revision + 1,
      localStatus: ActiveWorkoutLocalStatus.dirty,
    );
    state = AsyncData(currentState.copyWith(session: finishing));
    await checkpointNow();

    final result =
        await ref.read(appDraftProvider.notifier).finishActiveWorkout(
              finishing,
            );
    if (result.syncStatus == WorkoutSyncStatus.synced) {
      await _store.clear(ref.read(authSessionProvider));
      state = AsyncData(currentState.copyWith(session: null));
      return result;
    }

    final preserved = finishing.copyWith(
      remoteStatus: result.syncStatus == WorkoutSyncStatus.pendingSync
          ? ActiveWorkoutRemoteStatus.pendingSync
          : ActiveWorkoutRemoteStatus.failed,
      localStatus: ActiveWorkoutLocalStatus.dirty,
    );
    state = AsyncData(currentState.copyWith(session: preserved));
    await checkpointNow();
    return result;
  }

  Future<void> discard() async {
    _checkpointTimer?.cancel();
    final currentState = state.valueOrNull ?? await future;
    final current = currentState.session;
    if (current == null) {
      return;
    }
    state = AsyncData(
      currentState.copyWith(
        session: current.copyWith(
          lifecycle: ActiveWorkoutLifecycle.discarded,
          revision: current.revision + 1,
        ),
      ),
    );
    await _store.clear(ref.read(authSessionProvider));
    state = AsyncData(currentState.copyWith(session: null));
  }
}

List<WorkoutExerciseDraft> _executionCopy(
  List<WorkoutExerciseDraft> exercises,
) {
  return exercises
      .map(
        (exercise) => exercise.copyWith(
          sets: exercise.sets
              .map((set) => set.copyWith(isCompleted: false))
              .toList(growable: false),
        ),
      )
      .toList(growable: false);
}
