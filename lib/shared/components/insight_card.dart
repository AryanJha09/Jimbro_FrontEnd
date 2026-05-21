import 'package:flutter/material.dart';

import '../../core/theme/jim_tokens.dart';
import '../models/atlas_insight.dart';
import 'jim_surface.dart';

class InsightCard extends StatelessWidget {
  const InsightCard({
    super.key,
    required this.insight,
  });

  final AtlasInsight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = switch (insight.confidence) {
      AtlasConfidence.high => JimColors.success,
      AtlasConfidence.medium => JimColors.warning,
      AtlasConfidence.low => JimColors.terracotta,
    };

    return JimSurface(
      backgroundColor: insight.isMythBust
          ? const Color(0xFFF4EFE7)
          : JimColors.plaque.withValues(alpha: .9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(JimRadius.pill),
                ),
                child: Text(
                  insight.isMythBust ? 'MYTH / REALITY' : 'ATLAS NOTE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: JimColors.inkMuted,
              ),
            ],
          ),
          const SizedBox(height: JimSpacing.md),
          Text(insight.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(
            insight.mainText,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: JimColors.inkSoft,
              height: 1.55,
            ),
          ),
          if (insight.actionItems.isNotEmpty) ...[
            const SizedBox(height: JimSpacing.md),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: insight.actionItems
                  .map(
                    (item) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(JimRadius.pill),
                        color: JimColors.galleryWhite,
                        border: Border.all(color: JimColors.line),
                      ),
                      child: Text(
                        item,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: JimColors.inkSoft,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (insight.learnMoreKey != null) ...[
            const SizedBox(height: JimSpacing.md),
            Text(
              'Learn more key: ${insight.learnMoreKey}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: JimColors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
