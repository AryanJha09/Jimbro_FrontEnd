import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jimbro/core/errors/app_error.dart';
import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/notifications/workout_notification_service.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/features/workouts/application/active_workout_controller.dart';
import 'package:jimbro/shared/models/app_models.dart';

const _searchSession = AuthSession(
  userId: 'search-user',
  displayName: 'Search User',
  email: 'search@example.com',
  accessToken: 'search-token',
  provider: 'test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

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

    final result = await repository.saveWorkoutLog(
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
    expect(payload, contains('exercises'));
    expect(result.syncStatus, WorkoutSyncStatus.synced);
    expect(result.serverLogId, 10);
    expect(result.authoritativeWorkout?.workoutLogId, 10);
    expect(payload, isNot(contains('workout_exercises')));
    expect(payload, isNot(contains('started_at')));
    expect(payload, isNot(contains('duration_minutes')));

    final exercises = payload['exercises'] as List<dynamic>;
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

    expect(payload.keys, containsAll(['name', 'template_id', 'exercises']));
    expect(payload['name'], 'Push');
    expect(payload['template_id'], 20);
    expect(payload, isNot(contains('workout_exercises')));

    final exercises = payload['exercises'] as Iterable<dynamic>;
    final sets =
        (exercises.single as Map<String, dynamic>)['sets'] as Iterable<dynamic>;
    expect(sets.single, {
      'set_number': 1,
      'reps': 8,
      'weight_kg': 60.0,
      'is_warmup': false,
      'rpe': 7.0,
    });
  });

  test('workout log PATCH contains metadata only', () {
    final payload = workoutLogMetadataPatchPayload(
      const WorkoutLogDraft(
        workoutLogId: 10,
        name: 'Updated Push',
        notes: 'Keep one rep in reserve.',
        startedAtLabel: '',
        endedAtLabel: '',
        exercises: [],
      ),
    );

    expect(payload, {
      'name': 'Updated Push',
      'notes': 'Keep one rep in reserve.',
    });
  });

  test('exercise search uses the documented query-only endpoint', () async {
    final adapter = _ExerciseSearchDioAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    final results = await repository.searchExercises('bench');

    expect(results.single.name, 'Bench Press');
    expect(adapter.queryParameters, [
      {'q': 'bench'}
    ]);
  });

  test('short exercise query is sent as prefix suggestion query', () async {
    final adapter = _ExerciseSearchDioAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    final suggestions = await repository.searchExercises('b');

    expect(suggestions.single.name, 'Bench Press');
    expect(adapter.queryParameters.single['q'], 'b');
    expect(adapter.queryParameters.single.containsKey('limit'), isFalse);
  });

  test('exercise search caches normalized repeated queries', () async {
    final adapter = _ExerciseSearchDioAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    await repository.searchExercises(' Bench ');
    await repository.searchExercises('bench');

    expect(adapter.queryParameters, hasLength(1));
    expect(adapter.queryParameters.single['q'], 'bench');
  });

  test(
      'exercise search trims, normalizes, authenticates and preserves partials',
      () async {
    final adapter = _ExerciseSearchDioAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    expect(await repository.searchExercises('   ', _searchSession), isEmpty);
    await repository.searchExercises(' BÉNCH & press ', _searchSession);

    expect(adapter.queryParameters.single, {'q': 'bénch & press'});
    expect(adapter.headers.single['Authorization'], 'Bearer search-token');
  });

  test('exercise search distinguishes empty, malformed and HTTP failures',
      () async {
    final adapter = _ExerciseSearchDioAdapter()..empty = true;
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(
      dio,
      searchCacheTtl: Duration.zero,
    );

    expect(await repository.searchExercises('none', _searchSession), isEmpty);
    adapter
      ..empty = false
      ..malformed = true;
    await expectLater(
      repository.searchExercises('bad', _searchSession),
      throwsA(isA<AppError>().having(
        (error) => error.code,
        'code',
        AppErrorCode.malformedResponse,
      )),
    );

    adapter
      ..malformed = false
      ..statusCode = 401;
    await expectLater(
      repository.searchExercises('private', _searchSession),
      throwsA(isA<AppError>().having(
        (error) => error.code,
        'code',
        AppErrorCode.sessionExpired,
      )),
    );
    adapter.statusCode = 422;
    await expectLater(
      repository.searchExercises('invalid', _searchSession),
      throwsA(isA<AppError>().having(
        (error) => error.code,
        'code',
        AppErrorCode.validationFailed,
      )),
    );
    adapter.statusCode = 500;
    await expectLater(
      repository.searchExercises('server', _searchSession),
      throwsA(isA<AppError>().having(
        (error) => error.code,
        'code',
        AppErrorCode.serverUnavailable,
      )),
    );
  });

  test('exercise search exposes cached offline results and timeout', () async {
    final adapter = _ExerciseSearchDioAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(
      dio,
      searchCacheTtl: Duration.zero,
    );

    await repository.searchExercises('bench', _searchSession);
    adapter.offline = true;
    await expectLater(
      repository.searchExercises('bench', _searchSession),
      throwsA(
        isA<CachedSearchResultsException<ExerciseSuggestion>>().having(
          (error) => error.results.single.name,
          'cached result',
          'Bench Press',
        ),
      ),
    );

    adapter
      ..offline = false
      ..timeout = true;
    await expectLater(
      repository.searchExercises('timeout', _searchSession),
      throwsA(isA<AppError>().having(
        (error) => error.code,
        'code',
        AppErrorCode.requestTimeout,
      )),
    );
  });

  test('search request generations ignore stale and cleared responses', () {
    final gate = SearchRequestGate();
    final older = gate.begin('bench');
    final newer = gate.begin('squat');

    expect(gate.isCurrent(older, 'bench'), isFalse);
    expect(gate.isCurrent(newer, 'squat'), isTrue);

    gate.clear();
    expect(gate.isCurrent(newer, 'squat'), isFalse);
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

  test('workout log does not duplicate a rejected documented submit', () async {
    final adapter = _CapturingDioAdapter()..rejectRichWorkoutLogOnce = true;
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    final rejected = await repository.saveWorkoutLog(
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

    expect(rejected.syncStatus, WorkoutSyncStatus.needsReview);
    expect(adapter.workoutLogPayloads, hasLength(1));
    expect(adapter.workoutLogPayloads.single, contains('exercises'));
  });

  test('workout log repository redacts FastAPI 422 validation detail',
      () async {
    final adapter = _CapturingDioAdapter()
      ..validationError = {
        'detail': [
          {
            'loc': ['body', 'exercises'],
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

    final rejected = await repository.saveWorkoutLog(
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
    );
    expect(rejected.syncStatus, WorkoutSyncStatus.needsReview);
    expect(rejected.errorCode, AppErrorCode.validationFailed);
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

  test('schedule is device-local and never probes unsupported endpoints',
      () async {
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

    expect(adapter.scheduleCalls, 0);
    expect(second.scheduleId, startsWith('local-'));
    expect(loaded, hasLength(1));
    expect(loaded.single.timeLabel, '08:00');
  });

  test('device-local schedule survives restart and isolates users', () async {
    SharedPreferences.setMockInitialValues({});
    const store = LocalWorkoutScheduleStore();
    await store.save(
      _ReadyAuthRepository._session,
      const WorkoutScheduleEntry(
        templateId: 7,
        templateName: 'Monday Push',
        weekday: DateTime.monday,
        timeLabel: '07:30',
      ),
    );
    const otherUser = AuthSession(
      userId: 'other-user',
      displayName: 'Other User',
      email: 'other@example.test',
      accessToken: 'other-token',
      provider: 'test',
    );

    expect(
        await const LocalWorkoutScheduleStore()
            .load(_ReadyAuthRepository._session),
        hasLength(1));
    expect(await const LocalWorkoutScheduleStore().load(otherUser), isEmpty);
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

    expect(local.syncStatus, WorkoutSyncStatus.pendingSync);
    expect(local.authoritativeWorkout?.name, 'Offline Push');
    final queued = await outbox.load(_ReadyAuthRepository._session);
    expect(queued, hasLength(1));
    final restored = await repository
        .loadPendingWorkoutMutation(_ReadyAuthRepository._session);
    expect(restored?.syncStatus, WorkoutSyncStatus.pendingSync);
    expect(restored?.mutationId, queued.single.localId);
    expect(restored?.authoritativeWorkout?.name, 'Offline Push');

    adapter.offline = false;
    await repository.flushPending(_ReadyAuthRepository._session);

    expect(adapter.workoutLogPayloads, isNotEmpty);
    expect(
      adapter.workoutLogPayloads
          .map((payload) => payload['client_mutation_id'])
          .toSet(),
      {queued.single.localId},
    );
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
    expect(exercises.single['notes'], 'Smooth reps.');
    expect(exercises.single, isNot(contains('target_sets')));
    expect(exercises.single, isNot(contains('target_reps')));
    expect(exercises.single, isNot(contains('sets')));
  });

  test('workout template documented mapper excludes performance data', () {
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
    final exercises = payload['exercises'] as Iterable<dynamic>;
    expect(exercises.single, {
      'exercise_id': 111,
      'order_index': 1,
      'notes': 'Smooth reps.',
    });
  });

  test('workout template submits the documented shape once', () async {
    final adapter = _CapturingDioAdapter();
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
    expect(adapter.templatePayloads, hasLength(1));
    expect(adapter.templatePayloads.single, contains('exercises'));
    expect(adapter.templatePayloads.single, isNot(contains('days')));
    expect(adapter.templateIdempotencyKeys.single, startsWith('template-'));
  });

  test('template create rejects a success body without a stable id', () async {
    final adapter = _CapturingDioAdapter()..omitTemplateId = true;
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    await expectLater(
      repository.saveTemplate(
        _ReadyAuthRepository._session,
        const WorkoutTemplateDraft(
          name: 'Unconfirmed draft',
          description: '',
          durationMinutes: 0,
          goal: '',
          exercises: [
            WorkoutExerciseDraft(
              exerciseId: 111,
              exerciseName: 'Bench Press',
              notes: '',
              targetSets: 3,
              targetReps: 8,
              sets: [],
            ),
          ],
        ),
      ),
      throwsA(
        isA<AppError>().having(
          (error) => error.code,
          'code',
          AppErrorCode.malformedResponse,
        ),
      ),
    );
  });

  test('authoritative empty template list clears the previous cache', () async {
    final adapter = _CapturingDioAdapter()
      ..templateList = [
        {
          'template_id': 20,
          'name': 'Cached template',
          'description': '',
          'exercises': <Object>[],
        },
      ];
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiWorkoutRepository(dio);

    expect(await repository.loadTemplates(_ReadyAuthRepository._session),
        hasLength(1));
    adapter.templateList = [];

    expect(
        await repository.loadTemplates(_ReadyAuthRepository._session), isEmpty);
    expect(repository.templatesAreStale, isFalse);
  });

  test('dirty template checkpoint survives a store restart', () async {
    SharedPreferences.setMockInitialValues({});
    const store = WorkoutTemplateDraftStore();
    const draft = WorkoutTemplateDraft(
      name: 'Recovered draft',
      description: 'Still editing',
      durationMinutes: 45,
      goal: 'Strength',
      exercises: [],
    );

    await store.write(_ReadyAuthRepository._session, draft);
    final recovered = await const WorkoutTemplateDraftStore()
        .load(_ReadyAuthRepository._session);

    expect(recovered?.name, 'Recovered draft');
    expect(recovered?.description, 'Still editing');
  });

  test('active session is unique, isolated from template, and restarts',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = _activeTestContainer(MockWorkoutRepository());
    await container.read(appDraftProvider.future);
    await container.read(activeWorkoutProvider.future);
    final controller = container.read(activeWorkoutProvider.notifier);

    const template = WorkoutTemplateDraft(
      templateId: 42,
      name: 'Durable Push',
      description: '',
      durationMinutes: 0,
      goal: '',
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
              isCompleted: false,
              rpe: 7,
            ),
          ],
        ),
      ],
    );

    final first = await controller.startOrResume(template);
    final repeated = await controller.startOrResume(template);
    expect(repeated.sessionId, first.sessionId);

    controller.updateSet(
      0,
      0,
      first.exercises.single.sets.single.copyWith(
        reps: 10,
        weightKg: 65,
      ),
    );
    for (var index = 0; index < 8; index++) {
      controller.updateNotes('rapid edit $index');
    }
    await Future.wait([controller.checkpointNow(), controller.checkpointNow()]);

    final checkpoint = await const ActiveWorkoutCheckpointStore()
        .load(_ReadyAuthRepository._session);
    expect(checkpoint.session?.notes, 'rapid edit 7');
    expect(checkpoint.session?.exercises.single.sets.single.reps, 10);
    expect(
        checkpoint.session?.localStatus, ActiveWorkoutLocalStatus.checkpointed);
    expect(template.exercises.single.sets.single.reps, 8);
    expect(template.exercises.single.sets.single.weightKg, 60);

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    controller.setRestDeadline(deadline);
    expect(controller.restRemaining(DateTime.now()).inSeconds,
        inInclusiveRange(28, 30));
    await controller.checkpointNow();
    container.dispose();

    final restoredContainer = _activeTestContainer(MockWorkoutRepository());
    addTearDown(restoredContainer.dispose);
    await restoredContainer.read(appDraftProvider.future);
    final restored = await restoredContainer.read(activeWorkoutProvider.future);
    expect(restored.session?.sessionId, first.sessionId);
    expect(restored.session?.notes, 'rapid edit 7');
    expect(restored.session?.restDeadline, deadline);
  });

  test('finish is exactly once and creates read-only completed history',
      () async {
    final repository = _CountingCompletionRepository();
    final container = _activeTestContainer(repository);
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);
    await container.read(activeWorkoutProvider.future);
    final controller = container.read(activeWorkoutProvider.notifier);
    final active = await controller.startOrResume(
      const WorkoutTemplateDraft(
        templateId: 7,
        name: 'Finish Once',
        description: '',
        durationMinutes: 0,
        goal: '',
        exercises: [],
      ),
    );

    final results =
        await Future.wait([controller.finish(), controller.finish()]);
    expect(repository.finishCount, 1);
    expect(results.whereType<WorkoutMutationResult>(), hasLength(2));
    expect(container.read(activeWorkoutProvider).value?.session, isNull);
    final completed = container.read(appDraftProvider).value!.workoutLog;
    expect(completed.workoutLogId, 1);
    expect(completed.endedAtLabel, isNotEmpty);
    expect(completed.isInProgress, isFalse);
    expect(repository.lastMutationId, active.sessionId);
  });

  test('network-pending finish remains durable until explicit discard',
      () async {
    final container = _activeTestContainer(_PendingCompletionRepository());
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);
    await container.read(activeWorkoutProvider.future);
    final controller = container.read(activeWorkoutProvider.notifier);
    await controller.startOrResume(
      const WorkoutTemplateDraft(
        templateId: 8,
        name: 'Offline Finish',
        description: '',
        durationMinutes: 0,
        goal: '',
        exercises: [],
      ),
    );

    final result = await controller.finish();
    expect(result?.syncStatus, WorkoutSyncStatus.pendingSync);
    expect(container.read(activeWorkoutProvider).value?.session?.isFinishing,
        isTrue);
    expect(
      (await const ActiveWorkoutCheckpointStore()
              .load(_ReadyAuthRepository._session))
          .session,
      isNotNull,
    );

    await controller.discard();
    expect(container.read(activeWorkoutProvider).value?.session, isNull);
    expect(
      (await const ActiveWorkoutCheckpointStore()
              .load(_ReadyAuthRepository._session))
          .session,
      isNull,
    );
  });

  test('token expiry keeps the active checkpoint for later recovery', () async {
    final container = _activeTestContainer(_ExpiredCompletionRepository());
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);
    await container.read(activeWorkoutProvider.future);
    final controller = container.read(activeWorkoutProvider.notifier);
    await controller.startOrResume(
      const WorkoutTemplateDraft(
        templateId: 9,
        name: 'Token Refresh Session',
        description: '',
        durationMinutes: 0,
        goal: '',
        exercises: [],
      ),
    );

    await expectLater(
        controller.finish(), throwsA(isA<AuthSessionExpiredException>()));
    expect(
      (await const ActiveWorkoutCheckpointStore()
              .load(_ReadyAuthRepository._session))
          .session,
      isNotNull,
    );
  });

  test('corrupted checkpoint is removed and user checkpoints are isolated',
      () async {
    SharedPreferences.setMockInitialValues({
      'jimbro.active_workout.v1.test-user': '{damaged',
    });
    const store = ActiveWorkoutCheckpointStore();
    final damaged = await store.load(_ReadyAuthRepository._session);
    expect(damaged.corrupted, isTrue);
    expect(damaged.session, isNull);

    const other = AuthSession(
      userId: 'other-user',
      displayName: 'Other',
      email: 'other@example.test',
      accessToken: 'other-token',
      provider: 'test',
    );
    final now = DateTime.now();
    await store.write(
      _ReadyAuthRepository._session,
      ActiveWorkoutSession(
        sessionId: 'owned-session',
        sourceTemplateId: null,
        name: 'Owned',
        notes: '',
        exercises: const [],
        startedAt: now,
        lastCheckpointAt: now,
        revision: 1,
        restDeadline: null,
        localStatus: ActiveWorkoutLocalStatus.checkpointed,
        remoteStatus: ActiveWorkoutRemoteStatus.localOnly,
        lifecycle: ActiveWorkoutLifecycle.active,
      ),
    );
    expect((await store.load(other)).session, isNull);
  });
}

ProviderContainer _activeTestContainer(WorkoutRepository repository) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_ReadyAuthRepository()),
      profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
      workoutRepositoryProvider.overrideWithValue(repository),
      nutritionRepositoryProvider.overrideWithValue(MockNutritionRepository()),
      consistencyRepositoryProvider.overrideWithValue(
        MockConsistencyRepository(),
      ),
      atlasRepositoryProvider.overrideWithValue(MockAtlasRepository()),
      searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
    ],
  );
}

class _CountingCompletionRepository extends MockWorkoutRepository {
  int finishCount = 0;
  String? lastMutationId;

  @override
  Future<WorkoutMutationResult> finishWorkout(
    AuthSession? session,
    WorkoutLogDraft log, {
    required String mutationId,
  }) {
    finishCount += 1;
    lastMutationId = mutationId;
    return super.finishWorkout(session, log, mutationId: mutationId);
  }
}

class _PendingCompletionRepository extends MockWorkoutRepository {
  @override
  Future<WorkoutMutationResult> finishWorkout(
    AuthSession? session,
    WorkoutLogDraft log, {
    required String mutationId,
  }) async {
    return WorkoutMutationResult(
      localWorkoutId: 'pending-$mutationId',
      mutationId: mutationId,
      syncStatus: WorkoutSyncStatus.pendingSync,
      errorCode: 'NETWORK_UNAVAILABLE',
      retryable: true,
      authoritativeWorkout: log,
    );
  }
}

class _ExpiredCompletionRepository extends MockWorkoutRepository {
  @override
  Future<WorkoutMutationResult> finishWorkout(
    AuthSession? session,
    WorkoutLogDraft log, {
    required String mutationId,
  }) {
    throw const AuthSessionExpiredException('Expired during finish.');
  }
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
  Future<WorkoutMutationResult> saveWorkoutLog(
    AuthSession? session,
    WorkoutLogDraft log,
  ) async {
    capturedLog = log;
    final saved = log.copyWith(workoutLogId: 1);
    return WorkoutMutationResult(
      localWorkoutId: 'local-test',
      serverLogId: 1,
      mutationId: 'test-mutation',
      syncStatus: WorkoutSyncStatus.synced,
      errorCode: null,
      retryable: false,
      authoritativeWorkout: saved,
    );
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
  Future<List<ExerciseSuggestion>> searchExercises(
    String query, [
    AuthSession? session,
  ]) async {
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

class _ExerciseSearchDioAdapter implements HttpClientAdapter {
  final queryParameters = <Map<String, dynamic>>[];
  final headers = <Map<String, dynamic>>[];
  int statusCode = 200;
  bool offline = false;
  bool timeout = false;
  bool empty = false;
  bool malformed = false;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET' && options.path == '/exercises/search') {
      queryParameters.add(Map<String, dynamic>.from(options.queryParameters));
      headers.add(Map<String, dynamic>.from(options.headers));
      if (offline) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'offline',
        );
      }
      if (timeout) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      }
      if (statusCode != 200) {
        return _json(statusCode, {'detail': 'search rejected'});
      }
      if (empty) {
        return _json(200, {'success': true, 'data': <Object>[]});
      }
      if (malformed) {
        return _json(200, {
          'success': true,
          'data': [
            {'exercise_id': null, 'name': ''}
          ],
        });
      }
      return _json(200, {
        'success': true,
        'data': [
          {
            'exercise_id': 111,
            'name': 'Bench Press',
            'category': 'Barbell',
            'primary_muscle': 'chest',
          },
        ],
      });
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

class _CapturingDioAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastPostPayload;
  Map<String, dynamic>? lastTemplatePayload;
  Map<String, dynamic>? validationError;
  bool rejectRichTemplateOnce = false;
  bool rejectRichWorkoutLogOnce = false;
  bool omitTemplateId = false;
  List<Map<String, dynamic>> templateList = [];
  final List<Map<String, dynamic>> templatePayloads = [];
  final List<String> templateIdempotencyKeys = [];
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
      templateIdempotencyKeys
          .add(options.headers['Idempotency-Key']?.toString() ?? '');
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
            if (!omitTemplateId) 'template_id': 20,
            ...lastTemplatePayload!,
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'GET' && options.path == '/workout-templates') {
      return ResponseBody.fromString(
        jsonEncode({'success': true, 'data': templateList}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'POST' && options.path == '/workout-logs') {
      lastPostPayload = Map<String, dynamic>.from(options.data as Map);
      workoutLogPayloads.add(lastPostPayload!);
      if (rejectRichWorkoutLogOnce && workoutLogPayloads.length == 1) {
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
      workoutLogPayloads.add(Map<String, dynamic>.from(options.data as Map));
      if (offline) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'offline',
        );
      }
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
