import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/repositories/app_repositories.dart';
import '../../../shared/models/jim_chat_models.dart';

final jimChatControllerProvider =
    AutoDisposeNotifierProvider<JimChatController, JimChatState>(
  JimChatController.new,
);

class JimChatState {
  const JimChatState({
    required this.session,
    required this.messages,
    this.clarificationOptions = const [],
    this.isSending = false,
    this.error,
  });

  final JimChatSession session;
  final List<JimChatMessage> messages;
  final List<JimClarificationOption> clarificationOptions;
  final bool isSending;
  final String? error;

  JimChatState copyWith({
    JimChatSession? session,
    List<JimChatMessage>? messages,
    List<JimClarificationOption>? clarificationOptions,
    bool? isSending,
    Object? error = _unset,
  }) {
    return JimChatState(
      session: session ?? this.session,
      messages: messages ?? this.messages,
      clarificationOptions: clarificationOptions ?? this.clarificationOptions,
      isSending: isSending ?? this.isSending,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

const _unset = Object();

class JimChatController extends AutoDisposeNotifier<JimChatState> {
  JimChatRepository get _repository => ref.read(jimChatRepositoryProvider);

  @override
  JimChatState build() {
    final sessionId = 'jim-${DateTime.now().microsecondsSinceEpoch}';
    return JimChatState(
      session: JimChatSession(sessionId: sessionId),
      messages: const [
        JimChatMessage(
          id: 'welcome',
          role: JimChatRole.assistant,
          text: 'Ask Jim about training, nutrition, or general fitness.',
        ),
      ],
    );
  }

  void setMode(JimChatMode mode) {
    if (state.isSending) {
      return;
    }
    state = state.copyWith(
      session: JimChatSession(
        sessionId: state.session.sessionId,
        mode: mode,
      ),
    );
  }

  Future<void> endSession() async {
    final draft = ref.read(appDraftProvider).valueOrNull;
    if (draft?.session == null || _repository is MockJimChatRepository) {
      return;
    }
    try {
      await _repository.endSession(draft?.session, state.session.sessionId);
    } catch (_) {
      // Leaving chat should not be blocked by best-effort session cleanup.
    }
  }

  Future<void> sendMessage(String rawMessage) async {
    final message = rawMessage.trim();
    if (message.isEmpty || state.isSending) {
      return;
    }
    final userMessage = JimChatMessage(
      id: _messageId('user'),
      role: JimChatRole.user,
      text: message,
    );
    final assistantId = _messageId('assistant');
    state = state.copyWith(
      messages: [
        ...state.messages,
        userMessage,
        JimChatMessage(
          id: assistantId,
          role: JimChatRole.assistant,
          text: '',
          isStreaming: true,
          isLocalMock: _repository is MockJimChatRepository,
        ),
      ],
      clarificationOptions: const [],
      isSending: true,
      error: null,
    );

    try {
      final draft = await ref.read(appDraftProvider.future);
      JimChatResponse? finalResponse;
      await for (final event in _repository.stream(
        draft.session,
        sessionId: state.session.sessionId,
        message: message,
        mode: state.session.mode,
      )) {
        switch (event.type) {
          case JimChatStreamEventType.textDelta:
            _appendDelta(assistantId, event.text);
          case JimChatStreamEventType.done:
            finalResponse = event.response;
          case JimChatStreamEventType.error:
            throw Exception(event.error ?? 'Jim chat stream failed.');
        }
      }
      await _finishResponse(assistantId, finalResponse);
    } catch (error) {
      _markFailed(assistantId, error);
    }
  }

  Future<void> selectClarification(JimClarificationOption option) async {
    if (state.isSending) {
      return;
    }
    final userMessage = JimChatMessage(
      id: _messageId('selection'),
      role: JimChatRole.user,
      text: option.label,
    );
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      clarificationOptions: const [],
      isSending: true,
      error: null,
    );
    try {
      final draft = await ref.read(appDraftProvider.future);
      final response = await _repository.send(
        draft.session,
        sessionId: state.session.sessionId,
        message: '',
        mode: state.session.mode,
        selectedOption: option.id,
      );
      final text = _responseText(response);
      state = state.copyWith(
        messages: [
          ...state.messages,
          JimChatMessage(
            id: _messageId('assistant'),
            role: JimChatRole.assistant,
            text: text,
            isLocalMock: _repository is MockJimChatRepository,
          ),
        ],
        clarificationOptions: response.clarificationOptions,
        isSending: false,
      );
      await _refreshFor(response.actionsTaken);
    } catch (error) {
      state = state.copyWith(
        isSending: false,
        error: _friendlyError(error),
      );
    }
  }

  Future<void> _finishResponse(
    String assistantId,
    JimChatResponse? response,
  ) async {
    final messages = state.messages.map((message) {
      if (message.id != assistantId) {
        return message;
      }
      final responseText = response == null ? '' : _responseText(response);
      return message.copyWith(
        text: message.text.trim().isEmpty ? responseText : message.text,
        isStreaming: false,
      );
    }).toList(growable: false);
    state = state.copyWith(
      messages: messages,
      clarificationOptions: response?.clarificationOptions ?? const [],
      isSending: false,
    );
    await _refreshFor(response?.actionsTaken ?? const []);
  }

  void _appendDelta(String assistantId, String delta) {
    if (delta.isEmpty) {
      return;
    }
    state = state.copyWith(
      messages: state.messages
          .map(
            (message) => message.id == assistantId
                ? message.copyWith(text: '${message.text}$delta')
                : message,
          )
          .toList(growable: false),
    );
  }

  void _markFailed(String assistantId, Object error) {
    final messages = state.messages
        .where(
            (message) => message.id != assistantId || message.text.isNotEmpty)
        .map(
          (message) => message.id == assistantId
              ? message.copyWith(isStreaming: false)
              : message,
        )
        .toList(growable: false);
    state = state.copyWith(
      messages: messages,
      isSending: false,
      error: _friendlyError(error),
    );
  }

  Future<void> _refreshFor(List<String> actions) async {
    if (actions.isEmpty) {
      return;
    }
    await ref.read(appDraftProvider.notifier).refreshAfterJimActions(actions);
  }

  String _responseText(JimChatResponse response) {
    final message = response.message.trim();
    if (message.isNotEmpty) {
      return message;
    }
    final prompt = response.clarificationPrompt?.trim() ?? '';
    return prompt.isNotEmpty ? prompt : 'Jim completed the request.';
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.isEmpty
        ? 'Jim could not respond. Your message was not logged.'
        : text;
  }

  String _messageId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}
