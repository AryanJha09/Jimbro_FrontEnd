import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/notifications/workout_notification_service.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('workout log preserves full name notes exercises and sets', () async {
    final workoutRepository = _CapturingWorkoutRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_ReadyAuthRepository()),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
        workoutRepositoryProvider.overrideWithValue(workoutRepository),
        nutritionRepositoryProvider
            .overrideWithValue(MockNutritionRepository()),
        consistencyRepositoryProvider.overrideWithValue(
          MockConsistencyRepository(),
        ),
        atlasRepositoryProvider.overrideWithValue(MockAtlasRepository()),
        searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(appDraftProvider.future);
    final controller = container.read(appDraftProvider.notifier);

    for (final typedName in ['P', 'Pu', 'Pus', 'Push']) {
      final current = container.read(appDraftProvider).value!;
      await controller.updateTemplate(
        current.template.copyWith(name: typedName),
      );
    }
    await controller.updateWorkoutNotes('Moved well. Add 2.5 kg next time.');
    await controller.addExercise();

    var current = container.read(appDraftProvider).value!;
    await controller.updateExercise(
      0,
      current.template.exercises[0].copyWith(
        exerciseId: 111,
        exerciseName: 'Bench Press (Barbell)',
        notes: 'Keep the first reps smooth.',
      ),
    );

    current = container.read(appDraftProvider).value!;
    await controller.updateSet(
      0,
      0,
      current.template.exercises[0].sets[0].copyWith(
        setNumber: 1,
        reps: 8,
        weightKg: 60,
        rpe: 7,
      ),
    );

    await controller.logWorkoutSession();

    final captured = workoutRepository.capturedLog!;
    expect(captured.name, 'Push');
    expect(captured.notes, 'Moved well. Add 2.5 kg next time.');
    expect(captured.startedAtLabel, isNotEmpty);
    expect(captured.endedAtLabel, isNotEmpty);
    expect(captured.exercises, hasLength(1));
    expect(captured.exercises.single.exerciseName, 'Bench Press (Barbell)');
    expect(captured.exercises.single.notes, 'Keep the first reps smooth.');
    expect(captured.exercises.single.sets, hasLength(1));
    expect(captured.exercises.single.sets.single.reps, 8);
    expect(captured.exercises.single.sets.single.weightKg, 60);
    expect(captured.exercises.single.sets.single.rpe, 7);
  });

  test('workout log repository posts backend-aligned payload', () async {
    final adapter = _CapturingDioAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    await repository.saveWorkoutLog(
      _ReadyAuthRepository._session,
      const WorkoutLogDraft(
        templateId: 20,
        name: 'Push',
        notes: 'Moved well. Add 2.5 kg next time.',
        startedAtLabel: '2026-06-06T10:00:00.000',
        endedAtLabel: '2026-06-06T10:42:00.000',
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 111,
            exerciseName: 'Bench Press (Barbell)',
            notes: 'Keep the first reps smooth.',
            targetSets: 1,
            targetReps: 8,
            sets: [
              SetDraft(
                setNumber: 1,
                weightKg: 60,
                reps: 8,
                isWarmup: false,
                isCompleted: false,
                rpe: 7,
              ),
            ],
          ),
        ],
      ),
    );

    final payload = adapter.lastPostPayload!;
    expect(payload['name'], 'Push');
    expect(payload['template_id'], 20);
    expect(payload['notes'], 'Moved well. Add 2.5 kg next time.');
    expect(payload['started_at'], '2026-06-06T10:00:00.000');
    expect(payload['ended_at'], '2026-06-06T10:42:00.000');
    expect(payload['duration_minutes'], 42);
    expect(payload, contains('exercises'));
    expect(payload, contains('workout_exercises'));

    final exercises = payload['workout_exercises'] as List<dynamic>;
    expect(exercises, hasLength(1));
    expect(exercises.single['exercise_id'], 111);
    expect(exercises.single['order_index'], 1);
    expect(exercises.single['notes'], 'Keep the first reps smooth.');

    final sets = exercises.single['sets'] as List<dynamic>;
    expect(sets, hasLength(1));
    expect(sets.single['set_number'], 1);
    expect(sets.single['reps'], 8);
    expect(sets.single['weight_kg'], 60);
    expect(sets.single['rpe'], 7);
  });

  test('workout log documented mapper emits minimal backend shape', () {
    final payload = workoutLogDocumentedPayload(
      const WorkoutLogDraft(
        templateId: 20,
        name: 'Push',
        notes: 'Moved well.',
        startedAtLabel: '2026-06-06T10:00:00.000',
        endedAtLabel: '2026-06-06T10:42:00.000',
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 111,
            exerciseName: 'Bench Press (Barbell)',
            notes: 'Keep the first reps smooth.',
            targetSets: 1,
            targetReps: 8,
            sets: [
              SetDraft(
                setNumber: 1,
                weightKg: 60,
                reps: 8,
                isWarmup: false,
                isCompleted: true,
                rpe: 7,
              ),
            ],
          ),
        ],
      ),
      const [
        WorkoutExerciseDraft(
          exerciseId: 111,
          exerciseName: 'Bench Press (Barbell)',
          notes: 'Keep the first reps smooth.',
          targetSets: 1,
          targetReps: 8,
          sets: [
            SetDraft(
              setNumber: 1,
              weightKg: 60,
              reps: 8,
              isWarmup: false,
              isCompleted: true,
              rpe: 7,
            ),
          ],
        ),
      ],
    );

    expect(payload.keys, containsAll(['workout_name', 'date', 'duration_min']));
    expect(payload['workout_name'], 'Push');
    expect(payload['date'], '2026-06-06');
    expect(payload['duration_min'], 42);
    expect(payload, isNot(contains('workout_exercises')));

    final exercises = payload['exercises'] as Iterable<dynamic>;
    final sets =
        (exercises.single as Map<String, dynamic>)['sets'] as Iterable<dynamic>;
    expect(sets.single, {
      'set_number': 1,
      'reps': 8,
      'weight_kg': 60.0,
      'is_warmup': false,
    });
  });

  test('workout log mapper rejects exercises without nested sets', () {
    expect(
      () => workoutLogRichPayload(
        const WorkoutLogDraft(
          name: 'Push',
          notes: '',
          startedAtLabel: '2026-06-06T10:00:00.000',
          endedAtLabel: '2026-06-06T10:42:00.000',
          exercises: [
            WorkoutExerciseDraft(
              exerciseId: 111,
              exerciseName: 'Bench Press',
              notes: '',
              targetSets: 1,
              targetReps: 8,
              sets: [],
            ),
          ],
        ),
        const [
          WorkoutExerciseDraft(
            exerciseId: 111,
            exerciseName: 'Bench Press',
            notes: '',
            targetSets: 1,
            targetReps: 8,
            sets: [],
          ),
        ],
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('has no sets'),
        ),
      ),
    );
  });

  test('workout log repository retries documented payload on 422', () async {
    final adapter = _CapturingDioAdapter()..rejectRichWorkoutLogOnce = true;
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    await repository.saveWorkoutLog(
      _ReadyAuthRepository._session,
      const WorkoutLogDraft(
        name: 'Push',
        notes: '',
        startedAtLabel: '2026-06-06T10:00:00.000',
        endedAtLabel: '2026-06-06T10:42:00.000',
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 111,
            exerciseName: 'Bench Press (Barbell)',
            notes: '',
            targetSets: 1,
            targetReps: 8,
            sets: [
              SetDraft(
                setNumber: 1,
                weightKg: 60,
                reps: 8,
                isWarmup: false,
                isCompleted: true,
                rpe: 7,
              ),
            ],
          ),
        ],
      ),
    );

    expect(adapter.workoutLogPayloads, hasLength(2));
    expect(adapter.workoutLogPayloads.first, contains('workout_exercises'));
    expect(adapter.workoutLogPayloads.last, contains('workout_name'));
    expect(
        adapter.workoutLogPayloads.last, isNot(contains('workout_exercises')));
  });

  test('workout log repository surfaces FastAPI 422 validation detail',
      () async {
    final adapter = _CapturingDioAdapter()
      ..validationError = {
        'detail': [
          {
            'loc': ['body', 'workout_exercises'],
            'msg': 'Field required',
            'type': 'missing',
          },
        ],
      };
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    expect(
      () => repository.saveWorkoutLog(
        _ReadyAuthRepository._session,
        const WorkoutLogDraft(
          name: 'Push',
          notes: '',
          startedAtLabel: '',
          exercises: [
            WorkoutExerciseDraft(
              exerciseId: 111,
              exerciseName: 'Bench Press (Barbell)',
              notes: '',
              targetSets: 1,
              targetReps: 8,
              sets: [
                SetDraft(
                  setNumber: 1,
                  weightKg: 60,
                  reps: 8,
                  isWarmup: false,
                  isCompleted: false,
                  rpe: 7,
                ),
              ],
            ),
          ],
        ),
      ),
      throwsA(
        isA<Exception>()
            .having(
              (error) => error.toString(),
              'message',
              contains(
                'loc=body.workout_exercises msg=Field required type=missing',
              ),
            )
            .having(
              (error) => error.toString(),
              'payload',
              contains('duration_min'),
            ),
      ),
    );
  });

  test('template created saved visible opened and starts workout', () async {
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
      ],
    );
    addTearDown(container.dispose);

    await container.read(appDraftProvider.future);
    final controller = container.read(appDraftProvider.notifier);

    await controller.createTemplateDraft();
    var current = container.read(appDraftProvider).value!;
    await controller.updateTemplate(
      current.template.copyWith(
        name: 'Push Strength',
        description: 'Upper body repeatable plan',
      ),
    );
    await controller.addExercise();

    current = container.read(appDraftProvider).value!;
    await controller.updateExercise(
      0,
      current.template.exercises[0].copyWith(
        exerciseId: 111,
        exerciseName: 'Bench Press (Barbell)',
        targetSets: 3,
        targetReps: 8,
      ),
    );

    current = container.read(appDraftProvider).value!;
    await controller.updateSet(
      0,
      0,
      current.template.exercises[0].sets[0].copyWith(
        reps: 8,
        weightKg: 60,
        rpe: 7,
      ),
    );

    final saved = await controller.saveWorkoutTemplate();
    current = container.read(appDraftProvider).value!;
    expect(current.templates, hasLength(1));
    expect(current.templates.single.name, 'Push Strength');

    await controller.createTemplateDraft();
    current = container.read(appDraftProvider).value!;
    expect(current.template.name, isEmpty);

    await controller.openWorkoutTemplate(saved);
    current = container.read(appDraftProvider).value!;
    expect(current.template.name, 'Push Strength');
    expect(current.template.exercises.single.sets.single.reps, 8);

    await controller.startWorkoutFromTemplate(saved);
    current = container.read(appDraftProvider).value!;
    expect(current.workoutLog.templateId, saved.templateId);
    expect(current.workoutLog.name, 'Push Strength');
    expect(current.workoutLog.startedAtLabel, isNotEmpty);
    expect(current.workoutLog.exercises.single.exerciseName,
        'Bench Press (Barbell)');
  });

  test('started workout can edit sets and finish without mutating template',
      () async {
    final workoutRepository = _CapturingWorkoutRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_ReadyAuthRepository()),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
        workoutRepositoryProvider.overrideWithValue(workoutRepository),
        nutritionRepositoryProvider
            .overrideWithValue(MockNutritionRepository()),
        consistencyRepositoryProvider.overrideWithValue(
          MockConsistencyRepository(),
        ),
        atlasRepositoryProvider.overrideWithValue(MockAtlasRepository()),
        searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(appDraftProvider.future);
    final controller = container.read(appDraftProvider.notifier);

    await controller.updateTemplate(
      const WorkoutTemplateDraft(
        name: 'Push Strength Full Name',
        description: 'Upper body repeatable plan',
        durationMinutes: 0,
        goal: '',
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 111,
            exerciseName: 'Bench Press (Barbell)',
            notes: 'Smooth reps.',
            targetSets: 2,
            targetReps: 8,
            sets: [
              SetDraft(
                setNumber: 1,
                weightKg: 60,
                reps: 8,
                isWarmup: false,
                isCompleted: false,
                rpe: 7,
              ),
            ],
          ),
        ],
      ),
    );
    final saved = await controller.saveWorkoutTemplate();
    await controller.startWorkoutFromTemplate(saved);

    var current = container.read(appDraftProvider).value!;
    expect(current.workoutLog.exercises.single.sets.single.reps, 8);

    await controller.updateWorkoutSet(
      0,
      0,
      current.workoutLog.exercises[0].sets[0].copyWith(
        reps: 9,
        weightKg: 62.5,
        rpe: 8,
      ),
    );
    await controller.addWorkoutSet(0);

    current = container.read(appDraftProvider).value!;
    await controller.updateWorkoutSet(
      0,
      1,
      current.workoutLog.exercises[0].sets[1].copyWith(
        reps: 7,
        weightKg: 65,
        rpe: 8.5,
      ),
    );
    await controller.removeWorkoutSet(0, 0);
    await controller.updateWorkoutNotes('Finished strong.');
    await controller.logWorkoutSession();

    final captured = workoutRepository.capturedLog!;
    expect(captured.name, 'Push Strength Full Name');
    expect(captured.name, isNot(contains('...')));
    expect(captured.templateId, saved.templateId);
    expect(captured.notes, 'Finished strong.');
    expect(captured.startedAtLabel, isNotEmpty);
    expect(captured.endedAtLabel, isNotEmpty);
    expect(captured.exercises, hasLength(1));
    expect(captured.exercises.single.exerciseName, 'Bench Press (Barbell)');
    expect(captured.exercises.single.sets, hasLength(1));
    expect(captured.exercises.single.sets.single.setNumber, 1);
    expect(captured.exercises.single.sets.single.reps, 7);
    expect(captured.exercises.single.sets.single.weightKg, 65);
    expect(captured.exercises.single.sets.single.rpe, 8.5);

    current = container.read(appDraftProvider).value!;
    expect(current.templates.single.exercises.single.sets.single.reps, 8);
    expect(current.templates.single.exercises.single.sets.single.weightKg, 60);
  });

  test('template scheduled for Monday can start scheduled workout', () async {
    final notificationService = _FakeWorkoutNotificationService();
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
        workoutNotificationServiceProvider
            .overrideWithValue(notificationService),
      ],
    );
    addTearDown(container.dispose);

    await container.read(appDraftProvider.future);
    final controller = container.read(appDraftProvider.notifier);

    await controller.updateTemplate(
      const WorkoutTemplateDraft(
        name: 'Monday Push',
        description: '',
        durationMinutes: 0,
        goal: '',
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 111,
            exerciseName: 'Bench Press (Barbell)',
            notes: '',
            targetSets: 3,
            targetReps: 8,
            sets: [
              SetDraft(
                setNumber: 1,
                weightKg: 60,
                reps: 8,
                isWarmup: false,
                isCompleted: false,
                rpe: 7,
              ),
            ],
          ),
        ],
      ),
    );
    final saved = await controller.saveWorkoutTemplate();

    final result = await controller.scheduleWorkoutTemplate(
      saved,
      weekday: DateTime.monday,
      timeLabel: '07:30',
    );

    var current = container.read(appDraftProvider).value!;
    expect(current.workoutSchedule, hasLength(1));
    expect(current.workoutSchedule.single.weekday, DateTime.monday);
    expect(current.workoutSchedule.single.timeLabel, '07:30');
    expect(result.notification.status, WorkoutReminderStatus.scheduled);
    expect(notificationService.scheduledEntry?.templateName, 'Monday Push');

    await controller.startScheduledWorkout(current.workoutSchedule.single);
    current = container.read(appDraftProvider).value!;
    expect(current.workoutLog.templateId, saved.templateId);
    expect(current.workoutLog.name, 'Monday Push');
    expect(current.workoutLog.startedAtLabel, isNotEmpty);
  });

  test('schedule 404 marks backend unsupported and saves locally', () async {
    SharedPreferences.setMockInitialValues({});
    final adapter = _ScheduleUnsupportedDioAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    final first = await repository.saveScheduleEntry(
      _ReadyAuthRepository._session,
      const WorkoutScheduleEntry(
        templateId: 7,
        templateName: 'Monday Push',
        weekday: DateTime.monday,
        timeLabel: '07:30',
      ),
    );
    final second = await repository.saveScheduleEntry(
      _ReadyAuthRepository._session,
      first.copyWith(timeLabel: '08:00'),
    );
    final loaded = await repository.loadSchedule(_ReadyAuthRepository._session);

    expect(adapter.scheduleCalls, 1);
    expect(second.scheduleId, startsWith('local-'));
    expect(loaded, hasLength(1));
    expect(loaded.single.timeLabel, '08:00');
  });

  test('workout log queues on connection error and flushes later', () async {
    SharedPreferences.setMockInitialValues({});
    final adapter = _WorkoutLogOfflineDioAdapter()..offline = true;
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    const outbox = OfflineOutboxStore();
    final repository = FastApiWorkoutRepository(dio, outbox: outbox);

    final local = await repository.saveWorkoutLog(
      _ReadyAuthRepository._session,
      const WorkoutLogDraft(
        name: 'Offline Push',
        notes: '',
        startedAtLabel: '2026-06-14T10:00:00.000',
        endedAtLabel: '2026-06-14T10:30:00.000',
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 111,
            exerciseName: 'Bench Press',
            notes: '',
            targetSets: 1,
            targetReps: 8,
            sets: [
              SetDraft(
                setNumber: 1,
                weightKg: 60,
                reps: 8,
                isWarmup: false,
                isCompleted: true,
                rpe: 7,
              ),
            ],
          ),
        ],
      ),
    );

    expect(local.name, 'Offline Push');
    expect(await outbox.load(_ReadyAuthRepository._session), hasLength(1));

    adapter.offline = false;
    await repository.flushPending(_ReadyAuthRepository._session);

    expect(adapter.workoutLogPayloads, isNotEmpty);
    expect(await outbox.load(_ReadyAuthRepository._session), isEmpty);
  });

  test('workout template repository posts planned fields', () async {
    final adapter = _CapturingDioAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    await repository.saveTemplate(
      _ReadyAuthRepository._session,
      const WorkoutTemplateDraft(
        name: 'Push Strength',
        description: 'Upper body repeatable plan',
        durationMinutes: 0,
        goal: '',
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 111,
            exerciseName: 'Bench Press (Barbell)',
            notes: 'Smooth reps.',
            targetSets: 3,
            targetReps: 8,
            sets: [
              SetDraft(
                setNumber: 1,
                weightKg: 60,
                reps: 8,
                isWarmup: false,
                isCompleted: false,
                rpe: 7,
              ),
            ],
          ),
        ],
      ),
    );

    final payload = adapter.lastTemplatePayload!;
    expect(payload['name'], 'Push Strength');
    expect(payload['description'], 'Upper body repeatable plan');

    final exercises = payload['exercises'] as List<dynamic>;
    expect(exercises.single['exercise_id'], 111);
    expect(exercises.single['order_index'], 1);
    expect(exercises.single['target_sets'], 3);
    expect(exercises.single['target_reps'], 8);
    expect(exercises.single['notes'], 'Smooth reps.');

    final sets = exercises.single['sets'] as List<dynamic>;
    expect(sets.single['set_number'], 1);
    expect(sets.single['reps'], 8);
    expect(sets.single['weight_kg'], 60);
    expect(sets.single['rpe'], 7);
  });

  test('workout template documented mapper emits days shape', () {
    final payload = workoutTemplateDocumentedPayload(
      const WorkoutTemplateDraft(
        name: 'Push Strength',
        description: 'Upper body repeatable plan',
        durationMinutes: 0,
        goal: '',
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 111,
            exerciseName: 'Bench Press (Barbell)',
            notes: 'Smooth reps.',
            targetSets: 3,
            targetReps: 8,
            sets: [],
          ),
        ],
      ),
      const [
        WorkoutExerciseDraft(
          exerciseId: 111,
          exerciseName: 'Bench Press (Barbell)',
          notes: 'Smooth reps.',
          targetSets: 3,
          targetReps: 8,
          sets: [],
        ),
      ],
    );

    expect(payload['name'], 'Push Strength');
    final days = payload['days'] as Iterable<dynamic>;
    final day = days.single as Map<String, dynamic>;
    expect(day['day_label'], 'Day 1');
    final exercises = day['exercises'] as Iterable<dynamic>;
    expect(exercises.single, {
      'exercise_id': 111,
      'sets': 3,
      'reps': 8,
      'notes': 'Smooth reps.',
    });
  });

  test('workout template repository retries documented payload on 422',
      () async {
    final adapter = _CapturingDioAdapter()..rejectRichTemplateOnce = true;
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    final saved = await repository.saveTemplate(
      _ReadyAuthRepository._session,
      const WorkoutTemplateDraft(
        name: 'Push Strength',
        description: 'Upper body repeatable plan',
        durationMinutes: 0,
        goal: '',
        exercises: [
          WorkoutExerciseDraft(
            exerciseId: 111,
            exerciseName: 'Bench Press (Barbell)',
            notes: 'Smooth reps.',
            targetSets: 3,
            targetReps: 8,
            sets: [],
          ),
        ],
      ),
    );

    expect(saved.name, 'Push Strength');
    expect(adapter.templatePayloads, hasLength(2));
    expect(adapter.templatePayloads.first, contains('exercises'));
    expect(adapter.templatePayloads.last, contains('days'));
    final days = adapter.templatePayloads.last['days'] as Iterable<dynamic>;
    final exercises =
        (days.single as Map<String, dynamic>)['exercises'] as Iterable<dynamic>;
    expect((exercises.single as Map<String, dynamic>)['sets'], 3);
  });
}

class _ReadyAuthRepository implements AuthRepository {
  static const _session = AuthSession(
    userId: 'test-user',
    displayName: 'Test User',
    email: 'test@example.com',
    accessToken: 'test-token',
    provider: 'test',
  );

  @override
  Future<AuthSession?> currentSession() async => _session;

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return _session;
  }

  @override
  Future<AuthSession> signInWithMockProvider(String provider) async {
    return _session;
  }

  @override
  Future<void> signOut() async {}
}

class _CapturingWorkoutRepository implements WorkoutRepository {
  WorkoutLogDraft? capturedLog;

  @override
  Future<List<WorkoutTemplateDraft>> loadTemplates(AuthSession? session) async {
    return const [];
  }

  @override
  Future<WorkoutLogDraft> loadWorkoutLog(AuthSession? session) async {
    return WorkoutLogDraft.empty;
  }

  @override
  Future<WorkoutTemplateDraft> loadTemplate(AuthSession? session) async {
    return WorkoutTemplateDraft.empty;
  }

  @override
  Future<List<WorkoutScheduleEntry>> loadSchedule(AuthSession? session) async {
    return const [];
  }

  @override
  Future<WorkoutLogDraft> saveWorkoutLog(
    AuthSession? session,
    WorkoutLogDraft log,
  ) async {
    capturedLog = log;
    return log.copyWith(workoutLogId: 1);
  }

  @override
  Future<WorkoutTemplateDraft> saveTemplate(
    AuthSession? session,
    WorkoutTemplateDraft template,
  ) async {
    return template.copyWith(templateId: 1);
  }

  @override
  Future<void> deleteTemplate(AuthSession? session, int templateId) async {}

  @override
  Future<WorkoutScheduleEntry> saveScheduleEntry(
    AuthSession? session,
    WorkoutScheduleEntry entry,
  ) async {
    return entry.copyWith(scheduleId: 'test-schedule');
  }

  @override
  Future<void> deleteScheduleEntry(
    AuthSession? session,
    WorkoutScheduleEntry entry,
  ) async {}

  @override
  Future<List<ExerciseSuggestion>> searchExercises(String query) async {
    return const [];
  }

  @override
  Future<void> flushPending(AuthSession? session) async {}
}

class _FakeWorkoutNotificationService implements WorkoutNotificationService {
  WorkoutScheduleEntry? scheduledEntry;
  WorkoutScheduleEntry? cancelledEntry;

  @override
  Future<WorkoutReminderResult> scheduleWeeklyReminder(
    WorkoutScheduleEntry entry,
  ) async {
    scheduledEntry = entry;
    return const WorkoutReminderResult(
      status: WorkoutReminderStatus.scheduled,
      message: 'Weekly reminder set.',
    );
  }

  @override
  Future<void> cancelReminder(WorkoutScheduleEntry entry) async {
    cancelledEntry = entry;
  }
}

class _CapturingDioAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastPostPayload;
  Map<String, dynamic>? lastTemplatePayload;
  Map<String, dynamic>? validationError;
  bool rejectRichTemplateOnce = false;
  bool rejectRichWorkoutLogOnce = false;
  final List<Map<String, dynamic>> templatePayloads = [];
  final List<Map<String, dynamic>> workoutLogPayloads = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST' && options.path == '/workout-templates') {
      lastTemplatePayload = Map<String, dynamic>.from(options.data as Map);
      templatePayloads.add(lastTemplatePayload!);
      if (rejectRichTemplateOnce &&
          templatePayloads.length == 1 &&
          lastTemplatePayload!.containsKey('exercises')) {
        return ResponseBody.fromString(
          jsonEncode({
            'detail': [
              {
                'loc': ['body', 'days'],
                'msg': 'Field required',
                'type': 'missing',
              },
            ],
          }),
          422,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'data': {
            'template_id': 20,
            ...lastTemplatePayload!,
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'POST' && options.path == '/workout-logs') {
      lastPostPayload = Map<String, dynamic>.from(options.data as Map);
      workoutLogPayloads.add(lastPostPayload!);
      if (rejectRichWorkoutLogOnce &&
          workoutLogPayloads.length == 1 &&
          lastPostPayload!.containsKey('workout_exercises')) {
        return ResponseBody.fromString(
          jsonEncode({
            'detail': [
              {
                'loc': ['body', 'workout_name'],
                'msg': 'Field required',
                'type': 'missing',
              },
            ],
          }),
          422,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      final error = validationError;
      if (error != null) {
        return ResponseBody.fromString(
          jsonEncode(error),
          422,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'data': {
            'workout_log_id': 10,
            ...lastPostPayload!,
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{"success":true,"data":[]}', 200);
  }
}

class _ScheduleUnsupportedDioAdapter implements HttpClientAdapter {
  int scheduleCalls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.startsWith('/workout-schedule')) {
      scheduleCalls += 1;
      return ResponseBody.fromString(
        '{"detail":"not found"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{"success":true,"data":[]}', 200);
  }
}

class _WorkoutLogOfflineDioAdapter implements HttpClientAdapter {
  bool offline = false;
  final workoutLogPayloads = <Map<String, dynamic>>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST' && options.path == '/workout-logs') {
      if (offline) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'offline',
        );
      }
      workoutLogPayloads.add(Map<String, dynamic>.from(options.data as Map));
      return ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'data': {
            'workout_log_id': 99,
            ...workoutLogPayloads.last,
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{"success":true,"data":[]}', 200);
  }
}
