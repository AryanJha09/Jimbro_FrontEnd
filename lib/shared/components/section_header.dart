import 'package:flutter/material.dart';

import '../../core/theme/jim_tokens.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: theme.textTheme.labelLarge?.copyWith(
                  letterSpacing: 1.2,
                  color: JimColors.inkMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(title, style: theme.textTheme.headlineSmall),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
