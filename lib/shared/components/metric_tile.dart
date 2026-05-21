import 'package:flutter/material.dart';

import '../../core/theme/jim_tokens.dart';
import '../models/dashboard_models.dart';
import 'jim_surface.dart';

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.metric,
    this.onTap,
  });

  final MetricSnapshot metric;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(JimRadius.md),
        child: JimSurface(
          padding: const EdgeInsets.all(JimSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  letterSpacing: 1,
                  color: JimColors.inkMuted,
                ),
              ),
              const SizedBox(height: 10),
              Text(metric.value, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                metric.detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: JimColors.inkSoft,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    'Open detail',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: JimColors.accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: JimColors.accent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
