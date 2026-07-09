import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/core/navigation/app_state.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/features/atlas/application/jim_chat_controller.dart';
import 'package:jimbro/features/atlas/presentation/atlas_chat_page.dart';
import 'package:jimbro/shared/models/app_models.dart';
import 'package:jimbro/shared/models/jim_chat_models.dart';

void main() {
  test('maps documented standard chat reply, type, and options', () {
    final response = jimChatResponseFromBackend({
      'data': {
        'session_id': 'chat-1',
        'reply': 'Which meal?',
        'type': 'clarification',
        'prompt': 'Choose a meal type.',
        'options': [
          {'id': 'breakfast', 'label': 'Breakfast'},
          {'id': 'lunch', 'label': 'Lunch'},
        ],
        'actions_taken': ['read_context'],
      },
    });

    expect(response.sessionId, 'chat-1');
    expect(response.requiresClarification, isTrue);
    expect(response.clarificationOptions.last.label, 'Lunch');
    expect(response.actionsTaken, ['read_context']);
  });

  test('clarification selection sends empty message and selected_option',
      () async {
    final adapter = _ChatAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;

    final response = await FastApiJimChatRepository(dio).send(
      _session,
      sessionId: 'chat-2',
      message: 'ignored',
      mode: JimChatMode.nutrition,
      selectedOption: 'breakfast',
    );

    expect(adapter.payload?['session_id'], 'chat-2');
    expect(adapter.payload?['message'], '');
    expect(adapter.payload?['selected_option'], 'breakfast');
    expect(adapter.payload?['mode'], 'nutrition');
    expect(response.actionsTaken, ['log_food']);
  });

  test('parses SSE text deltas, done actions, and errors', () async {
    final bytes = Stream<List<int>>.fromIterable([
      utf8.encode('event: text_delta\ndata: {"text_delta":"Hel"}\n\n'),
      utf8.encode('data: {"type":"text_delta","delta":"lo"}\n\n'),
      utf8.encode(
        'event: done\ndata: {"session_id":"s1","message":"Hello","actions_taken":["log_workout"]}\n\n',
      ),
      utf8.encode('event: error\ndata: {"message":"stream failed"}\n\n'),
    ]);

    final events = await parseJimChatSse(bytes).toList();

    expect(events[0].text, 'Hel');
    expect(events[1].text, 'lo');
    expect(events[2].response?.actionsTaken, ['log_workout']);
    expect(events[3].error, 'stream failed');
  });

  test('parses plain text, JSON chunks, and done sentinel', () async {
    final bytes = Stream<List<int>>.fromIterable([
      utf8.encode('Plain reply\n\n'),
      utf8.encode('{"type":"text_delta","reply":" JSON"}\n\n'),
      utf8.encode('data: [DONE]\n\n'),
    ]);

    final events = await parseJimChatSse(bytes).toList();

    expect(events.map((event) => event.type), [
      JimChatStreamEventType.textDelta,
      JimChatStreamEventType.textDelta,
      JimChatStreamEventType.done,
    ]);
    expect(events[0].text, 'Plain reply');
    expect(events[1].text, ' JSON');
  });

  test('live chat stream requests an SSE response and deletes sessions',
      () async {
    final adapter = _StreamChatAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.example.test/api/v1',
        validateStatus: (status) => status != null && status < 500,
      ),
    )..httpClientAdapter = adapter;
    final repository = FastApiJimChatRepository(dio);

    final events = await repository
        .stream(
          _session,
          sessionId: 'chat-stream',
          message: 'Hello Jim',
          mode: JimChatMode.general,
        )
        .toList();
    await repository.endSession(_session, 'chat-stream');

    expect(adapter.streamResponseType, ResponseType.stream);
    expect(events.single.text, 'Hello');
    expect(adapter.deletePath, '/chat/chat-stream');
  });

  test('controller exposes clarification and refreshes by completed action',
      () async {
    final draftController = _TrackingDraftController();
    final chatRepository = _ClarifyingChatRepository();
    final container = ProviderContainer(
      overrides: [
        appDraftProvider.overrideWith(() => draftController),
        jimChatRepositoryProvider.overrideWithValue(chatRepository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appDraftProvider.future);
    final controller = container.read(jimChatControllerProvider.notifier);

    await controller.sendMessage('Log my meal');
    expect(
      container.read(jimChatControllerProvider).clarificationOptions.single.id,
      'lunch',
    );

    await controller.selectClarification(
      const JimClarificationOption(id: 'lunch', label: 'Lunch'),
    );

    expect(chatRepository.selectedOption, 'lunch');
    expect(draftController.refreshedActions, ['log_food']);
    expect(container.read(jimChatControllerProvider).isSending, isFalse);
  });

  test('mock chat clearly states no backend action was performed', () async {
    final response = await MockJimChatRepository().send(
      _session,
      sessionId: 'mock-chat',
      message: 'Log a workout',
      mode: JimChatMode.workout,
    );

    expect(response.actionsTaken, isEmpty);
    expect(response.message, contains('Local mock response'));
    expect(response.message, contains('No backend action'));
  });

  testWidgets('clarification chip submits the selected option', (tester) async {
    final draftController = _TrackingDraftController();
    final repository = _ClarifyingChatRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDraftProvider.overrideWith(() => draftController),
          jimChatRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: AtlasChatPage()),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('jim-chat-input')),
      'Log my meal',
    );
    await tester.tap(find.byKey(const ValueKey('jim-chat-send')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ActionChip, 'Lunch'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'Lunch'));
    await tester.pumpAndSettle();

    expect(repository.selectedOption, 'lunch');
    expect(find.text('Meal logged.'), findsOneWidget);
  });
}

const _session = AuthSession(
  userId: 'chat-user',
  displayName: 'Chat User',
  email: 'chat@example.com',
  accessToken: 'test-token',
  provider: 'fastapi',
);

class _ChatAdapter implements HttpClientAdapter {
  Map<String, dynamic>? payload;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    payload = Map<String, dynamic>.from(options.data as Map);
    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'session_id': 'chat-2',
          'message': 'Breakfast logged.',
          'actions_taken': ['log_food'],
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _StreamChatAdapter implements HttpClientAdapter {
  ResponseType? streamResponseType;
  String? deletePath;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST' && options.path == '/chat/stream') {
      streamResponseType = options.responseType;
      return ResponseBody(
        Stream.value(
          Uint8List.fromList(utf8.encode('data: {"text":"Hello"}\n\n')),
        ),
        200,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      );
    }
    if (options.method == 'DELETE') {
      deletePath = options.path;
    }
    return ResponseBody.fromString(
      '{"data":{}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _ClarifyingChatRepository implements JimChatRepository {
  String? selectedOption;

  @override
  Stream<JimChatStreamEvent> stream(
    AuthSession? session, {
    required String sessionId,
    required String message,
    required JimChatMode mode,
  }) async* {
    yield JimChatStreamEvent.textDelta('Which meal?');
    yield JimChatStreamEvent.done(
      JimChatResponse(
        sessionId: sessionId,
        message: 'Which meal?',
        requiresClarification: true,
        clarificationPrompt: 'Choose a meal.',
        clarificationOptions: const [
          JimClarificationOption(id: 'lunch', label: 'Lunch'),
        ],
      ),
    );
  }

  @override
  Future<JimChatResponse> send(
    AuthSession? session, {
    required String sessionId,
    required String message,
    required JimChatMode mode,
    String? selectedOption,
  }) async {
    this.selectedOption = selectedOption;
    return JimChatResponse(
      sessionId: sessionId,
      message: 'Meal logged.',
      actionsTaken: const ['log_food'],
    );
  }

  @override
  Future<void> endSession(AuthSession? session, String sessionId) async {}
}

class _TrackingDraftController extends AppDraftController {
  List<String> refreshedActions = const [];

  @override
  Future<AppDraftState> build() async => _draft;

  @override
  Future<void> refreshAfterJimActions(Iterable<String> actions) async {
    refreshedActions = actions.toList(growable: false);
  }
}

const _draft = AppDraftState(
  session: _session,
  profile: UserProfile(
    name: 'Chat User',
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
  template: WorkoutTemplateDraft.empty,
  templates: [],
  workoutSchedule: [],
  workoutLog: WorkoutLogDraft.empty,
  foodLogs: [],
  nutritionSummary: DailyNutritionSummary.empty,
  consistency: ConsistencyState(
    currentStreak: 0,
    longestStreak: 0,
    weeklyCheckins: 0,
    totalLogs: 0,
  ),
  search: SearchState(query: '', groups: []),
);
