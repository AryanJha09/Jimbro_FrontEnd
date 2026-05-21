class MetricSnapshot {
  const MetricSnapshot({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;
}

class DailyAction {
  const DailyAction({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
}
