enum AtlasConfidence {
  high,
  medium,
  low,
}

class AtlasInsight {
  const AtlasInsight({
    required this.title,
    required this.mainText,
    required this.confidence,
    this.actionItems = const <String>[],
    this.learnMoreKey,
    this.isMythBust = false,
  });

  final String title;
  final String mainText;
  final AtlasConfidence confidence;
  final List<String> actionItems;
  final String? learnMoreKey;
  final bool isMythBust;

  AtlasInsight copyWith({
    String? title,
    String? mainText,
    AtlasConfidence? confidence,
    List<String>? actionItems,
    String? learnMoreKey,
    bool? isMythBust,
  }) {
    return AtlasInsight(
      title: title ?? this.title,
      mainText: mainText ?? this.mainText,
      confidence: confidence ?? this.confidence,
      actionItems: actionItems ?? this.actionItems,
      learnMoreKey: learnMoreKey ?? this.learnMoreKey,
      isMythBust: isMythBust ?? this.isMythBust,
    );
  }
}
