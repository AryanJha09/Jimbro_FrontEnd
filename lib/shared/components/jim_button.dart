import 'package:flutter/material.dart';

import '../../core/theme/jim_tokens.dart';

class JimPrimaryButton extends StatelessWidget {
  const JimPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: JimColors.plaque,
        foregroundColor: JimColors.ink,
        padding: const EdgeInsets.symmetric(
          horizontal: JimSpacing.lg,
          vertical: JimSpacing.md,
        ),
        side: const BorderSide(color: JimColors.insetLine),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JimRadius.pill),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 10),
          ],
          Text(label),
        ],
      ),
    );
  }
}

class JimSecondaryButton extends StatelessWidget {
  const JimSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: JimColors.accent,
        side: const BorderSide(color: JimColors.accentLine),
        padding: const EdgeInsets.symmetric(
          horizontal: JimSpacing.lg,
          vertical: JimSpacing.md,
        ),
        backgroundColor: JimColors.accentSoft.withValues(alpha: .28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JimRadius.pill),
        ),
      ),
      child: Text(label),
    );
  }
}
