enum JimChatMode { workout, nutrition, knowledge, general }

extension JimChatModeWire on JimChatMode {
  String get wireName => name;
}

enum JimChatRole { user, assistant }

class JimChatMessage {
  const JimChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.isStreaming = false,
    this.isLocalMock = false,
  });

  final String id;
  final JimChatRole role;
  final String text;
  final bool isStreaming;
  final bool isLocalMock;

  JimChatMessage copyWith({
    String? text,
    bool? isStreaming,
  }) {
    return JimChatMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      isStreaming: isStreaming ?? this.isStreaming,
      isLocalMock: isLocalMock,
    );
  }
}

class JimChatSession {
  const JimChatSession({
    required this.sessionId,
    this.mode = JimChatMode.general,
  });

  final String sessionId;
  final JimChatMode mode;
}

class JimClarificationOption {
  const JimClarificationOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class JimChatResponse {
  const JimChatResponse({
    required this.sessionId,
    required this.message,
    this.requiresClarification = false,
    this.clarificationPrompt,
    this.clarificationOptions = const [],
    this.actionsTaken = const [],
  });

  final String sessionId;
  final String message;
  final bool requiresClarification;
  final String? clarificationPrompt;
  final List<JimClarificationOption> clarificationOptions;
  final List<String> actionsTaken;
}

enum JimChatStreamEventType { textDelta, done, error }

class JimChatStreamEvent {
  const JimChatStreamEvent._({
    required this.type,
    this.text = '',
    this.response,
    this.error,
  });

  final JimChatStreamEventType type;
  final String text;
  final JimChatResponse? response;
  final String? error;

  factory JimChatStreamEvent.textDelta(String text) => JimChatStreamEvent._(
        type: JimChatStreamEventType.textDelta,
        text: text,
      );

  factory JimChatStreamEvent.done(JimChatResponse response) =>
      JimChatStreamEvent._(
        type: JimChatStreamEventType.done,
        response: response,
      );

  factory JimChatStreamEvent.error(String error) => JimChatStreamEvent._(
        type: JimChatStreamEventType.error,
        error: error,
      );
}
