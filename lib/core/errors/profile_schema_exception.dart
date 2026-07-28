enum ProfileProcessingStage {
  envelopeExtraction,
  dtoParsing,
  domainMapping,
  profileValidation,
  localPersistence,
  completenessEvaluation,
}

class ProfileSchemaException implements Exception {
  const ProfileSchemaException({
    required this.stage,
    required this.sanitizedMessage,
    required this.exceptionType,
    required this.stackTrace,
    this.topLevelKeys = const <String>[],
    this.dataKeys = const <String>[],
    this.fieldShapes = const <String, String>{},
  });

  final ProfileProcessingStage stage;
  final String sanitizedMessage;
  final String exceptionType;
  final StackTrace stackTrace;
  final List<String> topLevelKeys;
  final List<String> dataKeys;
  final Map<String, String> fieldShapes;

  @override
  String toString() => sanitizedMessage;
}
